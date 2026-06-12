use std::collections::{HashMap, VecDeque};
use std::net::SocketAddr;
use std::path::Path as FsPath;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::Result;
use axum::body::Bytes;
use axum::extract::ws::{Message, WebSocket};
use axum::extract::{Path, Query, State, WebSocketUpgrade};
use axum::http::header::{AUTHORIZATION, CACHE_CONTROL, CONTENT_TYPE};
use axum::http::{HeaderMap, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use clap::Parser;
use dashmap::DashMap;
use futures_util::{SinkExt, StreamExt};
use rdesk_common::{hash_password, verify_password};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::sync::{broadcast, oneshot, Mutex};
use tracing::{debug, info, warn};
use tracing_subscriber::EnvFilter;
use uuid::Uuid;

const PREVIEW_TTL_MS: u64 = 30_000;
const ACCOUNT_PRESENCE_TTL_MS: u64 = 75_000;
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
    account_presence: Arc<DashMap<String, AccountPresence>>,
    frames: Arc<DashMap<String, FrameSnapshot>>,
    viewer_sessions: Arc<DashMap<String, ViewerSession>>,
    command_queues: Arc<DashMap<String, VecDeque<PendingCommand>>>,
    command_waiters: Arc<DashMap<String, oneshot::Sender<CommandResult>>>,
    users: Arc<DashMap<String, UserRecord>>,
    username_index: Arc<DashMap<String, String>>,
    auth_sessions: Arc<DashMap<String, AuthSession>>,
    user_store_path: Arc<String>,
    user_store_write: Arc<Mutex<()>>,
    /// Per-device frame broadcast channels for WebSocket viewers
    frame_broadcasters: Arc<DashMap<String, broadcast::Sender<WsFrame>>>,
    /// Per-device command sender for WebSocket host
    ws_host_cmd_tx: Arc<DashMap<String, tokio::sync::mpsc::UnboundedSender<String>>>,
    /// File transfer temporary storage
    file_store: Arc<DashMap<String, FileBlob>>,
    /// File listing requests/responses
    file_list_responses: Arc<DashMap<String, oneshot::Sender<String>>>,
}

#[derive(Debug, Clone)]
struct WsFrame {
    bytes: Bytes,
    width: u32,
    height: u32,
    captured_at_ms: u64,
    relay_received_at_ms: u64,
}

#[derive(Debug, Clone)]
struct FileBlob {
    data: Bytes,
    filename: String,
    created_at_ms: u64,
    /// device_id of the host this file belongs to (for download auth).
    device_id: String,
}

impl AppState {
    fn new(user_store_path: String) -> Self {
        Self {
            previews: Arc::new(DashMap::new()),
            account_presence: Arc::new(DashMap::new()),
            frames: Arc::new(DashMap::new()),
            viewer_sessions: Arc::new(DashMap::new()),
            command_queues: Arc::new(DashMap::new()),
            command_waiters: Arc::new(DashMap::new()),
            users: Arc::new(DashMap::new()),
            username_index: Arc::new(DashMap::new()),
            auth_sessions: Arc::new(DashMap::new()),
            user_store_path: Arc::new(user_store_path),
            user_store_write: Arc::new(Mutex::new(())),
            frame_broadcasters: Arc::new(DashMap::new()),
            ws_host_cmd_tx: Arc::new(DashMap::new()),
            file_store: Arc::new(DashMap::new()),
            file_list_responses: Arc::new(DashMap::new()),
        }
    }

