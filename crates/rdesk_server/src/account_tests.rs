use super::*;

fn signed_in_state() -> (AppState, HeaderMap) {
    let state = AppState::new(String::new());
    state.users.insert(
        "u1".into(),
        UserRecord {
            user_id: "u1".into(),
            username: "tester".into(),
            display_name: "tester".into(),
            password_hash: String::new(),
            created_at_ms: now_ms(),
            wake: Default::default(),
        },
    );
    state.auth_sessions.insert(
        "token".into(),
        AuthSession {
            user_id: "u1".into(),
            last_seen_ms: now_ms(),
        },
    );
    let mut headers = HeaderMap::new();
    headers.insert(AUTHORIZATION, "Bearer token".parse().unwrap());
    (state, headers)
}

async fn report(state: &AppState, headers: &HeaderMap, body: Value) {
    let request: UpsertAccountPresenceRequest = serde_json::from_value(body).unwrap();
    let response =
        upsert_account_presence(State(state.clone()), headers.clone(), Json(request)).await;
    assert_eq!(response.status(), StatusCode::OK);
}

async fn listed(state: &AppState, headers: &HeaderMap) -> Vec<Value> {
    let response = list_account_devices(State(state.clone()), headers.clone()).await;
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let payload: Value = serde_json::from_slice(&bytes).unwrap();
    payload["devices"].as_array().unwrap().clone()
}

fn device<'a>(devices: &'a [Value], id: &str) -> &'a Value {
    devices
        .iter()
        .find(|item| item["device_id"] == id)
        .unwrap_or_else(|| panic!("device {id} not listed"))
}

#[tokio::test]
async fn presence_without_capability_lists_as_not_hostable() {
    let (state, headers) = signed_in_state();
    report(
        &state,
        &headers,
        json!({"device_id": "old-win", "platform": "windows", "hostname": "PC"}),
    )
    .await;

    let devices = listed(&state, &headers).await;

    assert_eq!(device(&devices, "old-win")["can_host"], false);
}

#[tokio::test]
async fn presence_reporting_capability_lists_as_hostable() {
    let (state, headers) = signed_in_state();
    report(
        &state,
        &headers,
        json!({"device_id": "new-win", "platform": "windows", "hostname": "PC", "can_host": true}),
    )
    .await;

    let devices = listed(&state, &headers).await;

    assert_eq!(device(&devices, "new-win")["can_host"], true);
}

fn register_host(state: &AppState, device_id: &str, platform: &str, updated_at_ms: u64) {
    state.previews.insert(
        device_id.into(),
        PreviewRegistration {
            device_id: device_id.into(),
            user_id: Some("u1".into()),
            platform: platform.into(),
            hostname: "PC".into(),
            password_hash: "secret".into(),
            auto_accept: false,
            trusted_viewers: vec![],
            host_token: "host".into(),
            on_demand_capture: false,
            updated_at_ms,
        },
    );
}

/// Shipped Windows builds register as a host at launch although they cannot
/// capture, so a registration alone must never imply the capability.
#[tokio::test]
async fn registered_host_without_capability_stays_not_hostable() {
    let (state, headers) = signed_in_state();
    report(
        &state,
        &headers,
        json!({"device_id": "old-win", "platform": "windows", "hostname": "PC"}),
    )
    .await;
    register_host(&state, "old-win", "windows", now_ms());

    let devices = listed(&state, &headers).await;

    assert_eq!(device(&devices, "old-win")["can_host"], false);
    assert_eq!(device(&devices, "old-win")["hosting"], true);
}

#[tokio::test]
async fn hosting_reflects_a_fresh_registration_only() {
    let (state, headers) = signed_in_state();
    for id in ["idle", "live", "stale"] {
        report(
            &state,
            &headers,
            json!({"device_id": id, "platform": "windows", "hostname": "PC", "can_host": true}),
        )
        .await;
    }
    register_host(&state, "live", "windows", now_ms());
    register_host(&state, "stale", "windows", now_ms() - PREVIEW_TTL_MS - 1);

    let devices = listed(&state, &headers).await;

    assert_eq!(device(&devices, "idle")["hosting"], false);
    assert_eq!(device(&devices, "live")["hosting"], true);
    assert_eq!(device(&devices, "stale")["hosting"], false);
    assert_eq!(device(&devices, "live")["can_host"], true);
}
