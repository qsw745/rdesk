use super::*;

fn host_state() -> AppState {
    let state = AppState::new(String::new());
    state.previews.insert(
        "mac".into(),
        PreviewRegistration {
            device_id: "mac".into(),
            user_id: None,
            platform: "macos".into(),
            hostname: "test".into(),
            password_hash: "secret".into(),
            auto_accept: false,
            trusted_viewers: vec![],
            host_token: "host".into(),
            on_demand_capture: true,
            updated_at_ms: now_ms(),
        },
    );
    state
}

#[tokio::test]
async fn idle_host_rejects_frames() {
    let state = host_state();
    let response = upload_frame(
        State(state.clone()),
        Query(FrameUploadQuery {
            device_id: "mac".into(),
            host_token: "host".into(),
            width: 1,
            height: 1,
            timestamp_ms: None,
            capture_epoch: None,
        }),
        Bytes::from_static(b"jpeg"),
    )
    .await;
    assert_eq!(response.status(), StatusCode::CONFLICT);
    assert!(state.frames.is_empty());
}

fn viewer(state: &AppState, token: &str) {
    state.viewer_sessions.insert(
        token.into(),
        ViewerSession {
            device_id: "mac".into(),
            last_seen_ms: now_ms(),
        },
    );
}

async fn upload(state: &AppState, epoch: u64) -> StatusCode {
    upload_frame(
        State(state.clone()),
        Query(FrameUploadQuery {
            device_id: "mac".into(),
            host_token: "host".into(),
            width: 1,
            height: 1,
            timestamp_ms: None,
            capture_epoch: Some(epoch),
        }),
        Bytes::from_static(b"jpeg"),
    )
    .await
    .status()
}

#[tokio::test]
async fn authenticated_frame_request_starts_capture_and_last_close_revokes_it() {
    let state = host_state();
    viewer(&state, "first");
    viewer(&state, "second");
    // Authenticated file/control access may validate tokens, but cannot capture.
    assert!(validate_viewer(&state, "mac", "first"));
    assert_eq!(upload(&state, 0).await, StatusCode::CONFLICT);
    assert!(!renew_screen_lease(&state, "mac", "wrong", "wrong"));
    let response = fetch_frame(
        State(state.clone()),
        Query(RelayViewerQuery {
            device_id: "mac".into(),
            token: "first".into(),
        }),
    )
    .await;
    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    let epoch = state.screen_demands.get("mac").unwrap().epoch;
    assert_eq!(upload(&state, epoch).await, StatusCode::OK);
    assert!(renew_screen_lease(&state, "mac", "second", "second"));
    close_viewer_session(
        State(state.clone()),
        Query(RelayViewerQuery {
            device_id: "mac".into(),
            token: "first".into(),
        }),
    )
    .await;
    assert_eq!(upload(&state, epoch).await, StatusCode::OK);
    close_viewer_session(
        State(state.clone()),
        Query(RelayViewerQuery {
            device_id: "mac".into(),
            token: "second".into(),
        }),
    )
    .await;
    assert_eq!(upload(&state, epoch).await, StatusCode::CONFLICT);
    assert!(state.frames.is_empty());
    assert!(!renew_screen_lease(&state, "mac", "first", "first"));
    viewer(&state, "new");
    renew_screen_lease(&state, "mac", "new", "new");
    assert_eq!(upload(&state, epoch).await, StatusCode::CONFLICT);
    assert_eq!(upload(&state, epoch + 1).await, StatusCode::OK);
}

#[tokio::test]
async fn crashed_viewer_expires_without_frames_or_host_recovery() {
    let state = host_state();
    viewer(&state, "viewer");
    renew_screen_lease(&state, "mac", "viewer", "viewer");
    assert_eq!(upload(&state, 1).await, StatusCode::OK);
    state
        .screen_demands
        .get_mut("mac")
        .unwrap()
        .viewers
        .get_mut("viewer")
        .unwrap()
        .1 = now_ms() - 1;
    assert_eq!(upload(&state, 1).await, StatusCode::CONFLICT);
    assert!(state.frames.is_empty());
    assert!(state.previews.contains_key("mac"), "待命在线不能依赖截图");
}

#[tokio::test]
async fn closing_one_websocket_does_not_remove_http_fallback_or_other_websocket() {
    let state = host_state();
    viewer(&state, "viewer");
    for key in ["ws:1", "ws:2", "viewer"] {
        assert!(renew_screen_lease(&state, "mac", "viewer", key));
    }
    release_screen_lease(&state, "mac", "ws:1");
    assert!(screen_lease_alive(&state, "mac", "viewer"));
    assert!(screen_lease_alive(&state, "mac", "ws:2"));
    disconnect_viewers_for_device(&state, "mac");
    assert!(!screen_lease_alive(&state, "mac", "ws:2"));
    assert!(!renew_screen_lease(&state, "mac", "viewer", "ws:2"));
}

#[tokio::test]
async fn legacy_mobile_host_uploads_remain_supported() {
    let state = host_state();
    state.previews.get_mut("mac").unwrap().on_demand_capture = false;
    assert_eq!(upload(&state, 0).await, StatusCode::OK);
}

#[tokio::test]
async fn screen_stop_keeps_file_authentication_without_screen_demand() {
    let state = host_state();
    viewer(&state, "viewer");
    renew_screen_lease(&state, "mac", "viewer", "ws:1");
    renew_screen_lease(&state, "mac", "viewer", "viewer");
    assert_eq!(upload(&state, 1).await, StatusCode::OK);
    stop_viewer_screen(
        State(state.clone()),
        Query(RelayViewerQuery {
            device_id: "mac".into(),
            token: "viewer".into(),
        }),
    )
    .await;
    assert!(validate_viewer(&state, "mac", "viewer"));
    assert!(!screen_lease_alive(&state, "mac", "ws:1"));
    assert_eq!(upload(&state, 1).await, StatusCode::CONFLICT);
    assert!(state.frames.is_empty());
}

#[tokio::test]
async fn pending_or_rejected_connection_request_cannot_activate_capture() {
    let state = host_state();
    let request: ResolvePreviewRequest = serde_json::from_value(json!({
        "requester_id": "viewer", "requester_hostname": "test", "requester_peer_os": "ios"
    }))
    .unwrap();
    let resolver = tokio::spawn(resolve_preview(
        Path("mac".into()),
        State(state.clone()),
        HeaderMap::new(),
        Json(request),
    ));
    for _ in 0..100 {
        if state
            .command_queues
            .get("mac")
            .is_some_and(|q| !q.is_empty())
        {
            break;
        }
        tokio::time::sleep(Duration::from_millis(1)).await;
    }
    assert_eq!(upload(&state, 0).await, StatusCode::CONFLICT);
    let command = state
        .command_queues
        .get_mut("mac")
        .unwrap()
        .pop_front()
        .unwrap();
    complete_host_command(
        State(state.clone()),
        Query(RelayHostQuery {
            device_id: "mac".into(),
            host_token: "host".into(),
        }),
        Json(CommandResultRequest {
            command_id: command.command_id,
            ok: false,
            text: None,
        }),
    )
    .await;
    assert!(!resolver.await.unwrap().0.authorized);
    assert!(state.viewer_sessions.is_empty());
}