    fn get_or_create_broadcaster(&self, device_id: &str) -> broadcast::Sender<WsFrame> {
        self.frame_broadcasters
            .entry(device_id.to_string())
            .or_insert_with(|| broadcast::channel(4).0)
            .clone()
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

#[derive(Debug, Clone, Serialize, Deserialize)]
struct AccountPresence {
    device_id: String,
    user_id: String,
    platform: String,
    hostname: String,
    updated_at_ms: u64,
}

#[derive(Debug, Clone)]
struct FrameSnapshot {
    bytes: Bytes,
    width: u32,
    height: u32,
    captured_at_ms: u64,
    relay_received_at_ms: u64,
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

#[derive(Debug, Clone, Serialize, Deserialize)]
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
    host_token: Option<String>,
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
    host_token: String,
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

#[derive(Debug, Deserialize)]
struct UpsertAccountPresenceRequest {
    device_id: String,
    platform: String,
    hostname: String,
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    message: String,
}

#[derive(Debug, Deserialize)]
struct ResolvePreviewRequest {
    password_hash: Option<String>,
    requester_id: Option<String>,
    auth_token: Option<String>,
    requester_hostname: Option<String>,
    requester_peer_os: Option<String>,
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
    #[serde(rename = "timestamp_ms")]
    timestamp_ms: Option<u64>,
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
    if let Err(e) = load_auth_sessions(&state).await {
        warn!("failed to load auth sessions: {e}");
    }
    let app = Router::new()
        .route("/health", get(health))
        .route("/debug", get(debug_state))
        .route("/frame.jpg", get(fetch_frame))
        .route("/session/trust", post(session_trust))
        .route("/input/tap", post(input_tap))
        .route("/input/action", post(input_action))
        .route("/input/long_press", post(input_long_press))
        .route("/input/drag", post(input_drag))
        .route("/input/drag_path", post(input_drag_path))
        .route("/input/text", post(input_text))
        .route("/clipboard/set", post(clipboard_set))
        .route("/clipboard/get", get(clipboard_get))
        .route("/displays", get(list_displays))
        .route("/settings/quality", post(settings_quality))
        .route("/api/preview/register", post(register_preview))
        .route("/api/preview/unregister", post(unregister_preview))
        .route("/api/preview/disconnect_viewers", post(disconnect_viewers))
        .route("/api/preview/resolve/:device_id", post(resolve_preview))
        .route("/api/preview/host/frame", post(upload_frame))
        .route("/api/preview/host/control/poll", get(poll_host_command))
        .route("/api/account/register", post(register_account))
        .route("/api/account/login", post(login_account))
        .route("/api/account/presence", post(upsert_account_presence))
        .route("/api/account/devices", get(list_account_devices))
        .route(
            "/api/preview/host/control/result",
            post(complete_host_command),
        )
        // WebSocket endpoints
        .route("/ws/host/:device_id", get(ws_host_handler))
        .route("/ws/viewer/:device_id", get(ws_viewer_handler))
        // File transfer endpoints
        .route("/api/file/list", post(file_list_request))
        .route("/api/file/upload", post(file_upload))
        .route("/api/file/download/:file_id", get(file_download))
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
        let mut persist_counter: u32 = 0;
        loop {
            interval.tick().await;
            cleanup_expired(cleanup_state.clone());
            // Persist auth sessions every ~5 minutes (20 * 15s)
            persist_counter += 1;
            if persist_counter >= 20 {
                persist_counter = 0;
                let _ = persist_auth_sessions(&cleanup_state).await;
            }
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

async fn debug_state(State(state): State<AppState>) -> Json<Value> {
    let previews: Vec<Value> = state
        .previews
        .iter()
        .map(|e| {
            json!({
                "device_id": e.device_id,
                "platform": e.platform,
                "hostname": e.hostname,
                "auto_accept": e.auto_accept,
                "has_password": !e.password_hash.is_empty(),
                "trusted_viewers": e.trusted_viewers.len(),
                "age_seconds": (now_ms().saturating_sub(e.updated_at_ms)) / 1000,
            })
        })
        .collect();

    let frames: Vec<Value> = state
        .frames
        .iter()
        .map(|e| {
            json!({
                "device_id": e.key().clone(),
                "width": e.width,
                "height": e.height,
                "size_bytes": e.bytes.len(),
                "age_seconds": (now_ms().saturating_sub(e.updated_at_ms)) / 1000,
            })
        })
        .collect();

    let viewers: Vec<Value> = state
        .viewer_sessions
        .iter()
        .map(|e| {
            json!({
                "token_prefix": &e.key()[..8.min(e.key().len())],
                "device_id": e.device_id,
                "age_seconds": (now_ms().saturating_sub(e.last_seen_ms)) / 1000,
            })
        })
        .collect();

    let ws_hosts: Vec<String> = state
        .ws_host_cmd_tx
        .iter()
        .map(|e| e.key().clone())
        .collect();

    let broadcasters: Vec<Value> = state
        .frame_broadcasters
        .iter()
        .map(|e| {
            json!({
                "device_id": e.key().clone(),
                "receiver_count": e.value().receiver_count(),
            })
        })
        .collect();

    Json(json!({
        "previews": previews,
        "frames": frames,
        "viewer_sessions": viewers,
        "ws_hosts": ws_hosts,
        "broadcasters": broadcasters,
        "command_queues": state.command_queues.len(),
    }))
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
    state
        .username_index
        .insert(username.clone(), user.user_id.clone());

    if let Err(err) = persist_users(&state).await {
        state.users.remove(&user.user_id);
        state.username_index.remove(&username);
        warn!(error = %err, "failed to persist registered user");
        return error_response(StatusCode::INTERNAL_SERVER_ERROR, "保存账号失败");
    }

    let session = create_account_session(&state, &user);
    let _ = persist_auth_sessions(&state).await;
    Json(session).into_response()
}

async fn login_account(
    State(state): State<AppState>,
    Json(request): Json<AccountAuthRequest>,
) -> Response {
    let username = normalize_username(&request.username);
    let password = request.password.trim().to_string();
    let Some(user_id) = state
        .username_index
        .get(&username)
        .map(|entry| entry.value().clone())
    else {
        return error_response(StatusCode::UNAUTHORIZED, "账号或密码错误");
    };
    let Some(user) = state.users.get(&user_id).map(|entry| entry.clone()) else {
        return error_response(StatusCode::UNAUTHORIZED, "账号或密码错误");
    };

    let verified = verify_password(&password, &user.password_hash).unwrap_or(false);
    if !verified {
        return error_response(StatusCode::UNAUTHORIZED, "账号或密码错误");
    }

    let session = create_account_session(&state, &user);
    let _ = persist_auth_sessions(&state).await;
    Json(session).into_response()
}

async fn list_account_devices(State(state): State<AppState>, headers: HeaderMap) -> Response {
    let Some(user) = authenticated_user(&state, &headers) else {
        return error_response(StatusCode::UNAUTHORIZED, "登录状态已失效");
    };

    let mut device_map: HashMap<String, AccountDeviceSummary> = state
        .account_presence
        .iter()
        .filter(|entry| {
            entry.user_id == user.user_id && is_fresh(entry.updated_at_ms, ACCOUNT_PRESENCE_TTL_MS)
        })
        .map(|entry| AccountDeviceSummary {
            device_id: entry.device_id.clone(),
            hostname: entry.hostname.clone(),
            platform: entry.platform.clone(),
            updated_at_ms: entry.updated_at_ms,
        })
        .map(|entry| (entry.device_id.clone(), entry))
        .collect();

    for entry in state.previews.iter().filter(|entry| {
        entry.user_id.as_deref() == Some(user.user_id.as_str())
            && is_fresh(entry.updated_at_ms, PREVIEW_TTL_MS)
    }) {
        match device_map.get_mut(entry.device_id.as_str()) {
            Some(summary) => {
                summary.hostname = entry.hostname.clone();
                summary.platform = entry.platform.clone();
                if entry.updated_at_ms > summary.updated_at_ms {
                    summary.updated_at_ms = entry.updated_at_ms;
                }
            }
            None => {
                device_map.insert(
                    entry.device_id.clone(),
                    AccountDeviceSummary {
                        device_id: entry.device_id.clone(),
                        hostname: entry.hostname.clone(),
                        platform: entry.platform.clone(),
                        updated_at_ms: entry.updated_at_ms,
                    },
                );
            }
        }
    }

    let mut devices: Vec<AccountDeviceSummary> = device_map.into_values().collect();
    devices.sort_by(|left, right| right.updated_at_ms.cmp(&left.updated_at_ms));
    info!(
        user_id = %user.user_id,
        device_count = devices.len(),
        "listed account devices"
    );

    (StatusCode::OK, Json(AccountDevicesResponse { devices })).into_response()
}

async fn upsert_account_presence(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<UpsertAccountPresenceRequest>,
) -> Response {
    let Some(user) = authenticated_user(&state, &headers) else {
        return error_response(StatusCode::UNAUTHORIZED, "登录状态已失效");
    };

    let device_id = request.device_id.trim();
    if device_id.is_empty() {
        return error_response(StatusCode::BAD_REQUEST, "设备ID不能为空");
    }

    state.account_presence.insert(
        device_id.to_string(),
        AccountPresence {
            device_id: device_id.to_string(),
            user_id: user.user_id.clone(),
            platform: request.platform.trim().to_string(),
            hostname: request.hostname.trim().to_string(),
            updated_at_ms: now_ms(),
        },
    );
    info!(
        user_id = %user.user_id,
        device_id = %device_id,
        "updated account presence"
    );

    (StatusCode::OK, Json(json!({"ok": true}))).into_response()
}

async fn register_preview(
    State(state): State<AppState>,
    Json(request): Json<RegisterPreviewRequest>,
) -> Response {
    let existing = state
        .previews
        .get(&request.device_id)
        .map(|entry| entry.clone());

    // Renewal logic:
    //  - Matching host_token → keep existing token (normal heartbeat).
    //  - Mismatched/empty host_token BUT same account owner (via auth_token)
    //    → keep existing token (handles server restarts, client re-launches).
    //  - Mismatched/empty host_token AND different/no account → reject.
    //  - No existing entry → generate new token.
    let host_token = if let Some(ref entry) = existing {
        let provided = request.host_token.as_deref().unwrap_or("");
        if !provided.is_empty() && provided == entry.host_token {
            // Normal heartbeat — token matches.
            entry.host_token.clone()
        } else {
            // Token missing or mismatched — check account ownership.
            let caller_uid = request
                .auth_token
                .as_deref()
                .and_then(|token| validate_auth_session(&state, token));
            let same_owner =
                caller_uid.is_some() && entry.user_id.is_some() && caller_uid == entry.user_id;
            if same_owner {
                // Same account owner — return existing token so client
                // can recover the correct host_token.
                entry.host_token.clone()
            } else {
                warn!(
                    device_id = %request.device_id,
                    "register_preview rejected: missing or mismatched host_token"
                );
                return StatusCode::UNAUTHORIZED.into_response();
            }
        }
    } else {
        new_token()
    };

    let user_id = request
        .auth_token
        .as_deref()
        .and_then(|token| validate_auth_session(&state, token))
        // Preserve existing account binding when heartbeat omits auth token.
        .or_else(|| existing.as_ref().and_then(|entry| entry.user_id.clone()));

    let registration = PreviewRegistration {
        device_id: request.device_id.clone(),
        user_id: user_id.clone(),
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
    let has_auth_token = request
        .auth_token
        .as_ref()
        .is_some_and(|token| !token.trim().is_empty());
    info!(
        device_id = %request.device_id,
        has_auth_token,
        user_bound = user_id.is_some(),
        "registered preview host"
    );

    Json(RegisterPreviewResponse { host_token }).into_response()
}

async fn unregister_preview(
    State(state): State<AppState>,
    Json(request): Json<UnregisterPreviewRequest>,
) -> StatusCode {
    if !validate_host(&state, &request.device_id, &request.host_token) {
        warn!(device_id = %request.device_id, "unregister_preview rejected: invalid host_token");
        return StatusCode::UNAUTHORIZED;
    }
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
    let same_account_ok = registration.user_id.as_ref().is_some_and(|host_uid| {
        !host_uid.is_empty()
            && request
                .auth_token
                .as_deref()
                .and_then(|token| validate_auth_session(&state, token))
                .as_ref()
                == Some(host_uid)
    });
    let authorized = password_ok || trusted_ok || same_account_ok;

    if !authorized {
        // When viewer tries passwordless (empty password) and not authorized,
        // push "incoming_request" to host and wait for acceptance.
        let passwordless = request
            .password_hash
            .as_ref()
            .map_or(true, |h| h.is_empty());
        if passwordless {
            if let (Some(requester_id), Some(host_token)) = (
                request.requester_id.as_ref(),
                state
                    .previews
                    .get(&device_id)
                    .and_then(|e| Some(e.value().host_token.clone())),
            ) {
                if validate_host(&state, &device_id, &host_token) {
                    let command_id = Uuid::new_v4().to_string();
                    let (tx, rx) = oneshot::channel();
                    state.command_waiters.insert(command_id.clone(), tx);
                    state
                        .command_queues
                        .entry(device_id.clone())
                        .or_default()
                        .push_back(PendingCommand {
                            command_id: command_id.clone(),
                            kind: "incoming_request".to_string(),
                            payload: json!({
                                "deviceId": requester_id,
                                "hostname": request.requester_hostname.as_deref().unwrap_or("未知设备"),
                                "peerOs": request.requester_peer_os.as_deref().unwrap_or("未知"),
                            }),
                            queued_at_ms: now_ms(),
                        });

                    // Wait up to 60 seconds for the host to accept/reject.
                    let accepted = match tokio::time::timeout(Duration::from_secs(60), rx).await {
                        Ok(Ok(result)) => result.ok,
                        _ => {
                            state.command_waiters.remove(&command_id);
                            false
                        }
                    };

                    if accepted {
                        // Host accepted – authorize the viewer.
                        let viewer_token = new_token();
                        state.viewer_sessions.insert(
                            viewer_token.clone(),
                            ViewerSession {
                                device_id: device_id.clone(),
                                last_seen_ms: now_ms(),
                            },
                        );
                        let public_origin = request_public_origin(&headers);
                        let endpoint = format!(
                            "{public_origin}/frame.jpg?device_id={device_id}&token={viewer_token}"
                        );
                        return Json(ResolvePreviewResponse {
                            found: true,
                            authorized: true,
                            endpoint: Some(endpoint),
                            platform: Some(registration.platform),
                            hostname: Some(registration.hostname),
                            updated_at_ms: Some(registration.updated_at_ms),
                        });
                    }
                }
            }
        }
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
    let public_origin = request_public_origin(&headers);
    let endpoint = format!("{public_origin}/frame.jpg?device_id={device_id}&token={viewer_token}");

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
        warn!(device_id = %query.device_id, "frame upload rejected: invalid host token");
        return StatusCode::UNAUTHORIZED;
    }

    let received_at_ms = now_ms();
    let captured_at_ms = query
        .timestamp_ms
        .filter(|value| *value > 0)
        .unwrap_or(received_at_ms);

    debug!(
        device_id = %query.device_id,
        width = query.width,
        height = query.height,
        size = body.len(),
        "frame uploaded"
    );

    // Broadcast to WebSocket viewers if any are connected
    if let Some(broadcaster) = state.frame_broadcasters.get(&query.device_id) {
        let frame = WsFrame {
            bytes: body.clone(),
            width: query.width,
            height: query.height,
            captured_at_ms,
            relay_received_at_ms: received_at_ms,
        };
        let _ = broadcaster.send(frame);
    }

    state.frames.insert(
        query.device_id,
        FrameSnapshot {
            bytes: body,
            width: query.width,
            height: query.height,
            captured_at_ms,
            relay_received_at_ms: received_at_ms,
            updated_at_ms: received_at_ms,
        },
    );
    StatusCode::OK
}

async fn fetch_frame(
    State(state): State<AppState>,
    Query(query): Query<RelayViewerQuery>,
) -> Response {
    if !validate_viewer(&state, &query.device_id, &query.token) {
        warn!(device_id = %query.device_id, "fetch_frame rejected: invalid viewer token");
        return StatusCode::UNAUTHORIZED.into_response();
    }

    let Some(frame) = state.frames.get(&query.device_id) else {
        info!(device_id = %query.device_id, "fetch_frame: no frame available");
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };
    if !is_fresh(frame.updated_at_ms, PREVIEW_TTL_MS) {
        info!(device_id = %query.device_id, "fetch_frame: frame expired");
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
        &frame.captured_at_ms.to_string(),
    );
    insert_header(
        &mut headers,
        "x-rdesk-captured-at",
        &frame.captured_at_ms.to_string(),
    );
    insert_header(
        &mut headers,
        "x-rdesk-relay-received-at",
        &frame.relay_received_at_ms.to_string(),
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

async fn input_drag_path(
    State(state): State<AppState>,
    Query(query): Query<RelayViewerQuery>,
    Json(request): Json<Value>,
) -> Response {
    relay_bool_command(&state, &query, "drag_path", request).await
}

async fn settings_quality(
    State(state): State<AppState>,
    Query(query): Query<RelayViewerQuery>,
    Json(request): Json<Value>,
) -> Response {
    relay_bool_command(&state, &query, "quality", request).await
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

async fn list_displays(
    State(state): State<AppState>,
    Query(query): Query<RelayViewerQuery>,
) -> Response {
    match forward_command(&state, &query, "list_displays", json!({})).await {
        Ok(result) => {
            // The host returns display list as JSON text in result.text
            let text = result.text.unwrap_or_else(|| "[]".to_string());
            (
                StatusCode::OK,
                [(axum::http::header::CONTENT_TYPE, "application/json")],
                text,
            )
                .into_response()
        }
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

// ─── WebSocket Host handler ───
// Host connects, sends binary frames, receives JSON commands
#[derive(Debug, Deserialize)]
struct WsHostAuth {
    host_token: String,
}

async fn ws_host_handler(
    Path(device_id): Path<String>,
    Query(auth): Query<WsHostAuth>,
    State(state): State<AppState>,
    ws: WebSocketUpgrade,
) -> Response {
    if !validate_host(&state, &device_id, &auth.host_token) {
        return StatusCode::UNAUTHORIZED.into_response();
    }
    let device_id_clone = device_id.clone();
    ws.on_upgrade(move |socket| handle_ws_host(socket, state, device_id_clone))
}

async fn handle_ws_host(socket: WebSocket, state: AppState, device_id: String) {
    let (mut ws_tx, mut ws_rx) = socket.split();
    let broadcaster = state.get_or_create_broadcaster(&device_id);
    let (cmd_tx, mut cmd_rx) = tokio::sync::mpsc::unbounded_channel::<String>();
    state.ws_host_cmd_tx.insert(device_id.clone(), cmd_tx);

    info!(device_id = %device_id, "WebSocket host connected");

    let device_id_tx = device_id.clone();
    let send_task = tokio::spawn(async move {
        while let Some(cmd_json) = cmd_rx.recv().await {
            if ws_tx.send(Message::Text(cmd_json.into())).await.is_err() {
                break;
            }
        }
        let _ = ws_tx.close().await;
        info!(device_id = %device_id_tx, "WebSocket host send loop ended");
    });

    while let Some(Ok(msg)) = ws_rx.next().await {
        match msg {
            Message::Binary(data) => {
                let bytes = Bytes::from(data.to_vec());
                // Parse header: first 16 bytes = width(4) + height(4) + timestamp(8)
                if bytes.len() < 16 {
                    continue;
                }
                let width = u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
                let height = u32::from_le_bytes([bytes[4], bytes[5], bytes[6], bytes[7]]);
                let host_timestamp_ms = u64::from_le_bytes([
                    bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14],
                    bytes[15],
                ]);
                let jpeg_data = bytes.slice(16..);

                let received_at_ms = now_ms();
                let captured_at_ms = if host_timestamp_ms > 0 {
                    host_timestamp_ms
                } else {
                    received_at_ms
                };
                let frame = WsFrame {
                    bytes: jpeg_data.clone(),
                    width,
                    height,
                    captured_at_ms,
                    relay_received_at_ms: received_at_ms,
                };

                let _ = broadcaster.send(frame);

                state.frames.insert(
                    device_id.clone(),
                    FrameSnapshot {
                        bytes: jpeg_data,
                        width,
                        height,
                        captured_at_ms,
                        relay_received_at_ms: received_at_ms,
                        updated_at_ms: received_at_ms,
                    },
                );
            }
            Message::Text(text) => {
                // Host sends command results as JSON text
                if let Ok(result) = serde_json::from_str::<CommandResultRequest>(&text) {
                    if let Some((_, sender)) = state.command_waiters.remove(&result.command_id) {
                        let _ = sender.send(CommandResult {
                            ok: result.ok,
                            text: result.text,
                        });
                    }
                }
            }
            Message::Close(_) => break,
            _ => {}
        }
    }

    send_task.abort();
    state.ws_host_cmd_tx.remove(&device_id);
    info!(device_id = %device_id, "WebSocket host disconnected");
}

// ─── WebSocket Viewer handler ───
#[derive(Debug, Deserialize)]
struct WsViewerAuth {
    token: String,
}

async fn ws_viewer_handler(
    Path(device_id): Path<String>,
    Query(auth): Query<WsViewerAuth>,
    State(state): State<AppState>,
    ws: WebSocketUpgrade,
) -> Response {
    if !validate_viewer(&state, &device_id, &auth.token) {
        return StatusCode::UNAUTHORIZED.into_response();
    }
    let device_id_clone = device_id.clone();
    let token = auth.token.clone();
    ws.on_upgrade(move |socket| handle_ws_viewer(socket, state, device_id_clone, token))
}

async fn handle_ws_viewer(socket: WebSocket, state: AppState, device_id: String, token: String) {
    let (mut ws_tx, mut ws_rx) = socket.split();
    let broadcaster = state.get_or_create_broadcaster(&device_id);
    let mut frame_rx = broadcaster.subscribe();

    info!(device_id = %device_id, "WebSocket viewer connected");

    let state_send = state.clone();
    let device_id_send = device_id.clone();
    let token_send = token.clone();
    let send_task = tokio::spawn(async move {
        let mut validity_check = tokio::time::interval(Duration::from_millis(500));
        // The first tick completes immediately; consume it so the loop
        // doesn't start with a redundant validation.
        validity_check.tick().await;
        loop {
            tokio::select! {
                frame = frame_rx.recv() => {
                        match frame {
                            Ok(frame) => {
                                // Build binary message: RDF1 header + JPEG.
                                let mut buf = Vec::with_capacity(28 + frame.bytes.len());
                                buf.extend_from_slice(b"RDF1");
                                buf.extend_from_slice(&frame.width.to_le_bytes());
                                buf.extend_from_slice(&frame.height.to_le_bytes());
                                buf.extend_from_slice(&frame.captured_at_ms.to_le_bytes());
                                buf.extend_from_slice(&frame.relay_received_at_ms.to_le_bytes());
                                buf.extend_from_slice(&frame.bytes);
                                if ws_tx.send(Message::Binary(buf.into())).await.is_err() {
                                break;
                            }
                        }
                        Err(broadcast::error::RecvError::Lagged(_)) => continue,
                        Err(broadcast::error::RecvError::Closed) => break,
                    }
                }
                _ = validity_check.tick() => {
                    // Periodically verify the viewer session is still valid.
                    // When the host disconnects viewers, their tokens are
                    // removed from viewer_sessions — this check detects that
                    // and closes the WebSocket so the viewer exits promptly.
                    if !validate_viewer(&state_send, &device_id_send, &token_send) {
                        info!(device_id = %device_id_send, "WebSocket viewer session revoked, closing");
                        break;
                    }
                }
            }
        }
        let _ = ws_tx.close().await;
        info!(device_id = %device_id_send, "WebSocket viewer frame send loop ended");
    });

    while let Some(Ok(msg)) = ws_rx.next().await {
        if let Message::Text(text) = msg {
            // Viewer sends commands as JSON
            if let Ok(cmd) = serde_json::from_str::<Value>(&text) {
                let kind = cmd.get("kind").and_then(|v| v.as_str()).unwrap_or("");
                let payload = cmd.get("payload").cloned().unwrap_or(json!({}));

                // Forward via WS if host has WS connection
                if let Some(host_tx) = state.ws_host_cmd_tx.get(&device_id) {
                    let command_id = new_token();
                    let ws_cmd = json!({
                        "command_id": command_id,
                        "kind": kind,
                        "payload": payload,
                    });
                    let _ = host_tx.send(ws_cmd.to_string());
                } else {
                    // Fallback: use HTTP command queue
                    let query = RelayViewerQuery {
                        device_id: device_id.clone(),
                        token: token.clone(),
                    };
                    let _ = forward_command(&state, &query, kind, payload).await;
                }
            }
        }
    }

    send_task.abort();
    info!(device_id = %device_id, "WebSocket viewer disconnected");
}

// ─── File Transfer endpoints ───

#[derive(Debug, Deserialize)]
struct FileListRequest {
    device_id: String,
    token: String,
    path: String,
}

async fn file_list_request(
    State(state): State<AppState>,
    Json(request): Json<FileListRequest>,
) -> Response {
    if !validate_viewer(&state, &request.device_id, &request.token) {
        return StatusCode::UNAUTHORIZED.into_response();
    }

    let command_id = new_token();
    let query = RelayViewerQuery {
        device_id: request.device_id.clone(),
        token: request.token,
    };

    match forward_command(&state, &query, "file_list", json!({ "path": request.path })).await {
        Ok(result) => {
            let listing = result.text.unwrap_or_else(|| "[]".to_string());
            (
                StatusCode::OK,
                Json(json!({ "ok": true, "files": listing, "command_id": command_id })),
            )
                .into_response()
        }
        Err(status) => status.into_response(),
    }
}

#[derive(Debug, Deserialize)]
struct FileUploadQuery {
    device_id: String,
    token: String,
    filename: String,
    remote_path: String,
}

#[derive(Debug, Deserialize)]
struct FileDownloadQuery {
    token: String,
}

async fn file_upload(
    State(state): State<AppState>,
    Query(query): Query<FileUploadQuery>,
    body: Bytes,
) -> Response {
    if !validate_viewer(&state, &query.device_id, &query.token) {
        return StatusCode::UNAUTHORIZED.into_response();
    }

    let file_id = new_token();
    state.file_store.insert(
        file_id.clone(),
        FileBlob {
            data: body,
            filename: query.filename.clone(),
            created_at_ms: now_ms(),
            device_id: query.device_id.clone(),
        },
    );

    // Tell the host to download this file
    let relay_query = RelayViewerQuery {
        device_id: query.device_id,
        token: query.token,
    };
    let _ = forward_command(
        &state,
        &relay_query,
        "file_receive",
        json!({
            "file_id": file_id,
            "filename": query.filename,
            "remote_path": query.remote_path,
        }),
    )
    .await;

    (
        StatusCode::OK,
        Json(json!({ "ok": true, "file_id": file_id })),
    )
        .into_response()
}

async fn file_download(
    Path(file_id): Path<String>,
    Query(query): Query<FileDownloadQuery>,
    State(state): State<AppState>,
) -> Response {
    let Some(blob) = state.file_store.get(&file_id) else {
        return StatusCode::NOT_FOUND.into_response();
    };

    // Verify the requester has a valid viewer session for the file's device.
    if !validate_viewer(&state, &blob.device_id, &query.token) {
        drop(blob);
        return StatusCode::UNAUTHORIZED.into_response();
    }

    let mut headers = HeaderMap::new();
    headers.insert(
        CONTENT_TYPE,
        HeaderValue::from_static("application/octet-stream"),
    );
    insert_header(&mut headers, "x-rdesk-filename", &blob.filename);

    let data = blob.data.clone();
    drop(blob);

    (StatusCode::OK, headers, data).into_response()
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
        state
            .username_index
            .insert(user.username.clone(), user.user_id.clone());
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

fn auth_sessions_path(user_store_path: &str) -> std::path::PathBuf {
    let base = FsPath::new(user_store_path);
    base.with_file_name("auth_sessions.json")
}

async fn load_auth_sessions(state: &AppState) -> Result<()> {
    let path = auth_sessions_path(&state.user_store_path);
    if !path.exists() {
        return Ok(());
    }
    let raw = tokio::fs::read_to_string(&path).await?;
    if raw.trim().is_empty() {
        return Ok(());
    }
    let sessions: std::collections::HashMap<String, AuthSession> = serde_json::from_str(&raw)?;
    let now = now_ms();
    for (token, session) in sessions {
        if now.saturating_sub(session.last_seen_ms) <= AUTH_SESSION_TTL_MS {
            state.auth_sessions.insert(token, session);
        }
    }
    info!(
        count = state.auth_sessions.len(),
        "loaded auth sessions from disk"
    );
    Ok(())
}

async fn persist_auth_sessions(state: &AppState) -> Result<()> {
    let _guard = state.user_store_write.lock().await;
    let path = auth_sessions_path(&state.user_store_path);
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }
    let sessions: std::collections::HashMap<String, AuthSession> = state
        .auth_sessions
        .iter()
        .map(|entry| (entry.key().clone(), entry.value().clone()))
        .collect();
    let payload = serde_json::to_string_pretty(&sessions)?;
    tokio::fs::write(path, payload).await?;
    Ok(())
}

fn normalize_username(raw: &str) -> String {
    raw.trim().to_lowercase()
}

fn error_response(status: StatusCode, message: &str) -> Response {
    (
        status,
        Json(ErrorResponse {
            message: message.to_string(),
        }),
    )
        .into_response()
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

    let stale_presence: Vec<String> = state
        .account_presence
        .iter()
        .filter(|entry| now.saturating_sub(entry.updated_at_ms) > ACCOUNT_PRESENCE_TTL_MS)
        .map(|entry| entry.key().clone())
        .collect();
    for device_id in stale_presence {
        state.account_presence.remove(&device_id);
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

    // Clean up expired file blobs (5 min TTL)
    let stale_files: Vec<String> = state
        .file_store
        .iter()
        .filter(|entry| now.saturating_sub(entry.created_at_ms) > 300_000)
        .map(|entry| entry.key().clone())
        .collect();
    for file_id in stale_files {
        state.file_store.remove(&file_id);
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

fn request_public_origin(headers: &HeaderMap) -> String {
    let host = headers
        .get("x-forwarded-host")
        .or_else(|| headers.get("host"))
        .and_then(|value| value.to_str().ok())
        .filter(|value| !value.is_empty())
        .unwrap_or("127.0.0.1:21116")
        .to_string();
    let proto = headers
        .get("x-forwarded-proto")
        .and_then(|value| value.to_str().ok())
        .filter(|value| !value.is_empty())
        .unwrap_or("http");
    format!("{proto}://{host}")
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
