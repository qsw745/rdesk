use super::tests::{api, authenticated_fixture};
use crate::AppState;
use axum::http::StatusCode;
use serde_json::{json, Value};

async fn create(s: &AppState) -> Value {
    let (status, body) = api(
        s,
        "POST",
        "/api/wake/pairings",
        "account",
        json!({"name":"书房电脑","device_id":"pc-123","mac":"02:11:22:33:44:55"}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["qr_proof"].as_str().unwrap().len(), 64);
    assert_eq!(body["manual_code"].as_str().unwrap().len(), 16);
    assert_ne!(body["qr_proof"], body["desktop_proof"]);
    body
}
async fn action(s: &AppState, p: &Value, name: &str, body: Value) -> (StatusCode, Value) {
    api(
        s,
        "POST",
        &format!("/api/wake/pairings/{}/{}", p["id"].as_str().unwrap(), name),
        "account",
        body,
    )
    .await
}
#[tokio::test]
async fn pairing_claim_is_confirmed_idempotent_and_draft_cannot_wake() {
    let (s, dir) = authenticated_fixture();
    let p = create(&s).await;
    let token = "ab".repeat(32);
    let claim = json!({"desktop_proof":p["desktop_proof"],"enrollment_token":token});
    assert_eq!(
        action(&s, &p, "claim", claim.clone()).await.0,
        StatusCode::CONFLICT
    );
    let (code, summary) = api(
        &s,
        "POST",
        "/api/wake/pairings/resolve",
        "account",
        json!({"manual_code":p["manual_code"]}),
    )
    .await;
    assert_eq!(code, StatusCode::OK);
    assert_eq!(summary["name"], "书房电脑");
    assert!(summary.get("desktop_proof").is_none());
    assert_eq!(
        action(&s, &p, "confirm", json!({"qr_proof":p["qr_proof"]}))
            .await
            .0,
        StatusCode::OK
    );
    assert_eq!(
        action(&s, &p, "confirm", json!({"qr_proof":p["qr_proof"]}))
            .await
            .0,
        StatusCode::CONFLICT
    );
    let (code, result) = action(&s, &p, "claim", claim.clone()).await;
    assert_eq!(code, StatusCode::OK);
    assert!(!result.to_string().contains(&token));
    assert_eq!(action(&s, &p, "claim", claim).await.1, result);
    assert_eq!(
        action(
            &s,
            &p,
            "claim",
            json!({"desktop_proof":p["desktop_proof"],"enrollment_token":"cd".repeat(32)})
        )
        .await
        .0,
        StatusCode::CONFLICT
    );
    let id = result["target_id"].as_str().unwrap();
    assert_eq!(
        api(
            &s,
            "POST",
            "/api/wake/requests",
            "account",
            json!({"target_id":id})
        )
        .await
        .1["code"],
        "setup_incomplete"
    );
    assert_eq!(
        api(
            &s,
            "POST",
            &format!("/api/wake/targets/{id}/heartbeat"),
            &token,
            json!({})
        )
        .await
        .0,
        StatusCode::OK
    );
    let target = s.users.get("owner").unwrap().wake.targets[0].clone();
    assert_ne!(target.token_hash, token);
    assert_eq!(s.users.get("owner").unwrap().wake.targets.len(), 1);
    std::fs::remove_dir_all(dir).unwrap();
}
#[tokio::test]
async fn cancelled_pairing_cannot_be_resolved_or_claimed() {
    let (s, _) = authenticated_fixture();
    let p = create(&s).await;
    assert_eq!(
        action(
            &s,
            &p,
            "cancel",
            json!({"desktop_proof":p["desktop_proof"]})
        )
        .await
        .0,
        StatusCode::OK
    );
    assert_ne!(
        api(
            &s,
            "POST",
            "/api/wake/pairings/resolve",
            "account",
            json!({"id":p["id"],"qr_proof":p["qr_proof"]})
        )
        .await
        .0,
        StatusCode::OK
    );
    assert_ne!(
        action(
            &s,
            &p,
            "claim",
            json!({"desktop_proof":p["desktop_proof"],"enrollment_token":"ab".repeat(32)})
        )
        .await
        .0,
        StatusCode::OK
    );
}

#[tokio::test]
async fn concurrent_confirmation_and_claim_create_exactly_one_target() {
    let (s, dir) = authenticated_fixture();
    let p = create(&s).await;
    let body = json!({"qr_proof":p["qr_proof"]});
    let (a, b) = tokio::join!(
        action(&s, &p, "confirm", body.clone()),
        action(&s, &p, "confirm", body)
    );
    assert!(
        (a.0 == StatusCode::OK && b.0 == StatusCode::CONFLICT)
            || (b.0 == StatusCode::OK && a.0 == StatusCode::CONFLICT)
    );
    let body = json!({"desktop_proof":p["desktop_proof"],"enrollment_token":"ab".repeat(32)});
    let (a, b) = tokio::join!(
        action(&s, &p, "claim", body.clone()),
        action(&s, &p, "claim", body)
    );
    assert_eq!(a.0, StatusCode::OK);
    assert_eq!(a, b);
    assert_eq!(s.users.get("owner").unwrap().wake.targets.len(), 1);
    std::fs::remove_dir_all(dir).unwrap();
}
#[tokio::test]
async fn failed_persistence_can_retry_without_losing_confirmed_session() {
    let (s, dir) = authenticated_fixture();
    let p = create(&s).await;
    action(&s, &p, "confirm", json!({"qr_proof":p["qr_proof"]})).await;
    std::fs::create_dir_all(dir.join("users.json")).unwrap();
    let body = json!({"desktop_proof":p["desktop_proof"],"enrollment_token":"ab".repeat(32)});
    assert_eq!(
        action(&s, &p, "claim", body.clone()).await.0,
        StatusCode::SERVICE_UNAVAILABLE
    );
    assert!(s.users.get("owner").unwrap().wake.targets.is_empty());
    assert_eq!(
        action(
            &s,
            &p,
            "status",
            json!({"desktop_proof":p["desktop_proof"]})
        )
        .await
        .1["state"],
        "confirmed"
    );
    std::fs::remove_dir(dir.join("users.json")).unwrap();
    assert_eq!(action(&s, &p, "claim", body).await.0, StatusCode::OK);
    std::fs::remove_dir_all(dir).unwrap();
}
#[tokio::test]
async fn removed_creator_or_logout_revocation_invalidates_phone_confirmation() {
    for logout in [false, true] {
        let (s, _) = authenticated_fixture();
        s.auth_sessions.insert(
            "phone".into(),
            crate::AuthSession {
                user_id: "owner".into(),
                last_seen_ms: crate::now_ms(),
            },
        );
        let p = create(&s).await;
        if logout {
            assert_eq!(
                api(
                    &s,
                    "POST",
                    "/api/wake/pairings/cancel-all",
                    "account",
                    json!({})
                )
                .await
                .0,
                StatusCode::OK
            );
        } else {
            s.auth_sessions.remove("account");
        }
        assert_eq!(
            api(
                &s,
                "POST",
                &format!("/api/wake/pairings/{}/confirm", p["id"].as_str().unwrap()),
                "phone",
                json!({"qr_proof":p["qr_proof"]})
            )
            .await
            .0,
            StatusCode::CONFLICT
        );
    }
}
#[tokio::test]
async fn expiry_cross_account_and_wrong_proofs_do_not_reveal_pc() {
    let (s, _) = authenticated_fixture();
    let mut second = s.users.get("owner").unwrap().clone();
    second.user_id = "other".into();
    s.users.insert("other".into(), second);
    s.auth_sessions.insert(
        "other".into(),
        crate::AuthSession {
            user_id: "other".into(),
            last_seen_ms: crate::now_ms(),
        },
    );
    let p = create(&s).await;
    let body = json!({"id":p["id"],"qr_proof":p["qr_proof"]});
    let (code, response) = api(
        &s,
        "POST",
        "/api/wake/pairings/resolve",
        "other",
        body.clone(),
    )
    .await;
    assert_eq!(code, StatusCode::NOT_FOUND);
    assert!(!response.to_string().contains("书房"));
    assert_eq!(
        api(
            &s,
            "POST",
            "/api/wake/pairings/resolve",
            "account",
            json!({"id":p["id"],"qr_proof":"cc".repeat(32)})
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    s.wake_runtime
        .pairings
        .lock()
        .await
        .sessions
        .get_mut(p["id"].as_str().unwrap())
        .unwrap()
        .expires = crate::now_ms();
    assert_eq!(
        api(&s, "POST", "/api/wake/pairings/resolve", "account", body)
            .await
            .0,
        StatusCode::GONE
    );
    assert_eq!(
        action(
            &s,
            &p,
            "claim",
            json!({"desktop_proof":p["desktop_proof"],"enrollment_token":"ab".repeat(32)})
        )
        .await
        .0,
        StatusCode::GONE
    );
}
#[tokio::test]
async fn creation_and_guessing_have_bounded_account_limits() {
    let (s, _) = authenticated_fixture();
    let p = create(&s).await;
    create(&s).await;
    create(&s).await;
    assert_eq!(
        api(
            &s,
            "POST",
            "/api/wake/pairings",
            "account",
            json!({"name":"x","device_id":"new","mac":"02:11:22:33:44:55"})
        )
        .await
        .0,
        StatusCode::TOO_MANY_REQUESTS
    );
    for _ in 0..20 {
        assert_eq!(
            api(
                &s,
                "POST",
                "/api/wake/pairings/resolve",
                "account",
                json!({"manual_code":"AAAAAAAAAAAAAAAA"})
            )
            .await
            .0,
            StatusCode::NOT_FOUND
        );
    }
    assert_eq!(
        api(
            &s,
            "POST",
            "/api/wake/pairings/resolve",
            "account",
            json!({"manual_code":p["manual_code"]})
        )
        .await
        .0,
        StatusCode::TOO_MANY_REQUESTS
    );
}
#[tokio::test]
async fn draft_completion_requires_enabled_own_helper_and_bios_then_allows_wake() {
    let (s, dir) = authenticated_fixture();
    let p = create(&s).await;
    action(&s, &p, "confirm", json!({"manual_code":p["manual_code"]})).await;
    let target = action(
        &s,
        &p,
        "claim",
        json!({"desktop_proof":p["desktop_proof"],"enrollment_token":"ab".repeat(32)}),
    )
    .await
    .1;
    let id = target["target_id"].as_str().unwrap();
    let path = format!("/api/wake/targets/{id}/complete");
    assert_eq!(
        api(
            &s,
            "POST",
            &path,
            "account",
            json!({"agent_id":"other","bios_confirmed":true})
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    let helper = api(
        &s,
        "POST",
        "/api/wake/agents",
        "account",
        json!({"name":"home"}),
    )
    .await
    .1;
    assert_eq!(
        api(
            &s,
            "POST",
            &path,
            "account",
            json!({"agent_id":helper["id"],"bios_confirmed":false})
        )
        .await
        .1["code"],
        "setup_incomplete"
    );
    assert_eq!(
        api(
            &s,
            "POST",
            &path,
            "account",
            json!({"agent_id":helper["id"],"bios_confirmed":true})
        )
        .await
        .0,
        StatusCode::OK
    );
    s.wake_runtime
        .agents
        .lock()
        .unwrap()
        .insert(helper["id"].as_str().unwrap().into(), crate::now_ms());
    assert_eq!(
        api(
            &s,
            "POST",
            "/api/wake/requests",
            "account",
            json!({"target_id":id})
        )
        .await
        .0,
        StatusCode::OK
    );
    // Reconfiguration cancels already queued packets.
    api(
        &s,
        "POST",
        &path,
        "account",
        json!({"agent_id":helper["id"],"bios_confirmed":true}),
    )
    .await;
    assert_eq!(
        s.users.get("owner").unwrap().wake.requests[0].phase,
        super::model::WakePhase::Cancelled
    );
    std::fs::remove_dir_all(dir).unwrap();
}
#[tokio::test]
async fn claim_retry_never_resurrects_deleted_or_rotated_binding() {
    for rotate in [true, false] {
        let (s, dir) = authenticated_fixture();
        let p = create(&s).await;
        action(&s, &p, "confirm", json!({"qr_proof":p["qr_proof"]})).await;
        let body = json!({"desktop_proof":p["desktop_proof"],"enrollment_token":"ab".repeat(32)});
        let result = action(&s, &p, "claim", body.clone()).await.1;
        let path = format!(
            "/api/wake/targets/{}{}",
            result["target_id"].as_str().unwrap(),
            if rotate { "/rotate-token" } else { "" }
        );
        assert_eq!(
            api(
                &s,
                if rotate { "POST" } else { "DELETE" },
                &path,
                "account",
                json!({})
            )
            .await
            .0,
            StatusCode::OK
        );
        assert_eq!(action(&s, &p, "claim", body).await.0, StatusCode::CONFLICT);
        std::fs::remove_dir_all(dir).unwrap();
    }
}
#[test]
fn old_targets_keep_setup_completion_without_schema_migration() {
    let t:super::model::WakeTarget=serde_json::from_value(json!({"id":"x","name":"x","device_id":"x","mac":"02:11:22:33:44:55","agent_id":"a","revision":1,"token_hash":"hash","created_at_ms":1})).unwrap();
    assert!(t.setup_complete);
}
