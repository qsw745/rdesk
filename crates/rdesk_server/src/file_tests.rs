use super::*;

fn state_with_host_and_viewer() -> AppState {
    let state = AppState::new(String::new());
    state.previews.insert(
        "pc".into(),
        PreviewRegistration {
            device_id: "pc".into(),
            user_id: None,
            platform: "windows".into(),
            hostname: "PC".into(),
            password_hash: "secret".into(),
            auto_accept: false,
            trusted_viewers: vec![],
            host_token: "host".into(),
            on_demand_capture: true,
            updated_at_ms: now_ms(),
        },
    );
    state.viewer_sessions.insert(
        "viewer".into(),
        ViewerSession {
            device_id: "pc".into(),
            last_seen_ms: now_ms(),
        },
    );
    state
}

fn upload_query(filename: &str) -> Query<FileUploadQuery> {
    Query(FileUploadQuery {
        device_id: "pc".into(),
        token: "viewer".into(),
        filename: filename.into(),
        remote_path: String::new(),
    })
}

/// Plays the host: takes the queued command and answers it.
async fn answer_next_command(state: &AppState, ok: bool) -> PendingCommand {
    loop {
        let next = state
            .command_queues
            .get_mut("pc")
            .and_then(|mut queue| queue.pop_front());
        if let Some(command) = next {
            if let Some((_, sender)) = state.command_waiters.remove(&command.command_id) {
                let _ = sender.send(CommandResult {
                    ok,
                    text: Some("report.pdf".into()),
                });
            }
            return command;
        }
        tokio::task::yield_now().await;
    }
}

async fn host_download(state: &AppState, file_id: &str, device: &str, token: &str) -> Response {
    file_host_download(
        Path(file_id.to_string()),
        Query(RelayHostQuery {
            device_id: device.into(),
            host_token: token.into(),
        }),
        State(state.clone()),
    )
    .await
}

#[test]
fn file_names_keep_only_a_safe_base_name() {
    assert_eq!(safe_file_name("report.pdf").as_deref(), Some("report.pdf"));
    assert_eq!(safe_file_name("../../etc/passwd").as_deref(), Some("passwd"));
    assert_eq!(
        safe_file_name("C:\\Users\\a\\合同 v2.docx").as_deref(),
        Some("合同 v2.docx")
    );
    assert_eq!(safe_file_name("a\u{0}b\n.txt").as_deref(), Some("ab.txt"));
    assert_eq!(safe_file_name(""), None);
    assert_eq!(safe_file_name(".."), None);
    assert_eq!(safe_file_name("dir/"), None);
    assert!(safe_file_name(&"x".repeat(400)).unwrap().chars().count() <= 200);
}

#[tokio::test]
async fn host_fetches_an_uploaded_file_once_with_its_own_token() {
    let state = state_with_host_and_viewer();
    let host = state.clone();
    let host_task = tokio::spawn(async move {
        let command = answer_next_command(&host, true).await;
        assert_eq!(command.kind, "file_receive");
        assert_eq!(command.payload["filename"], "report.pdf");
        command.payload["file_id"].as_str().unwrap().to_string()
    });

    // While the upload waits for the host, the host fetches the bytes.
    let uploading = tokio::spawn({
        let state = state.clone();
        async move {
            file_upload(
                State(state),
                upload_query("../report.pdf"),
                Bytes::from_static(b"contents"),
            )
            .await
        }
    });
    let file_id = host_task.await.unwrap();
    let response = uploading.await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    // A viewer token, another device's host, or a wrong token get nothing.
    assert_eq!(
        host_download(&state, &file_id, "pc", "viewer").await.status(),
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        host_download(&state, &file_id, "other", "host").await.status(),
        StatusCode::UNAUTHORIZED
    );

    let fetched = host_download(&state, &file_id, "pc", "host").await;
    assert_eq!(fetched.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(fetched.into_body(), usize::MAX)
        .await
        .unwrap();
    assert_eq!(&bytes[..], b"contents");

    // Fetched once: the relay does not keep the file.
    assert_eq!(
        host_download(&state, &file_id, "pc", "host").await.status(),
        StatusCode::NOT_FOUND
    );
    assert!(state.file_store.is_empty());
}

#[tokio::test]
async fn upload_is_dropped_when_the_host_never_takes_it() {
    let state = state_with_host_and_viewer();

    let response = relay_file(
        state.clone(),
        upload_query("report.pdf").0,
        Bytes::from_static(b"contents"),
        Duration::from_millis(50),
    )
    .await;

    assert_eq!(response.status(), StatusCode::GATEWAY_TIMEOUT);
    assert!(state.file_store.is_empty());
}

#[tokio::test]
async fn upload_refused_by_the_host_is_reported_and_dropped() {
    let state = state_with_host_and_viewer();
    let host = state.clone();
    tokio::spawn(async move { answer_next_command(&host, false).await });

    let response = file_upload(
        State(state.clone()),
        upload_query("report.pdf"),
        Bytes::from_static(b"contents"),
    )
    .await;

    assert_eq!(response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let payload: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(payload["ok"], false);
    assert!(state.file_store.is_empty());
}

#[tokio::test]
async fn upload_needs_a_viewer_session_and_a_usable_name() {
    let state = state_with_host_and_viewer();

    let unauthorized = file_upload(
        State(state.clone()),
        Query(FileUploadQuery {
            device_id: "pc".into(),
            token: "nobody".into(),
            filename: "a.txt".into(),
            remote_path: String::new(),
        }),
        Bytes::from_static(b"x"),
    )
    .await;
    assert_eq!(unauthorized.status(), StatusCode::UNAUTHORIZED);

    let unnamed = file_upload(State(state.clone()), upload_query("../"), Bytes::from_static(b"x"))
        .await;
    assert_eq!(unnamed.status(), StatusCode::BAD_REQUEST);
    assert!(state.file_store.is_empty());
}

#[tokio::test]
async fn relay_refuses_to_hold_more_than_its_total_budget() {
    let state = state_with_host_and_viewer();
    state.file_store.insert(
        "held".into(),
        FileBlob {
            data: Bytes::from(vec![0u8; FILE_STORE_MAX_BYTES]),
            filename: "big".into(),
            created_at_ms: now_ms(),
            device_id: "pc".into(),
        },
    );

    let response = file_upload(
        State(state.clone()),
        upload_query("report.pdf"),
        Bytes::from_static(b"contents"),
    )
    .await;

    assert_eq!(response.status(), StatusCode::INSUFFICIENT_STORAGE);
    assert_eq!(state.file_store.len(), 1);
}
