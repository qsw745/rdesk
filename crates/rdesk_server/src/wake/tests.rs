use super::model::*;
#[test]
fn mac_accepts_physical_unicast_and_rejects_invalid_targets() {
    assert_eq!(
        MacAddress::parse("02-11-22-33-44-55").unwrap().0,
        [2, 17, 34, 51, 68, 85]
    );
    for raw in [
        "01:00:5E:00:00:01",
        "FF:FF:FF:FF:FF:FF",
        "00:00:00:00:00:00",
        "02:11:22:33:44",
        "02:11:22:33:44:GG",
        "021122334455",
    ] {
        assert!(MacAddress::parse(raw).is_err(), "{raw}");
    }
}

fn request(phase: WakePhase, created: u64) -> WakeRequest {
    WakeRequest {
        id: created.to_string(),
        target_id: "pc".into(),
        agent_id: "phone".into(),
        target_revision: 1,
        created_at_ms: created,
        expires_at_ms: created + 30_000,
        observe_until_ms: created + 120_000,
        phase,
        claimed_at_ms: None,
        authorized_at_ms: None,
        sent_at_ms: None,
        online_at_ms: None,
        error_code: None,
    }
}
#[test]
fn stale_heartbeat_and_sent_packet_do_not_prove_boot() {
    let mut r = request(WakePhase::Sent, 1000);
    r.sent_at_ms = Some(2000);
    r.advance(3000, Some(900));
    assert_eq!(r.phase, WakePhase::Sent);
    r.advance(121000, None);
    assert_eq!(r.phase, WakePhase::Unconfirmed);
    let mut r = request(WakePhase::Sent, 1000);
    r.sent_at_ms = Some(2000);
    r.advance(3000, Some(2100));
    assert_eq!(r.phase, WakePhase::Online);
}
#[test]
fn restart_terminates_pending_and_retains_only_bounded_history() {
    let mut d = WakeAccountData::default();
    d.requests = (0..60)
        .map(|i| request(WakePhase::Queued, 1000 + i))
        .collect();
    d.recover_after_restart(2000);
    assert_eq!(d.requests.len(), 50);
    assert!(d.requests.iter().all(|r| r.phase == WakePhase::Interrupted));
    d.prune(7 * 24 * 60 * 60 * 1000 + 3000);
    assert!(d.requests.is_empty());
}

use super::store::update_wake;
use crate::{AppState, UserRecord};
fn fixture() -> (AppState, std::path::PathBuf) {
    let dir = std::env::temp_dir().join(format!("rdesk-wake-{}", uuid::Uuid::new_v4()));
    let state = AppState::new(dir.join("users.json").to_str().unwrap().into());
    let user:UserRecord=serde_json::from_value(serde_json::json!({"user_id":"owner","username":"owner","display_name":"owner","password_hash":"hash","created_at_ms":1})).unwrap();
    state.users.insert("owner".into(), user);
    (state, dir)
}
#[tokio::test]
async fn old_user_store_defaults_and_mutations_survive_reload() {
    let (state, dir) = fixture();
    assert!(state.users.get("owner").unwrap().wake.agents.is_empty());
    update_wake(&state, "owner", |d| {
        d.agents.push(WakeAgent {
            id: "a".into(),
            name: "安卓".into(),
            token_hash: "digest".into(),
            enabled: true,
        });
        Ok(())
    })
    .await
    .unwrap();
    let reloaded = AppState::new(state.user_store_path.to_string());
    crate::load_users(&reloaded).await.unwrap();
    assert_eq!(
        reloaded.users.get("owner").unwrap().wake.agents[0].name,
        "安卓"
    );
    std::fs::remove_dir_all(dir).unwrap();
}
#[tokio::test]
async fn failed_disk_write_never_changes_live_config() {
    let (state, dir) = fixture();
    std::fs::create_dir_all(dir.join("users.json")).unwrap();
    let result = update_wake(&state, "owner", |d| {
        d.agents.push(WakeAgent {
            id: "a".into(),
            name: "n".into(),
            token_hash: "h".into(),
            enabled: true,
        });
        Ok(())
    })
    .await;
    assert!(result.is_err());
    assert!(state.users.get("owner").unwrap().wake.agents.is_empty());
    std::fs::remove_dir_all(dir).unwrap();
}
#[tokio::test]
async fn concurrent_changes_do_not_overwrite_each_other() {
    let (state, dir) = fixture();
    let add = |id: &str| {
        let state = state.clone();
        let id = id.to_string();
        async move {
            update_wake(&state, "owner", |d| {
                d.agents.push(WakeAgent {
                    id,
                    name: "phone".into(),
                    token_hash: "h".into(),
                    enabled: true,
                });
                Ok(())
            })
            .await
        }
    };
    let (a, b) = tokio::join!(add("a"), add("b"));
    a.unwrap();
    b.unwrap();
    assert_eq!(state.users.get("owner").unwrap().wake.agents.len(), 2);
    std::fs::remove_dir_all(dir).unwrap();
}

