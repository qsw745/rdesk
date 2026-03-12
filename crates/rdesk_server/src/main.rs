use std::collections::VecDeque;
use std::net::SocketAddr;
use std::path::Path as FsPath;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::Result;
use axum::body::Bytes;
use axum::extract::{Path, Query, State};
use axum::http::header::{AUTHORIZATION, CACHE_CONTROL, CONTENT_TYPE};
use axum::http::{HeaderMap, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use clap::Parser;
use dashmap::DashMap;
use rdesk_common::{hash_password, verify_password};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::sync::{oneshot, Mutex};
use tracing::{info, warn};
use tracing_subscriber::EnvFilter;
use uuid::Uuid;

const PREVIEW_TTL_MS: u64 = 30_000;
const VIEWER_SESSION_TTL_MS: u64 = 30 * 60 * 1_000;
const COMMAND_TTL_MS: u64 = 15_000;
const AUTH_SESSION_TTL_MS: u64 = 30 * 24 * 60 * 60 * 1_000;
const MIN_PASSWORD_LEN: usize = 6;

#[derive(Debug, Parser)]
#[command(name = "rdesk-server")]
#[command(about = "Preview registration and relay server for rdesk MVP")]
struct Args {
    #[arg(long, default_value = "0.0.0.0")]
    host: String,
    #[arg(long, default_value_t = 21116)]
    signaling_port: u16,
    #[arg(long, default_value_t = 21117)]
    relay_port: u16,
    #[arg(long, default_value = "data/rdesk-users.json")]
    user_store_path: String,
}

#[derive(Clone)]
struct AppState {
    previews: Arc<DashMap<String, PreviewRegistration>>,
    frames: Arc<DashMap<String, FrameSnapshot>>,
    viewer_sessions: Arc<DashMap<String, ViewerSession>>,
    command_queues: Arc<DashMap<String, VecDeque<PendingCommand>>>,
    command_waiters: Arc<DashMap<String, oneshot::Sender<CommandResult>>>,
    users: Arc<DashMap<String, UserRecord>>,
    username_index: Arc<DashMap<String, String>>,
    auth_sessions: Arc<DashMap<String, AuthSession>>,
    user_store_path: Arc<String>,
    user_store_write: Arc<Mutex<()>>,
}

impl AppState {
    fn new(user_store_path: String) -> Self {
        Self {
            previews: Arc::new(DashMap::new()),
            frames: Arc::new(DashMap::new()),
            viewer_sessions: Arc::new(DashMap::new()),
            command_queues: Arc::new(DashMap::new()),
            command_waiters: Arc::new(DashMap::new()),
            users: Arc::new(DashMap::new()),
            username_index: Arc::new(DashMap::new()),
            auth_sessions: Arc::new(DashMap::new()),
            user_store_path: Arc::new(user_store_path),
            user_store_write: Arc::new(Mutex::new(())),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PreviewRegistration {
    device_id: String,
    user_id: Option<String>,
    platform: String,
    hostname: String,
    password_hash: String,
    auto_accept: bool,
    trusted_viewers: Vec<String>,
    host_token: String,
    updated_at_ms: u64,
}

#[derive(Debug, Clone)]
struct FrameSnapshot {
    bytes: Bytes,
    width: u32,
    height: u32,
    timestamp_ms: u64,
    updated_at_ms: u64,
}

#[derive(Debug, Clone)]
struct ViewerSession {
    device_id: String,
    last_seen_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct UserRecord {
    user_id: String,
    username: String,
    display_name: String,
    password_hash: String,
    created_at_ms: u64,
}

#[derive(Debug, Clone)]
struct AuthSession {
    user_id: String,
    last_seen_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PendingCommand {
    command_id: String,
    kind: String,
    payload: Value,
    queued_at_ms: u64,
}

#[derive(Debug, Clone)]
struct CommandResult {
    ok: bool,
    text: Option<String>,
}

#[derive(Debug, Deserialize)]
struct RegisterPreviewRequest {
    device_id: String,
    #[serde(rename = "endpoint")]
    _endpoint: Option<String>,
    auth_token: Option<String>,
    platform: String,
    hostname: String,
    password_hash: String,
    auto_accept: bool,
    trusted_viewers: Vec<String>,
}

#[derive(Debug, Serialize)]
struct RegisterPreviewResponse {
    host_token: String,
}

#[derive(Debug, Deserialize)]
struct UnregisterPreviewRequest {
    device_id: String,
}

#[derive(Debug, Deserialize)]
struct DisconnectViewersRequest {
    device_id: String,
    host_token: String,
}

#[derive(Debug, Deserialize)]
struct AccountAuthRequest {
    username: String,
    password: String,
    display_name: Option<String>,
}

#[derive(Debug, Serialize)]
struct AccountSessionResponse {
    token: String,
    user_id: String,
    username: String,
    display_name: String,
}

#[derive(Debug, Serialize)]
struct AccountDeviceSummary {
    device_id: String,
    hostname: String,
    platform: String,
    updated_at_ms: u64,
}

#[derive(Debug, Serialize)]
struct AccountDevicesResponse {
    devices: Vec<AccountDeviceSummary>,
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    message: String,
}

#[derive(Debug, Deserialize)]
struct ResolvePreviewRequest {
    password_hash: Option<String>,
    requester_id: Option<String>,
}

#[derive(Debug, Serialize)]
struct ResolvePreviewResponse {
    found: bool,
    authorized: bool,
    endpoint: Option<String>,
    platform: Option<String>,
    hostname: Option<String>,
    updated_at_ms: Option<u64>,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    ok: bool,
    preview_count: usize,
    viewer_count: usize,
}

#[derive(Debug, Deserialize)]
struct RelayViewerQuery {
    device_id: String,
    token: String,
}

#[derive(Debug, Deserialize)]
struct RelayHostQuery {
    device_id: String,
    host_token: String,
}

#[derive(Debug, Deserialize)]
struct FrameUploadQuery {
    device_id: String,
    host_token: String,
    width: u32,
    height: u32,
    timestamp_ms: u64,
}

#[derive(Debug, Serialize)]
struct GenericOkResponse {
    ok: bool,
}

#[derive(Debug, Deserialize)]
struct CommandResultRequest {
    command_id: String,
    ok: bool,
    text: Option<String>,
}

#[derive(Debug, Serialize)]
struct ClipboardResponse {
    text: Option<String>,
}

#[derive(Debug, Deserialize)]
struct TapRequest {
    x: f64,
    y: f64,
}

#[derive(Debug, Deserialize)]
struct ActionRequest {
    action: String,
}

#[derive(Debug, Deserialize)]
struct DragRequest {
    #[serde(rename = "startX")]
    start_x: f64,
    #[serde(rename = "startY")]
    start_y: f64,
    #[serde(rename = "endX")]
    end_x: f64,
    #[serde(rename = "endY")]
    end_y: f64,
}

#[derive(Debug, Deserialize)]
struct TextRequest {
    text: String,
}

#[derive(Debug, Deserialize)]
struct TrustViewerRequest {
    #[serde(rename = "deviceId")]
    device_id: String,
    hostname: String,
    #[serde(rename = "peerOs")]
    peer_os: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    let args = Args::parse();
    let state = AppState::new(args.user_store_path.clone());
    load_users(&state).await?;
    let app = Router::new()
        .route("/health", get(health))
        .route("/frame.jpg", get(fetch_frame))
        .route("/session/trust", post(session_trust))
        .route("/input/tap", post(input_tap))
        .route("/input/action", post(input_action))
        .route("/input/long_press", post(input_long_press))
        .route("/input/drag", post(input_drag))
        .route("/input/text", post(input_text))
        .route("/clipboard/set", post(clipboard_set))
        .route("/clipboard/get", get(clipboard_get))
        .route("/api/preview/register", post(register_preview))
        .route("/api/preview/unregister", post(unregister_preview))
        .route("/api/preview/disconnect_viewers", post(disconnect_viewers))
        .route("/api/preview/resolve/:device_id", post(resolve_preview))
        .route("/api/preview/host/frame", post(upload_frame))
        .route("/api/preview/host/control/poll", get(poll_host_command))
        .route("/api/account/register", post(register_account))
        .route("/api/account/login", post(login_account))
        .route("/api/account/devices", get(list_account_devices))
        .route(
            "/api/preview/host/control/result",
            post(complete_host_command),
        )
        .with_state(state.clone());

    let signaling_addr: SocketAddr = format!("{}:{}", args.host, args.signaling_port).parse()?;
    info!(
        host = %args.host,
        signaling_port = args.signaling_port,
        relay_port = args.relay_port,
        "starting rdesk preview relay server"
    );

    let cleanup_state = state.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(15));
        loop {
            interval.tick().await;
            cleanup_expired(cleanup_state.clone());
        }
    });

    let listener = tokio::net::TcpListener::bind(signaling_addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

async fn health(State(state): State<AppState>) -> Json<HealthResponse> {
    Json(HealthResponse {
        ok: true,
        preview_count: state.previews.len(),
        viewer_count: state.viewer_sessions.len(),
    })
}

async fn register_account(
    State(state): State<AppState>,
    Json(request): Json<AccountAuthRequest>,
) -> Response {
    let username = normalize_username(&request.username);
    let password = request.password.trim().to_string();
    if username.is_empty() {
        return error_response(StatusCode::BAD_REQUEST, "账号不能为空");
    }
    if password.len() < MIN_PASSWORD_LEN {
        return error_response(StatusCode::BAD_REQUEST, "密码至少需要 6 位");
    }
    if state.username_index.contains_key(&username) {
        return error_response(StatusCode::CONFLICT, "账号已存在");
    }

    let password_hash = match hash_password(&password) {
        Ok(hash) => hash,
        Err(err) => {
            warn!(error = %err, "failed to hash account password");
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, "密码处理失败");
        }
    };

    let display_name = request
        .display_name
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(&username)
        .to_string();
    let user = UserRecord {
        user_id: new_token(),
        username: username.clone(),
        display_name,
        password_hash,
        created_at_ms: now_ms(),
    };
    state.users.insert(user.user_id.clone(), user.clone());
    state.username_index.insert(username.clone(), user.user_id.clone());

    if let Err(err) = persist_users(&state).await {
        state.users.remove(&user.user_id);
        state.username_index.remove(&username);
        warn!(error = %err, "failed to persist registered user");
        return error_response(StatusCode::INTERNAL_SERVER_ERROR, "保存账号失败");
    }

    Json(create_account_session(&state, &user)).into_response()
}

async fn login_account(
    State(state): State<AppState>,
    Json(request): Json<AccountAuthRequest>,
) -> Response {
    let username = normalize_username(&request.username);
    let password = request.password.trim().to_string();
    let Some(user_id) = state.username_index.get(&username).map(|entry| entry.value().clone()) else {
        return error_response(StatusCode::UNAUTHORIZED, "账号或密码错误");
    };
    let Some(user) = state.users.get(&user_id).map(|entry| entry.clone()) else {
        return error_response(StatusCode::UNAUTHORIZED, "账号或密码错误");
    };

    let verified = verify_password(&password, &user.password_hash).unwrap_or(false);
    if !verified {
        return error_response(StatusCode::UNAUTHORIZED, "账号或密码错误");
    }

    Json(create_account_session(&state, &user)).into_response()
}

async fn list_account_devices(State(state): State<AppState>, headers: HeaderMap) -> Response {
    let Some(user) = authenticated_user(&state, &headers) else {
        return error_response(StatusCode::UNAUTHORIZED, "登录状态已失效");
    };

    let mut devices: Vec<AccountDeviceSummary> = state
        .previews
        .iter()
        .filter(|entry| {
            entry.user_id.as_deref() == Some(user.user_id.as_str())
                && is_fresh(entry.updated_at_ms, PREVIEW_TTL_MS)
        })
        .map(|entry| AccountDeviceSummary {
            device_id: entry.device_id.clone(),
            hostname: entry.hostname.clone(),
            platform: entry.platform.clone(),
            updated_at_ms: entry.updated_at_ms,
        })
        .collect();
    devices.sort_by(|left, right| right.updated_at_ms.cmp(&left.updated_at_ms));

    (StatusCode::OK, Json(AccountDevicesResponse { devices })).into_response()
}

async fn register_preview(
    State(state): State<AppState>,
    Json(request): Json<RegisterPreviewRequest>,
) -> Json<RegisterPreviewResponse> {
    let host_token = state
        .previews
        .get(&request.device_id)
        .map(|entry| entry.host_token.clone())
        .unwrap_or_else(new_token);

    let registration = PreviewRegistration {
        device_id: request.device_id.clone(),
        user_id: request
            .auth_token
            .as_deref()
            .and_then(|token| validate_auth_session(&state, token)),
        platform: request.platform,
        hostname: request.hostname,
        password_hash: request.password_hash,
        auto_accept: request.auto_accept,
        trusted_viewers: request.trusted_viewers,
        host_token: host_token.clone(),
        updated_at_ms: now_ms(),
    };
    state
        .previews
        .insert(request.device_id.clone(), registration);
    info!(device_id = %request.device_id, "registered preview host");

    Json(RegisterPreviewResponse { host_token })
}

async fn unregister_preview(
    State(state): State<AppState>,
    Json(request): Json<UnregisterPreviewRequest>,
) -> StatusCode {
    remove_preview_state(&state, &request.device_id);
    info!(device_id = %request.device_id, "unregistered preview host");
    StatusCode::OK
}

async fn disconnect_viewers(
    State(state): State<AppState>,
    Json(request): Json<DisconnectViewersRequest>,
) -> Response {
    if !validate_host(&state, &request.device_id, &request.host_token) {
        return StatusCode::UNAUTHORIZED.into_response();
    }

    disconnect_viewers_for_device(&state, &request.device_id);
    info!(device_id = %request.device_id, "disconnected all active viewers");
    (StatusCode::OK, Json(GenericOkResponse { ok: true })).into_response()
}

async fn resolve_preview(
    Path(device_id): Path<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<ResolvePreviewRequest>,
) -> Json<ResolvePreviewResponse> {
    let Some(entry) = state.previews.get(&device_id) else {
        return unresolved_response();
    };
    let registration = entry.clone();
    drop(entry);

    if !is_fresh(registration.updated_at_ms, PREVIEW_TTL_MS) {
        remove_preview_state(&state, &device_id);
        warn!(device_id = %device_id, "dropping stale preview registration");
        return unresolved_response();
    }

    let password_ok = request
        .password_hash
        .as_ref()
        .is_some_and(|hash| !hash.is_empty() && *hash == registration.password_hash);
    let trusted_ok = registration.auto_accept
        && request.requester_id.as_ref().is_some_and(|requester| {
            registration
                .trusted_viewers
                .iter()
                .any(|item| item == requester)
        });
    let authorized = password_ok || trusted_ok;

    if !authorized {
        return Json(ResolvePreviewResponse {
            found: true,
            authorized: false,
            endpoint: None,
            platform: None,
            hostname: None,
            updated_at_ms: None,
        });
    }

    let viewer_token = new_token();
    state.viewer_sessions.insert(
        viewer_token.clone(),
        ViewerSession {
            device_id: device_id.clone(),
            last_seen_ms: now_ms(),
        },
    );
    let public_host = request_host(&headers);
    let endpoint =
        format!("http://{public_host}/frame.jpg?device_id={device_id}&token={viewer_token}");

    Json(ResolvePreviewResponse {
        found: true,
        authorized: true,
        endpoint: Some(endpoint),
        platform: Some(registration.platform),
        hostname: Some(registration.hostname),
        updated_at_ms: Some(registration.updated_at_ms),
    })
}

async fn upload_frame(
    State(state): State<AppState>,
    Query(query): Query<FrameUploadQuery>,
    body: Bytes,
) -> StatusCode {
    if !validate_host(&state, &query.device_id, &query.host_token) {
        return StatusCode::UNAUTHORIZED;
    }

    state.frames.insert(
        query.device_id,
        FrameSnapshot {
            bytes: body,
            width: query.width,
            height: query.height,
            timestamp_ms: query.timestamp_ms,
            updated_at_ms: now_ms(),
        },
    );
    StatusCode::OK
}

async fn fetch_frame(
    State(state): State<AppState>,
    Query(query): Query<RelayViewerQuery>,
) -> Response {
    if !validate_viewer(&state, &query.device_id, &query.token) {
        return StatusCode::UNAUTHORIZED.into_response();
    }

    let Some(frame) = state.frames.get(&query.device_id) else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };
    if !is_fresh(frame.updated_at_ms, PREVIEW_TTL_MS) {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    }

    let mut headers = HeaderMap::new();
    headers.insert(CONTENT_TYPE, HeaderValue::from_static("image/jpeg"));
    headers.insert(CACHE_CONTROL, HeaderValue::from_static("no-store"));
    insert_header(&mut headers, "x-rdesk-width", &frame.width.to_string());
    insert_header(&mut headers, "x-rdesk-height", &frame.height.to_string());
    insert_header(
        &mut headers,
        "x-rdesk-timestamp",
        &frame.timestamp_ms.to_string(),
    );
    (StatusCode::OK, headers, frame.bytes.clone()).into_response()
}

async fn session_trust(
    State(state): State<AppState>,
    Query(query): Query<RelayViewerQuery>,
    Json(request): Json<TrustViewerRequest>,
) -> Response {
    match forward_command(
        &state,
        &query,
        "trust",
        json!({
            "deviceId": request.device_id,
            "hostname": request.hostname,
            "peerOs": request.peer_os,
        }),
    )
    .await
    {
        Ok(result) => (StatusCode::OK, Json(GenericOkResponse { ok: result.ok })).into_response(),
        Err(status) => status.into_response(),
    }
}

async fn input_tap(
    State(state): State<AppState>,
    Query(query): Query<RelayViewerQuery>,
    Json(request): Json<TapRequest>,
) -> Response {
    match forward_command(
        &state,
        &query,
        "tap",
        json!({ "x": request.x, "y": request.y }),
    )
    .await
    {
        Ok(_) => (StatusCode::OK, Json(GenericOkResponse { ok: true })).into_response(),
        Err(status) => status.into_response(),
    }
}

async fn input_action(
    State(state): State<AppState>,
    Query(query): Query<RelayViewerQuery>,
    Json(request): Json<ActionRequest>,
) -> Response {
    relay_bool_command(
        &state,
        &query,
        "action",
        json!({ "action": request.action }),
    )
    .await
}

async fn input_long_press(
    State(state): State<AppState>,
    Query(query): Query<RelayViewerQuery>,
    Json(request): Json<TapRequest>,
) -> Response {
    relay_bool_command(
        &state,
        &query,
        "long_press",
        json!({ "x": request.x, "y": request.y }),
    )
    .await
}

async fn input_drag(
    State(state): State<AppState>,
    Query(query): Query<RelayViewerQuery>,
    Json(request): Json<DragRequest>,
) -> Response {
    relay_bool_command(
        &state,
        &query,
        "drag",
        json!({
            "startX": request.start_x,
            "startY": request.start_y,
            "endX": request.end_x,
            "endY": request.end_y,
        }),
    )
    .await
}

async fn input_text(
    State(state): State<AppState>,
    Query(query): Query<RelayViewerQuery>,
    Json(request): Json<TextRequest>,
) -> Response {
    relay_bool_command(&state, &query, "text", json!({ "text": request.text })).await
}

async fn clipboard_set(
    State(state): State<AppState>,
    Query(query): Query<RelayViewerQuery>,
    Json(request): Json<TextRequest>,
) -> Response {
    relay_bool_command(
        &state,
        &query,
        "clipboard_set",
        json!({ "text": request.text }),
    )
    .await
}

async fn clipboard_get(
    State(state): State<AppState>,
    Query(query): Query<RelayViewerQuery>,
) -> Response {
    match forward_command(&state, &query, "clipboard_get", json!({})).await {
        Ok(result) => (
            StatusCode::OK,
            Json(ClipboardResponse { text: result.text }),
        )
            .into_response(),
        Err(status) => status.into_response(),
    }
}

async fn poll_host_command(
    State(state): State<AppState>,
    Query(query): Query<RelayHostQuery>,
) -> Response {
    if !validate_host(&state, &query.device_id, &query.host_token) {
        return StatusCode::UNAUTHORIZED.into_response();
    }

    expire_stale_device_commands(&state, &query.device_id);
    let Some(mut queue) = state.command_queues.get_mut(&query.device_id) else {
        return StatusCode::NO_CONTENT.into_response();
    };
    let Some(command) = queue.pop_front() else {
        return StatusCode::NO_CONTENT.into_response();
    };
    (StatusCode::OK, Json(command)).into_response()
}

async fn complete_host_command(
    State(state): State<AppState>,
    Query(query): Query<RelayHostQuery>,
    Json(request): Json<CommandResultRequest>,
) -> StatusCode {
    if !validate_host(&state, &query.device_id, &query.host_token) {
        return StatusCode::UNAUTHORIZED;
    }

    if let Some((_, sender)) = state.command_waiters.remove(&request.command_id) {
        let _ = sender.send(CommandResult {
            ok: request.ok,
            text: request.text,
        });
    }
    StatusCode::OK
}

async fn relay_bool_command(
    state: &AppState,
    query: &RelayViewerQuery,
    kind: &str,
    payload: Value,
) -> Response {
    match forward_command(state, query, kind, payload).await {
        Ok(result) => (StatusCode::OK, Json(GenericOkResponse { ok: result.ok })).into_response(),
        Err(status) => status.into_response(),
    }
}

async fn forward_command(
    state: &AppState,
    query: &RelayViewerQuery,
    kind: &str,
    payload: Value,
) -> Result<CommandResult, StatusCode> {
    if !validate_viewer(state, &query.device_id, &query.token) {
        return Err(StatusCode::UNAUTHORIZED);
    }
    let Some(preview) = state.previews.get(&query.device_id) else {
        return Err(StatusCode::NOT_FOUND);
    };
    if !is_fresh(preview.updated_at_ms, PREVIEW_TTL_MS) {
        return Err(StatusCode::NOT_FOUND);
    }
    drop(preview);

    let command_id = new_token();
    let (tx, rx) = oneshot::channel();
    state.command_waiters.insert(command_id.clone(), tx);
    state
        .command_queues
        .entry(query.device_id.clone())
        .or_default()
        .push_back(PendingCommand {
            command_id: command_id.clone(),
            kind: kind.to_string(),
            payload,
            queued_at_ms: now_ms(),
        });

    match tokio::time::timeout(Duration::from_secs(5), rx).await {
        Ok(Ok(result)) => Ok(result),
        Ok(Err(_)) => Err(StatusCode::BAD_GATEWAY),
        Err(_) => {
            state.command_waiters.remove(&command_id);
            Err(StatusCode::GATEWAY_TIMEOUT)
        }
    }
}

fn create_account_session(state: &AppState, user: &UserRecord) -> AccountSessionResponse {
    let token = new_token();
    state.auth_sessions.insert(
        token.clone(),
        AuthSession {
            user_id: user.user_id.clone(),
            last_seen_ms: now_ms(),
        },
    );
    AccountSessionResponse {
        token,
        user_id: user.user_id.clone(),
        username: user.username.clone(),
        display_name: user.display_name.clone(),
    }
}

fn authenticated_user(state: &AppState, headers: &HeaderMap) -> Option<UserRecord> {
    let token = headers
        .get(AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(parse_bearer_token)?;
    let user_id = validate_auth_session(state, token)?;
    state.users.get(&user_id).map(|entry| entry.clone())
}

fn parse_bearer_token(value: &str) -> Option<&str> {
    value
        .strip_prefix("Bearer ")
        .or_else(|| value.strip_prefix("bearer "))
        .filter(|token| !token.is_empty())
}

fn validate_auth_session(state: &AppState, token: &str) -> Option<String> {
    let Some(mut session) = state.auth_sessions.get_mut(token) else {
        return None;
    };
    if !is_fresh(session.last_seen_ms, AUTH_SESSION_TTL_MS) {
        return None;
    }
    session.last_seen_ms = now_ms();
    Some(session.user_id.clone())
}

async fn load_users(state: &AppState) -> Result<()> {
    let path = FsPath::new(state.user_store_path.as_str());
    if !path.exists() {
        return Ok(());
    }

    let raw = tokio::fs::read_to_string(path).await?;
    if raw.trim().is_empty() {
        return Ok(());
    }
    let users: Vec<UserRecord> = serde_json::from_str(&raw)?;
    for user in users {
        state.username_index.insert(user.username.clone(), user.user_id.clone());
        state.users.insert(user.user_id.clone(), user);
    }
    Ok(())
}

async fn persist_users(state: &AppState) -> Result<()> {
    let _guard = state.user_store_write.lock().await;
    let path = FsPath::new(state.user_store_path.as_str());
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }

    let users: Vec<UserRecord> = state.users.iter().map(|entry| entry.clone()).collect();
    let payload = serde_json::to_string_pretty(&users)?;
    tokio::fs::write(path, payload).await?;
    Ok(())
}

fn normalize_username(raw: &str) -> String {
    raw.trim().to_lowercase()
}

fn error_response(status: StatusCode, message: &str) -> Response {
    (status, Json(ErrorResponse { message: message.to_string() })).into_response()
}

fn validate_viewer(state: &AppState, device_id: &str, token: &str) -> bool {
    let Some(mut session) = state.viewer_sessions.get_mut(token) else {
        return false;
    };
    if session.device_id != device_id || !is_fresh(session.last_seen_ms, VIEWER_SESSION_TTL_MS) {
        return false;
    }
    session.last_seen_ms = now_ms();
    true
}

fn validate_host(state: &AppState, device_id: &str, host_token: &str) -> bool {
    let Some(preview) = state.previews.get(device_id) else {
        return false;
    };
    preview.host_token == host_token && is_fresh(preview.updated_at_ms, PREVIEW_TTL_MS)
}

fn cleanup_expired(state: AppState) {
    let now = now_ms();
    let stale_previews: Vec<String> = state
        .previews
        .iter()
        .filter(|entry| now.saturating_sub(entry.updated_at_ms) > PREVIEW_TTL_MS)
        .map(|entry| entry.key().clone())
        .collect();

    for device_id in stale_previews {
        remove_preview_state(&state, &device_id);
        warn!(device_id = %device_id, "expired preview registration removed");
    }

    let stale_sessions: Vec<String> = state
        .viewer_sessions
        .iter()
        .filter(|entry| now.saturating_sub(entry.last_seen_ms) > VIEWER_SESSION_TTL_MS)
        .map(|entry| entry.key().clone())
        .collect();
    for token in stale_sessions {
        state.viewer_sessions.remove(&token);
    }

    let stale_auth_sessions: Vec<String> = state
        .auth_sessions
        .iter()
        .filter(|entry| now.saturating_sub(entry.last_seen_ms) > AUTH_SESSION_TTL_MS)
        .map(|entry| entry.key().clone())
        .collect();
    for token in stale_auth_sessions {
        state.auth_sessions.remove(&token);
    }

    let queue_ids: Vec<String> = state
        .command_queues
        .iter()
        .map(|entry| entry.key().clone())
        .collect();
    for device_id in queue_ids {
        expire_stale_device_commands(&state, &device_id);
    }
}

fn expire_stale_device_commands(state: &AppState, device_id: &str) {
    let Some(mut queue) = state.command_queues.get_mut(device_id) else {
        return;
    };

    while let Some(command) = queue.front() {
        if is_fresh(command.queued_at_ms, COMMAND_TTL_MS) {
            break;
        }
        let command_id = command.command_id.clone();
        queue.pop_front();
        if let Some((_, sender)) = state.command_waiters.remove(&command_id) {
            let _ = sender.send(CommandResult {
                ok: false,
                text: None,
            });
        }
    }
}

fn remove_preview_state(state: &AppState, device_id: &str) {
    disconnect_viewers_for_device(state, device_id);
    state.previews.remove(device_id);
    state.frames.remove(device_id);
    state.command_queues.remove(device_id);
}

fn disconnect_viewers_for_device(state: &AppState, device_id: &str) {
    let tokens: Vec<String> = state
        .viewer_sessions
        .iter()
        .filter(|entry| entry.device_id == device_id)
        .map(|entry| entry.key().clone())
        .collect();
    for token in tokens {
        state.viewer_sessions.remove(&token);
    }
}

fn unresolved_response() -> Json<ResolvePreviewResponse> {
    Json(ResolvePreviewResponse {
        found: false,
        authorized: false,
        endpoint: None,
        platform: None,
        hostname: None,
        updated_at_ms: None,
    })
}

fn request_host(headers: &HeaderMap) -> String {
    headers
        .get("host")
        .and_then(|value| value.to_str().ok())
        .filter(|value| !value.is_empty())
        .unwrap_or("127.0.0.1:21116")
        .to_string()
}

fn insert_header(headers: &mut HeaderMap, name: &'static str, value: &str) {
    if let Ok(header_value) = HeaderValue::from_str(value) {
        headers.insert(name, header_value);
    }
}

fn is_fresh(updated_at_ms: u64, ttl_ms: u64) -> bool {
    now_ms().saturating_sub(updated_at_ms) <= ttl_ms
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

fn new_token() -> String {
    Uuid::new_v4().as_simple().to_string()
}
