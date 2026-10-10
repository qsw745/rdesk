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

fn declared(length: usize) -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.insert(CONTENT_LENGTH, HeaderValue::from(length));
    headers
}

/// Sends `data` through the upload handler the way a client does.
async fn upload(state: &AppState, query: Query<FileUploadQuery>, data: &'static [u8]) -> Response {
    file_upload(
        State(state.clone()),
        query,
        declared(data.len()),
        Body::from(data),
    )
    .await
}

/// A body that records whether the server started reading it.
fn watched_body(touched: Arc<std::sync::atomic::AtomicBool>) -> Body {
    Body::from_stream(futures_util::stream::poll_fn(move |_| {
        touched.store(true, Ordering::SeqCst);
        std::task::Poll::Ready(Some(Ok::<_, std::io::Error>(Bytes::from_static(b"x"))))
    }))
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
    assert_eq!(
        safe_file_name("../../etc/passwd").as_deref(),
        Some("passwd")
    );
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

/// Takes the queued command without answering it yet.
async fn take_next_command(state: &AppState) -> PendingCommand {
    loop {
        let next = state
            .command_queues
            .get_mut("pc")
            .and_then(|mut queue| queue.pop_front());
        if let Some(command) = next {
            return command;
        }
        tokio::task::yield_now().await;
    }
}

#[tokio::test]
async fn host_fetches_an_uploaded_file_once_with_its_own_token() {
    let state = state_with_host_and_viewer();
    let uploading = tokio::spawn({
        let state = state.clone();
        async move { upload(&state, upload_query("../report.pdf"), b"contents").await }
    });

    // While the upload waits for the host, the host fetches the bytes.
    let command = take_next_command(&state).await;
    assert_eq!(command.kind, "file_receive");
    assert_eq!(command.payload["filename"], "report.pdf");
    assert_eq!(command.payload["size"], 8);
    let file_id = command.payload["file_id"].as_str().unwrap().to_string();

    // A viewer token, another device's host, or a wrong token get nothing.
    assert_eq!(
        host_download(&state, &file_id, "pc", "viewer")
            .await
            .status(),
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        host_download(&state, &file_id, "other", "host")
            .await
            .status(),
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

    let (_, sender) = state.command_waiters.remove(&command.command_id).unwrap();
    sender
        .send(CommandResult {
            ok: true,
            text: Some("report.pdf".into()),
        })
        .unwrap();
    let response = uploading.await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let reply = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let reply: Value = serde_json::from_slice(&reply).unwrap();
    assert_eq!(reply["ok"], true);
    assert_eq!(reply["saved_as"], "report.pdf");
    assert_eq!(state.file_bytes.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn a_file_the_host_reported_on_without_fetching_is_not_kept() {
    let state = state_with_host_and_viewer();
    let host = state.clone();
    let host_task = tokio::spawn(async move { answer_next_command(&host, true).await });

    let response = upload(&state, upload_query("report.pdf"), b"contents").await;

    assert_eq!(response.status(), StatusCode::OK);
    let file_id = host_task.await.unwrap().payload["file_id"]
        .as_str()
        .unwrap()
        .to_string();
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
        "report.pdf".into(),
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

    let response = upload(&state, upload_query("report.pdf"), b"contents").await;

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

    let unnamed = upload(&state, upload_query("../"), b"x").await;
    assert_eq!(unnamed.status(), StatusCode::BAD_REQUEST);
    assert!(state.file_store.is_empty());
    assert_eq!(state.file_bytes.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn nothing_is_read_from_a_sender_without_a_viewer_session() {
    let state = state_with_host_and_viewer();
    let touched = Arc::new(std::sync::atomic::AtomicBool::new(false));

    let response = file_upload(
        State(state.clone()),
        Query(FileUploadQuery {
            device_id: "pc".into(),
            token: "nobody".into(),
            filename: "a.txt".into(),
            remote_path: String::new(),
        }),
        declared(FILE_MAX_BYTES),
        watched_body(touched.clone()),
    )
    .await;

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    assert!(
        !touched.load(Ordering::SeqCst),
        "body was read before the sender was checked"
    );
    assert_eq!(state.file_bytes.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn upload_must_declare_a_size_within_the_per_file_limit() {
    let state = state_with_host_and_viewer();
    let touched = Arc::new(std::sync::atomic::AtomicBool::new(false));

    let undeclared = file_upload(
        State(state.clone()),
        upload_query("a.bin"),
        HeaderMap::new(),
        watched_body(touched.clone()),
    )
    .await;
    assert_eq!(undeclared.status(), StatusCode::LENGTH_REQUIRED);

    let oversized = file_upload(
        State(state.clone()),
        upload_query("a.bin"),
        declared(FILE_MAX_BYTES + 1),
        watched_body(touched.clone()),
    )
    .await;
    assert_eq!(oversized.status(), StatusCode::PAYLOAD_TOO_LARGE);

    assert!(!touched.load(Ordering::SeqCst));
    assert_eq!(state.file_bytes.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn upload_shorter_than_declared_is_refused_and_releases_its_room() {
    let state = state_with_host_and_viewer();

    let response = file_upload(
        State(state.clone()),
        upload_query("a.bin"),
        declared(100),
        Body::from(&b"short"[..]),
    )
    .await;

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    assert!(state.file_store.is_empty());
    assert_eq!(state.file_bytes.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn room_is_counted_from_admission_so_concurrent_uploads_cannot_overshoot() {
    let state = state_with_host_and_viewer();
    let touched = Arc::new(std::sync::atomic::AtomicBool::new(false));

    // Three full-size uploads have been admitted and are still arriving.
    let arriving: Vec<FileReservation> = (0..3)
        .map(|_| FileReservation::try_new(&state.file_bytes, FILE_MAX_BYTES).unwrap())
        .collect();
    assert_eq!(FILE_MAX_BYTES * 3, FILE_STORE_MAX_BYTES);

    let refused = file_upload(
        State(state.clone()),
        upload_query("report.pdf"),
        declared(8),
        watched_body(touched.clone()),
    )
    .await;
    assert_eq!(refused.status(), StatusCode::INSUFFICIENT_STORAGE);
    assert!(!touched.load(Ordering::SeqCst));

    // Room comes back as soon as one of them ends, however it ends.
    drop(arriving);
    assert_eq!(state.file_bytes.load(Ordering::SeqCst), 0);
    let host = state.clone();
    tokio::spawn(async move { answer_next_command(&host, false).await });
    let admitted = upload(&state, upload_query("report.pdf"), b"contents").await;
    assert_eq!(admitted.status(), StatusCode::OK);
    assert_eq!(state.file_bytes.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn a_sender_that_goes_away_leaves_nothing_behind() {
    let state = state_with_host_and_viewer();
    let uploading = tokio::spawn({
        let state = state.clone();
        async move { upload(&state, upload_query("report.pdf"), b"contents").await }
    });
    while state.file_store.is_empty() {
        tokio::task::yield_now().await;
    }
    assert_eq!(state.file_bytes.load(Ordering::SeqCst), 8);

    // The connection closing drops the request while it waits for the host.
    uploading.abort();
    assert!(uploading.await.unwrap_err().is_cancelled());

    assert!(state.file_store.is_empty());
    assert_eq!(state.file_bytes.load(Ordering::SeqCst), 0);
}
