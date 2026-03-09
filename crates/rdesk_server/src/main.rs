use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::Result;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};
use clap::Parser;
use dashmap::DashMap;
use serde::{Deserialize, Serialize};
use tracing::{info, warn};
use tracing_subscriber::EnvFilter;

/// rdesk signaling and relay server entrypoint.
#[derive(Debug, Parser)]
#[command(name = "rdesk-server")]
#[command(about = "Preview registration and relay stub server for rdesk MVP")]
struct Args {
    #[arg(long, default_value = "0.0.0.0")]
    host: String,
    #[arg(long, default_value_t = 21116)]
    signaling_port: u16,
    #[arg(long, default_value_t = 21117)]
    relay_port: u16,
}

#[derive(Clone, Default)]
struct AppState {
    previews: Arc<DashMap<String, PreviewRegistration>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PreviewRegistration {
    device_id: String,
    endpoint: String,
    platform: String,
    hostname: String,
    password_hash: String,
    auto_accept: bool,
    trusted_viewers: Vec<String>,
    updated_at_ms: u64,
}

#[derive(Debug, Deserialize)]
struct RegisterPreviewRequest {
    device_id: String,
    endpoint: String,
    platform: String,
    hostname: String,
    password_hash: String,
    auto_accept: bool,
    trusted_viewers: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct UnregisterPreviewRequest {
    device_id: String,
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
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    let args = Args::parse();
    let state = AppState::default();
    let app = Router::new()
        .route("/health", get(health))
        .route("/api/preview/register", post(register_preview))
        .route("/api/preview/unregister", post(unregister_preview))
        .route("/api/preview/resolve/:device_id", post(resolve_preview))
        .with_state(state.clone());

    let signaling_addr: SocketAddr = format!("{}:{}", args.host, args.signaling_port).parse()?;
    info!(
        host = %args.host,
        signaling_port = args.signaling_port,
        relay_port = args.relay_port,
        "starting rdesk preview registry server"
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
    })
}

async fn register_preview(
    State(state): State<AppState>,
    Json(request): Json<RegisterPreviewRequest>,
) -> StatusCode {
    let registration = PreviewRegistration {
        device_id: request.device_id.clone(),
        endpoint: request.endpoint,
        platform: request.platform,
        hostname: request.hostname,
        password_hash: request.password_hash,
        auto_accept: request.auto_accept,
        trusted_viewers: request.trusted_viewers,
        updated_at_ms: now_ms(),
    };
    state.previews.insert(request.device_id.clone(), registration);
    info!(device_id = %request.device_id, "registered preview endpoint");
    StatusCode::OK
}

async fn unregister_preview(
    State(state): State<AppState>,
    Json(request): Json<UnregisterPreviewRequest>,
) -> StatusCode {
    state.previews.remove(&request.device_id);
    info!(device_id = %request.device_id, "unregistered preview endpoint");
    StatusCode::OK
}

async fn resolve_preview(
    Path(device_id): Path<String>,
    State(state): State<AppState>,
    Json(request): Json<ResolvePreviewRequest>,
) -> Json<ResolvePreviewResponse> {
    if let Some(entry) = state.previews.get(&device_id) {
        let registration = entry.clone();
        if is_fresh(registration.updated_at_ms) {
            let password_ok = request
                .password_hash
                .as_ref()
                .is_some_and(|hash| !hash.is_empty() && *hash == registration.password_hash);
            let trusted_ok = registration.auto_accept
                && request
                    .requester_id
                    .as_ref()
                    .is_some_and(|requester| registration.trusted_viewers.iter().any(|item| item == requester));
            let authorized = password_ok || trusted_ok;
            return Json(ResolvePreviewResponse {
                found: true,
                authorized,
                endpoint: authorized.then_some(registration.endpoint),
                platform: authorized.then_some(registration.platform),
                hostname: authorized.then_some(registration.hostname),
                updated_at_ms: authorized.then_some(registration.updated_at_ms),
            });
        }
        drop(entry);
        state.previews.remove(&device_id);
        warn!(device_id = %device_id, "dropping stale preview registration");
    }

    Json(ResolvePreviewResponse {
        found: false,
        authorized: false,
        endpoint: None,
        platform: None,
        hostname: None,
        updated_at_ms: None,
    })
}

fn cleanup_expired(state: AppState) {
    let stale: Vec<String> = state
        .previews
        .iter()
        .filter(|entry| !is_fresh(entry.updated_at_ms))
        .map(|entry| entry.key().clone())
        .collect();

    for device_id in stale {
        state.previews.remove(&device_id);
        warn!(device_id = %device_id, "expired preview registration removed");
    }
}

fn is_fresh(updated_at_ms: u64) -> bool {
    now_ms().saturating_sub(updated_at_ms) <= 30_000
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}