use axum::{
    body::{to_bytes, Body},
    http::{HeaderMap, Request, StatusCode},
};
use tower::ServiceExt;
async fn api(
    state: &AppState,
    method: &str,
    path: &str,
    token: &str,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    let app = super::routes::routes().with_state(state.clone());
    let response = app
        .oneshot(
            Request::builder()
                .method(method)
                .uri(path)
                .header("Authorization", format!("Bearer {token}"))
                .header("Content-Type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = to_bytes(response.into_body(), 1_000_000).await.unwrap();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null),
    )
}
fn authenticated_fixture() -> (AppState, std::path::PathBuf) {
    let (state, dir) = fixture();
    state.auth_sessions.insert(
        "account".into(),
        crate::AuthSession {
            user_id: "owner".into(),
            last_seen_ms: crate::now_ms(),
        },
    );
    (state, dir)
}
#[tokio::test]
async fn routes_require_account_and_never_leak_other_accounts() {
    let (state, dir) = authenticated_fixture();
    assert_eq!(
        api(
            &state,
            "GET",
            "/api/wake/targets",
            "wrong",
            serde_json::json!({})
        )
        .await
        .0,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        api(
            &state,
            "GET",
            "/api/wake/targets",
            "account",
            serde_json::json!({})
        )
        .await
        .0,
        StatusCode::OK
    );
    assert_eq!(
        api(
            &state,
            "GET",
            "/api/wake/requests/not-mine",
            "account",
            serde_json::json!({})
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    let _ = std::fs::remove_dir_all(dir);
}
#[tokio::test]
async fn complete_wake_protocol_dedupes_and_confirms_only_target_heartbeat() {
    let (state, dir) = authenticated_fixture();
    let empty = serde_json::json!({});
    let (status, a) = api(
        &state,
        "POST",
        "/api/wake/agents",
        "account",
        serde_json::json!({"name":"安卓"}),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let aid = a["id"].as_str().unwrap();
    let at = a["token"].as_str().unwrap();
    let (status,t)=api(&state,"POST","/api/wake/targets","account",serde_json::json!({"name":"电脑","device_id":"pc","mac":"02:11:22:33:44:55","agent_id":aid})).await;
    assert_eq!(status, StatusCode::OK);
    let tid = t["id"].as_str().unwrap();
    let tt = t["token"].as_str().unwrap();
    assert_eq!(
        api(
            &state,
            "POST",
            "/api/wake/requests",
            "account",
            serde_json::json!({"target_id":tid})
        )
        .await
        .0,
        StatusCode::CONFLICT
    );
    state
        .wake_runtime
        .agents
        .lock()
        .unwrap()
        .insert(aid.into(), crate::now_ms());
    let (_, r) = api(
        &state,
        "POST",
        "/api/wake/requests",
        "account",
        serde_json::json!({"target_id":tid}),
    )
    .await;
    let rid = r["id"].as_str().unwrap();
    let (_, same) = api(
        &state,
        "POST",
        "/api/wake/requests",
        "account",
        serde_json::json!({"target_id":tid}),
    )
    .await;
    assert_eq!(same["id"], r["id"]);
    let (_, job) = api(
        &state,
        "POST",
        &format!("/api/wake/agents/{aid}/poll"),
        at,
        empty.clone(),
    )
    .await;
    assert_eq!(job["id"], rid);
    assert_eq!(job["mac"], "02:11:22:33:44:55");
    let result_path = format!("/api/wake/requests/{rid}/result");
    assert_eq!(
        api(
            &state,
            "POST",
            &result_path,
            tt,
            serde_json::json!({"phase":"sent"})
        )
        .await
        .0,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        api(
            &state,
            "POST",
            &format!("/api/wake/requests/{rid}/authorize-send"),
            at,
            empty.clone()
        )
        .await
        .0,
        StatusCode::OK
    );
    let (_, sent) = api(
        &state,
        "POST",
        &result_path,
        at,
        serde_json::json!({"phase":"sent"}),
    )
    .await;
    assert_eq!(sent["phase"], "sent");
    tokio::time::sleep(std::time::Duration::from_millis(2)).await;
    assert_eq!(
        api(
            &state,
            "POST",
            &format!("/api/wake/targets/{tid}/heartbeat"),
            tt,
            empty.clone()
        )
        .await
        .0,
        StatusCode::OK
    );
    let (_, online) = api(
        &state,
        "GET",
        &format!("/api/wake/requests/{rid}"),
        "account",
        empty,
    )
    .await;
    assert_eq!(online["phase"], "online");
    let (_, targets) = api(
        &state,
        "GET",
        "/api/wake/targets",
        "account",
        serde_json::json!({}),
    )
    .await;
    assert!(!targets.to_string().contains("token_hash"));
    std::fs::remove_dir_all(dir).unwrap();
}

async fn ready(state: &AppState) -> (String, String, String, String) {
    let (_, a) = api(
        state,
        "POST",
        "/api/wake/agents",
        "account",
        serde_json::json!({"name":"phone"}),
    )
    .await;
    let aid = a["id"].as_str().unwrap().to_owned();
    let at = a["token"].as_str().unwrap().to_owned();
    let (_, t) = api(
        state,
        "POST",
        "/api/wake/targets",
        "account",
        serde_json::json!({"name":"pc","device_id":"pc","mac":"02:11:22:33:44:55","agent_id":aid}),
    )
    .await;
    let tid = t["id"].as_str().unwrap().to_owned();
    state
        .wake_runtime
        .agents
        .lock()
        .unwrap()
        .insert(aid.clone(), crate::now_ms());
    let (_, r) = api(
        state,
        "POST",
        "/api/wake/requests",
        "account",
        serde_json::json!({"target_id":tid}),
    )
    .await;
    (aid, at, tid, r["id"].as_str().unwrap().into())
}
#[tokio::test]
async fn expired_cancelled_cross_account_requests_cannot_be_sent() {
    let (s, dir) = authenticated_fixture();
    let (aid, at, tid, rid) = ready(&s).await;
    let mut other = s.users.get("owner").unwrap().clone();
    other.user_id = "other".into();
    other.username = "other".into();
    other.wake = Default::default();
    s.users.insert("other".into(), other);
    s.auth_sessions.insert(
        "other-account".into(),
        crate::AuthSession {
            user_id: "other".into(),
            last_seen_ms: crate::now_ms(),
        },
    );
    for (method, path, body) in [
        (
            "GET",
            format!("/api/wake/requests/{rid}"),
            serde_json::json!({}),
        ),
        (
            "DELETE",
            format!("/api/wake/targets/{tid}"),
            serde_json::json!({}),
        ),
        (
            "POST",
            "/api/wake/requests".into(),
            serde_json::json!({"target_id":tid}),
        ),
    ] {
        assert_eq!(
            api(&s, method, &path, "other-account", body).await.0,
            StatusCode::NOT_FOUND
        );
    }
    api(
        &s,
        "POST",
        &format!("/api/wake/agents/{aid}/poll"),
        &at,
        serde_json::json!({}),
    )
    .await;
    {
        let mut u = s.users.get_mut("owner").unwrap();
        u.wake.requests[0].expires_at_ms = crate::now_ms() - 1;
    }
    assert_eq!(
        api(
            &s,
            "POST",
            &format!("/api/wake/requests/{rid}/authorize-send"),
            &at,
            serde_json::json!({})
        )
        .await
        .0,
        StatusCode::GONE
    );
    api(
        &s,
        "DELETE",
        &format!("/api/wake/agents/{aid}"),
        "account",
        serde_json::json!({}),
    )
    .await;
    assert_eq!(
        api(
            &s,
            "POST",
            &format!("/api/wake/requests/{rid}/result"),
            &at,
            serde_json::json!({"phase":"sent"})
        )
        .await
        .0,
        StatusCode::UNAUTHORIZED
    );
    std::fs::remove_dir_all(dir).unwrap();
}
#[tokio::test]
async fn changed_configuration_cancels_already_claimed_request() {
    let (s, dir) = authenticated_fixture();
    let (aid, at, tid, rid) = ready(&s).await;
    api(
        &s,
        "POST",
        &format!("/api/wake/agents/{aid}/poll"),
        &at,
        serde_json::json!({}),
    )
    .await;
    assert_eq!(
        api(
            &s,
            "PUT",
            &format!("/api/wake/targets/{tid}"),
            "account",
            serde_json::json!({"name":"renamed","mac":"02:11:22:33:44:66","agent_id":aid})
        )
        .await
        .0,
        StatusCode::OK
    );
    assert_eq!(
        api(
            &s,
            "POST",
            &format!("/api/wake/requests/{rid}/authorize-send"),
            &at,
            serde_json::json!({})
        )
        .await
        .0,
        StatusCode::CONFLICT
    );
    let (_, r) = api(
        &s,
        "GET",
        &format!("/api/wake/requests/{rid}"),
        "account",
        serde_json::json!({}),
    )
    .await;
    assert_eq!(r["phase"], "cancelled");
    std::fs::remove_dir_all(dir).unwrap();
}
#[tokio::test]
async fn account_delete_failure_preserves_wake_data_and_success_removes_it() {
    let (s, dir) = authenticated_fixture();
    let (aid, at, _, _) = ready(&s).await;
    s.users.get_mut("owner").unwrap().password_hash = crate::hash_password("password-123").unwrap();
    std::fs::remove_file(dir.join("users.json")).unwrap();
    std::fs::create_dir(dir.join("users.json")).unwrap();
    let mut h = HeaderMap::new();
    h.insert("authorization", "Bearer account".parse().unwrap());
    let failed = crate::delete_account(
        axum::extract::State(s.clone()),
        h.clone(),
        axum::Json(crate::DeleteAccountRequest {
            password: "password-123".into(),
        }),
    )
    .await;
    assert_eq!(failed.status(), StatusCode::INTERNAL_SERVER_ERROR);
    assert_eq!(s.users.get("owner").unwrap().wake.agents.len(), 1);
    assert!(s.auth_sessions.contains_key("account"));
    std::fs::remove_dir(dir.join("users.json")).unwrap();
    let success = crate::delete_account(
        axum::extract::State(s.clone()),
        h,
        axum::Json(crate::DeleteAccountRequest {
            password: "password-123".into(),
        }),
    )
    .await;
    assert_eq!(success.status(), StatusCode::OK);
    assert_eq!(
        api(
            &s,
            "POST",
            &format!("/api/wake/agents/{aid}/poll"),
            &at,
            serde_json::json!({})
        )
        .await
        .0,
        StatusCode::UNAUTHORIZED
    );
    let users: Vec<UserRecord> =
        serde_json::from_slice(&std::fs::read(dir.join("users.json")).unwrap()).unwrap();
    assert!(users.is_empty());
    std::fs::remove_dir_all(dir).unwrap();
}
#[tokio::test]
async fn diagnostics_expire_even_without_client_visits() {
    let (s, dir) = fixture();
    s.users
        .get_mut("owner")
        .unwrap()
        .wake
        .requests
        .push(request(WakePhase::Online, 1));
    super::routes::cleanup(&s).await;
    assert!(s.users.get("owner").unwrap().wake.requests.is_empty());
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test]
async fn helper_disable_and_reenable_preserves_binding_and_rejects_old_token() {
    let (s, dir) = authenticated_fixture();
    let empty = serde_json::json!({});
    let (_, a) = api(
        &s,
        "POST",
        "/api/wake/agents",
        "account",
        serde_json::json!({"name":"phone"}),
    )
    .await;
    let aid = a["id"].as_str().unwrap();
    let old = a["token"].as_str().unwrap();
    let (_, t) = api(
        &s,
        "POST",
        "/api/wake/targets",
        "account",
        serde_json::json!({"name":"pc","device_id":"pc","mac":"02:11:22:33:44:55","agent_id":aid}),
    )
    .await;
    assert_eq!(
        api(
            &s,
            "POST",
            &format!("/api/wake/agents/{aid}/disable"),
            old,
            empty.clone()
        )
        .await
        .0,
        StatusCode::OK
    );
    assert!(s
        .users
        .get("owner")
        .unwrap()
        .wake
        .agents
        .iter()
        .any(|a| a.id == aid && !a.enabled));
    let (status, new) = api(
        &s,
        "POST",
        &format!("/api/wake/agents/{aid}/enable"),
        "account",
        serde_json::json!({"name":"phone"}),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(new["id"], aid);
    assert_ne!(new["token"], old);
    assert_eq!(
        api(
            &s,
            "POST",
            &format!("/api/wake/agents/{aid}/disable"),
            old,
            empty.clone()
        )
        .await
        .0,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(s.users.get("owner").unwrap().wake.targets[0].agent_id, aid);
    s.wake_runtime
        .agents
        .lock()
        .unwrap()
        .insert(aid.into(), crate::now_ms());
    assert_eq!(
        api(
            &s,
            "POST",
            "/api/wake/requests",
            "account",
            serde_json::json!({"target_id":t["id"]})
        )
        .await
        .0,
        StatusCode::OK
    );
    assert_eq!(
        api(
            &s,
            "POST",
            &format!("/api/wake/agents/{aid}/enable"),
            "other-account",
            serde_json::json!({"name":"stolen"})
        )
        .await
        .0,
        StatusCode::UNAUTHORIZED
    );
    std::fs::remove_dir_all(dir).unwrap();
}

#[tokio::test]
async fn offline_helpers_keep_last_seen_for_diagnosis_without_becoming_online() {
    let (s, dir) = authenticated_fixture();
    let (_, a) = api(
        &s,
        "POST",
        "/api/wake/agents",
        "account",
        serde_json::json!({"name":"phone"}),
    )
    .await;
    let id = a["id"].as_str().unwrap();
    let seen = crate::now_ms() - 300_000;
    s.wake_runtime
        .agents
        .lock()
        .unwrap()
        .insert(id.into(), seen);
    super::routes::cleanup(&s).await;
    let (_, list) = api(
        &s,
        "GET",
        "/api/wake/agents",
        "account",
        serde_json::json!({}),
    )
    .await;
    assert_eq!(list["agents"][0]["last_seen_ms"], seen);
    assert_eq!(list["agents"][0]["online"], false);
    std::fs::remove_dir_all(dir).unwrap();
}
