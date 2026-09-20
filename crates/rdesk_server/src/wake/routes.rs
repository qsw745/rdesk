use super::{model::*, store::update_wake};
use crate::{authenticated_user, new_token, now_ms, parse_bearer_token, AppState, UserRecord};
use axum::{
    extract::{DefaultBodyLimit, Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::time::{Duration, Instant};

pub fn routes() -> Router<AppState> {
    Router::new()
        .merge(super::pairing::routes())
        .route("/api/wake/targets", get(targets).post(create_target))
        .route(
            "/api/wake/targets/:id",
            axum::routing::put(update_target).delete(delete_target),
        )
        .route("/api/wake/targets/:id/rotate-token", post(rotate_target))
        .route("/api/wake/targets/:id/heartbeat", post(heartbeat))
        .route("/api/wake/agents", get(agents).post(create_agent))
        .route("/api/wake/agents/:id", axum::routing::delete(delete_agent))
        .route("/api/wake/agents/:id/disable", post(disable_agent))
        .route("/api/wake/agents/:id/stop", post(stop_agent))
        .route("/api/wake/agents/:id/enable", post(enable_agent))
        .route("/api/wake/agents/:id/poll", post(poll))
        .route("/api/wake/requests", post(create_request).get(history))
        .route("/api/wake/requests/:id", get(request_status))
        .route("/api/wake/requests/:id/authorize-send", post(authorize))
        .route("/api/wake/requests/:id/result", post(result))
        .layer(DefaultBodyLimit::max(16 * 1024))
}
pub(super) fn account(state: &AppState, h: &HeaderMap) -> WakeResult<UserRecord> {
    authenticated_user(state, h).ok_or(WakeError("unauthorized"))
}
pub(super) fn digest(token: &str) -> String {
    format!("{:x}", Sha256::digest(token.as_bytes()))
}
fn credential() -> (String, String) {
    let t = format!("{}{}", new_token(), new_token());
    let h = digest(&t);
    (t, h)
}
pub(super) fn bearer(h: &HeaderMap) -> WakeResult<&str> {
    h.get("authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(parse_bearer_token)
        .ok_or(WakeError("unauthorized"))
}
fn device_owner(state: &AppState, h: &HeaderMap, id: &str, agent: bool) -> WakeResult<String> {
    let token = bearer(h)?;
    if token.len() != 64 {
        return Err(WakeError("unauthorized"));
    }
    let hash = digest(token);
    state
        .users
        .iter()
        .find_map(|u| {
            let valid = if agent {
                u.wake
                    .agents
                    .iter()
                    .any(|a| a.id == id && a.enabled && a.token_hash == hash)
            } else {
                u.wake
                    .targets
                    .iter()
                    .any(|t| t.id == id && t.token_hash == hash)
            };
            valid.then(|| u.user_id.clone())
        })
        .ok_or(WakeError("unauthorized"))
}
pub(super) fn name(raw: &str) -> WakeResult<String> {
    let s = raw.trim();
    if s.is_empty() || s.chars().count() > 80 {
        Err(WakeError("invalid_name"))
    } else {
        Ok(s.into())
    }
}
fn fresh(seen: Option<u64>) -> bool {
    seen.is_some_and(|t| now_ms().saturating_sub(t) < 30_000)
}
fn agent_seen(state: &AppState, id: &str) -> Option<u64> {
    state.wake_runtime.agents.lock().unwrap().get(id).copied()
}
fn target_seen(state: &AppState, id: &str) -> Option<u64> {
    state.wake_runtime.targets.lock().unwrap().get(id).copied()
}
async fn advance(state: &AppState, owner: &str) -> WakeResult<()> {
    let now = now_ms();
    let beats = state.wake_runtime.targets.lock().unwrap().clone();
    let user = state
        .users
        .get(owner)
        .ok_or(WakeError("not_found"))?
        .clone();
    let changed = user.wake.requests.iter().any(|r| {
        let mut n = r.clone();
        n.advance(now, beats.get(&r.target_id).copied());
        n.phase != r.phase
    }) || user
        .wake
        .requests
        .iter()
        .any(|r| now.saturating_sub(r.created_at_ms) >= 604_800_000);
    if changed {
        update_wake(state, owner, |d| {
            for r in &mut d.requests {
                r.advance(now, beats.get(&r.target_id).copied());
            }
            Ok(())
        })
        .await?;
    }
    Ok(())
}
async fn targets(State(s): State<AppState>, h: HeaderMap) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    advance(&s, &u.user_id).await?;
    let u = s.users.get(&u.user_id).ok_or(WakeError("not_found"))?;
    let items:Vec<_>=u.wake.targets.iter().map(|t|json!({"id":t.id,"name":t.name,"device_id":t.device_id,"mac":t.mac,"agent_id":t.agent_id,"revision":t.revision,"setup_complete":t.setup_complete,"online":fresh(target_seen(&s,&t.id)),"last_seen_ms":target_seen(&s,&t.id),"agent_online":u.wake.agents.iter().any(|a|a.id==t.agent_id&&a.enabled)&&fresh(agent_seen(&s,&t.agent_id))})).collect();
    Ok(Json(json!({"targets":items,"server_time_ms":now_ms()})))
}
async fn agents(State(s): State<AppState>, h: HeaderMap) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    let items:Vec<_>=u.wake.agents.iter().map(|a|json!({"id":a.id,"name":a.name,"enabled":a.enabled,"online":a.enabled&&fresh(agent_seen(&s,&a.id)),"last_seen_ms":agent_seen(&s,&a.id)})).collect();
    Ok(Json(json!({"agents":items,"server_time_ms":now_ms()})))
}
#[derive(Deserialize)]
struct Named {
    name: String,
}
async fn create_agent(
    State(s): State<AppState>,
    h: HeaderMap,
    Json(body): Json<Named>,
) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    let name = name(&body.name)?;
    let id = new_token();
    let (token, hash) = credential();
    update_wake(&s, &u.user_id, |d| {
        if d.agents.len() >= 5 {
            return Err(WakeError("rate_limited"));
        }
        d.agents.push(WakeAgent {
            id: id.clone(),
            name,
            token_hash: hash,
            enabled: true,
        });
        Ok(())
    })
    .await?;
    Ok(Json(json!({"id":id,"token":token})))
}
#[derive(Deserialize)]
struct TargetInput {
    name: String,
    #[serde(default)]
    device_id: String,
    mac: String,
    agent_id: String,
}
async fn create_target(
    State(s): State<AppState>,
    h: HeaderMap,
    Json(b): Json<TargetInput>,
) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    let name = name(&b.name)?;
    let mac = MacAddress::parse(&b.mac)?.normalized();
    if b.device_id.trim().is_empty() || b.device_id.len() > 128 {
        return Err(WakeError("invalid_device"));
    }
    let id = new_token();
    let (token, hash) = credential();
    update_wake(&s, &u.user_id, |d| {
        if d.targets.len() >= 20 {
            return Err(WakeError("rate_limited"));
        }
        if !d.agents.iter().any(|a| a.id == b.agent_id && a.enabled) {
            return Err(WakeError("not_found"));
        }
        if d.targets.iter().any(|t| t.device_id == b.device_id) {
            return Err(WakeError("conflict"));
        }
        d.targets.push(WakeTarget {
            setup_complete: true,
            id: id.clone(),
            name,
            device_id: b.device_id,
            mac,
            agent_id: b.agent_id,
            revision: 1,
            token_hash: hash,
            created_at_ms: now_ms(),
        });
        Ok(())
    })
    .await?;
    Ok(Json(json!({"id":id,"token":token})))
}
async fn update_target(
    State(s): State<AppState>,
    Path(id): Path<String>,
    h: HeaderMap,
    Json(b): Json<TargetInput>,
) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    let name = name(&b.name)?;
    let mac = MacAddress::parse(&b.mac)?.normalized();
    update_wake(&s, &u.user_id, |d| {
        if !d.agents.iter().any(|a| a.id == b.agent_id && a.enabled) {
            return Err(WakeError("not_found"));
        }
        let t = d
            .targets
            .iter_mut()
            .find(|t| t.id == id)
            .ok_or(WakeError("not_found"))?;
        t.name = name;
        t.mac = mac;
        t.agent_id = b.agent_id;
        t.revision += 1;
        d.cancel_target(&id);
        Ok(())
    })
    .await?;
    Ok(Json(json!({"ok":true})))
}
async fn delete_target(
    State(s): State<AppState>,
    Path(id): Path<String>,
    h: HeaderMap,
) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    update_wake(&s, &u.user_id, |d| {
        if !d.targets.iter().any(|t| t.id == id) {
            return Err(WakeError("not_found"));
        }
        d.targets.retain(|t| t.id != id);
        d.requests.retain(|r| r.target_id != id);
        Ok(())
    })
    .await?;
    s.wake_runtime.targets.lock().unwrap().remove(&id);
    Ok(Json(json!({"ok":true})))
}
async fn rotate_target(
    State(s): State<AppState>,
    Path(id): Path<String>,
    h: HeaderMap,
) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    let (token, hash) = credential();
    update_wake(&s, &u.user_id, |d| {
        let t = d
            .targets
            .iter_mut()
            .find(|t| t.id == id)
            .ok_or(WakeError("not_found"))?;
        t.token_hash = hash;
        Ok(())
    })
    .await?;
    s.wake_runtime.targets.lock().unwrap().remove(&id);
    Ok(Json(json!({"id":id,"token":token})))
}
async fn heartbeat(
    State(s): State<AppState>,
    Path(id): Path<String>,
    h: HeaderMap,
) -> WakeResult<Json<Value>> {
    device_owner(&s, &h, &id, false)?;
    s.wake_runtime.targets.lock().unwrap().insert(id, now_ms());
    Ok(Json(json!({"ok":true,"server_time_ms":now_ms()})))
}
async fn revoke(s: &AppState, owner: &str, id: &str) -> WakeResult<Json<Value>> {
    update_wake(s, owner, |d| {
        if !d.agents.iter().any(|a| a.id == id) {
            return Err(WakeError("not_found"));
        }
        d.agents.retain(|a| a.id != id);
        for r in &mut d.requests {
            if r.agent_id == id && r.phase.active() {
                r.phase = WakePhase::Cancelled;
            }
        }
        Ok(())
    })
    .await?;
    s.wake_runtime.agents.lock().unwrap().remove(id);
    Ok(Json(json!({"ok":true})))
}
async fn delete_agent(
    State(s): State<AppState>,
    Path(id): Path<String>,
    h: HeaderMap,
) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    revoke(&s, &u.user_id, &id).await
}
async fn stop_helper(
    s: &AppState,
    owner: &str,
    id: &str,
    expected_hash: Option<String>,
) -> WakeResult<Json<Value>> {
    update_wake(s, owner, |d| {
        let agent = d
            .agents
            .iter_mut()
            .find(|a| a.id == id)
            .ok_or(WakeError("not_found"))?;
        // Recheck under the storage lock: a late old stop must not disable a newly rotated token.
        if expected_hash
            .as_ref()
            .is_some_and(|hash| *hash != agent.token_hash || !agent.enabled)
        {
            return Err(WakeError("unauthorized"));
        }
        agent.enabled = false;
        agent.token_hash.clear();
        for r in &mut d.requests {
            if r.agent_id == id && r.phase.active() {
                r.phase = WakePhase::Cancelled;
            }
        }
        Ok(())
    })
    .await?;
    s.wake_runtime.agents.lock().unwrap().remove(id);
    Ok(Json(json!({"ok":true})))
}
async fn stop_agent(
    State(s): State<AppState>,
    Path(id): Path<String>,
    h: HeaderMap,
) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    stop_helper(&s, &u.user_id, &id, None).await
}
async fn disable_agent(
    State(s): State<AppState>,
    Path(id): Path<String>,
    h: HeaderMap,
) -> WakeResult<Json<Value>> {
    let owner = device_owner(&s, &h, &id, true)?;
    stop_helper(&s, &owner, &id, Some(digest(bearer(&h)?))).await
}
async fn enable_agent(
    State(s): State<AppState>,
    Path(id): Path<String>,
    h: HeaderMap,
    Json(b): Json<Named>,
) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    let name = name(&b.name)?;
    let (token, hash) = credential();
    update_wake(&s, &u.user_id, |d| {
        let a = d
            .agents
            .iter_mut()
            .find(|a| a.id == id)
            .ok_or(WakeError("not_found"))?;
        a.name = name;
        a.enabled = true;
        a.token_hash = hash;
        for r in &mut d.requests {
            if r.agent_id == id && r.phase.active() {
                r.phase = WakePhase::Cancelled;
            }
        }
        Ok(())
    })
    .await?;
    s.wake_runtime.agents.lock().unwrap().remove(&id);
    Ok(Json(json!({"id":id,"token":token})))
}
#[derive(Deserialize)]
struct RequestInput {
    target_id: String,
}
async fn create_request(
    State(s): State<AppState>,
    h: HeaderMap,
    Json(b): Json<RequestInput>,
) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    advance(&s, &u.user_id).await?;
    let r = update_wake(&s, &u.user_id, |d| {
        let t = d
            .targets
            .iter()
            .find(|t| t.id == b.target_id)
            .ok_or(WakeError("not_found"))?;
        if !t.setup_complete {
            return Err(WakeError("setup_incomplete"));
        }
        if let Some(r) = d
            .requests
            .iter()
            .find(|r| r.target_id == t.id && r.phase.active())
        {
            return Ok(r.clone());
        }
        let now = now_ms();
        if fresh(target_seen(&s, &t.id)) {
            return Err(WakeError("target_online"));
        }
        if !d.agents.iter().any(|a| a.id == t.agent_id && a.enabled)
            || !fresh(agent_seen(&s, &t.agent_id))
        {
            return Err(WakeError("agent_offline"));
        }
        if d.requests
            .iter()
            .filter(|r| now.saturating_sub(r.created_at_ms) < 60_000)
            .count()
            >= 10
            || d.requests
                .iter()
                .any(|r| r.target_id == t.id && now.saturating_sub(r.created_at_ms) < 30_000)
        {
            return Err(WakeError("rate_limited"));
        }
        let r = WakeRequest {
            id: new_token(),
            target_id: t.id.clone(),
            agent_id: t.agent_id.clone(),
            target_revision: t.revision,
            created_at_ms: now,
            expires_at_ms: now + 30_000,
            observe_until_ms: now + 120_000,
            phase: WakePhase::Queued,
            claimed_at_ms: None,
            authorized_at_ms: None,
            sent_at_ms: None,
            online_at_ms: None,
            error_code: None,
        };
        d.requests.push(r.clone());
        Ok(r)
    })
    .await?;
    Ok(Json(serde_json::to_value(r).unwrap()))
}
async fn request_status(
    State(s): State<AppState>,
    Path(id): Path<String>,
    h: HeaderMap,
) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    advance(&s, &u.user_id).await?;
    let u = s.users.get(&u.user_id).ok_or(WakeError("not_found"))?;
    let r = u
        .wake
        .requests
        .iter()
        .find(|r| r.id == id)
        .ok_or(WakeError("not_found"))?;
    Ok(Json(serde_json::to_value(r).unwrap()))
}
#[derive(Deserialize)]
struct HistoryQuery {
    target_id: String,
}
async fn history(
    State(s): State<AppState>,
    h: HeaderMap,
    Query(q): Query<HistoryQuery>,
) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    advance(&s, &u.user_id).await?;
    let u = s.users.get(&u.user_id).ok_or(WakeError("not_found"))?;
    if !u.wake.targets.iter().any(|t| t.id == q.target_id) {
        return Err(WakeError("not_found"));
    }
    Ok(Json(
        json!({"requests":u.wake.requests.iter().filter(|r|r.target_id==q.target_id).collect::<Vec<_>>(),"server_time_ms":now_ms()}),
    ))
}
async fn poll(
    State(s): State<AppState>,
    Path(id): Path<String>,
    h: HeaderMap,
) -> WakeResult<Response> {
    let owner = device_owner(&s, &h, &id, true)?;
    let started = Instant::now();
    s.wake_runtime
        .agents
        .lock()
        .unwrap()
        .insert(id.clone(), now_ms());
    loop {
        device_owner(&s, &h, &id, true)?;
        let has_job = s.users.get(&owner).is_some_and(|u| {
            u.wake.requests.iter().any(|r| {
                r.agent_id == id
                    && matches!(r.phase, WakePhase::Queued | WakePhase::Claimed)
                    && r.authorized_at_ms.is_none()
                    && r.expires_at_ms > now_ms()
            })
        });
        if has_job {
            let job=update_wake(&s,&owner,|d|{
                if !d.agents.iter().any(|a|a.id==id&&a.enabled){return Err(WakeError("unauthorized"));}
                let now=now_ms();let r=d.requests.iter_mut().find(|r|r.agent_id==id&&matches!(r.phase,WakePhase::Queued|WakePhase::Claimed)&&r.authorized_at_ms.is_none()&&r.expires_at_ms>now).ok_or(WakeError("conflict"))?;
                let t=d.targets.iter().find(|t|t.id==r.target_id&&t.agent_id==id&&t.revision==r.target_revision).ok_or(WakeError("conflict"))?;
                r.phase=WakePhase::Claimed;r.claimed_at_ms.get_or_insert(now);
                Ok(json!({"id":r.id,"target_id":r.target_id,"mac":t.mac,"revision":t.revision,"setup_complete":t.setup_complete,"remaining_ms":r.expires_at_ms-now,"server_time_ms":now}))
            }).await?;
            return Ok(Json(job).into_response());
        }
        if started.elapsed() >= Duration::from_secs(5) {
            return Ok(StatusCode::NO_CONTENT.into_response());
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}
fn owner_for_request(s: &AppState, h: &HeaderMap, id: &str) -> WakeResult<(String, String)> {
    let found = s
        .users
        .iter()
        .find_map(|u| {
            u.wake
                .requests
                .iter()
                .find(|r| r.id == id)
                .map(|r| (u.user_id.clone(), r.agent_id.clone()))
        })
        .ok_or(WakeError("unauthorized"))?;
    let owner = device_owner(s, h, &found.1, true)?;
    if owner != found.0 {
        return Err(WakeError("unauthorized"));
    }
    Ok(found)
}
async fn authorize(
    State(s): State<AppState>,
    Path(id): Path<String>,
    h: HeaderMap,
) -> WakeResult<Json<Value>> {
    let (owner, aid) = owner_for_request(&s, &h, &id)?;
    let remaining =
        update_wake(&s, &owner, |d| {
            if !d.agents.iter().any(|a| a.id == aid && a.enabled) {
                return Err(WakeError("unauthorized"));
            }
            let r = d
                .requests
                .iter_mut()
                .find(|r| r.id == id)
                .ok_or(WakeError("not_found"))?;
            let now = now_ms();
            if now >= r.expires_at_ms {
                return Err(WakeError("expired"));
            }
            if r.phase != WakePhase::Claimed || r.authorized_at_ms.is_some() {
                return Err(WakeError("conflict"));
            }
            if !d.targets.iter().any(|t| {
                t.id == r.target_id && t.agent_id == aid && t.revision == r.target_revision
            }) {
                return Err(WakeError("conflict"));
            }
            r.authorized_at_ms = Some(now);
            Ok((r.expires_at_ms - now).min(2000))
        })
        .await?;
    Ok(Json(
        json!({"remaining_ms":remaining,"server_time_ms":now_ms()}),
    ))
}
#[derive(Deserialize)]
struct ResultInput {
    phase: String,
    error_code: Option<String>,
}
async fn result(
    State(s): State<AppState>,
    Path(id): Path<String>,
    h: HeaderMap,
    Json(b): Json<ResultInput>,
) -> WakeResult<Json<Value>> {
    let (owner, aid) = owner_for_request(&s, &h, &id)?;
    if b.phase != "sent" && b.phase != "failed" {
        return Err(WakeError("invalid_phase"));
    }
    let error = b
        .error_code
        .filter(|e| e.len() <= 64 && e.bytes().all(|c| c.is_ascii_lowercase() || c == b'_'));
    let r = update_wake(&s, &owner, |d| {
        if !d.agents.iter().any(|a| a.id == aid && a.enabled) {
            return Err(WakeError("unauthorized"));
        }
        let r = d
            .requests
            .iter_mut()
            .find(|r| r.id == id)
            .ok_or(WakeError("not_found"))?;
        if matches!(
            r.phase,
            WakePhase::Sent | WakePhase::Online | WakePhase::Unconfirmed | WakePhase::Failed
        ) {
            return Ok(r.clone());
        }
        if r.phase != WakePhase::Claimed {
            return Err(WakeError("conflict"));
        }
        if r.authorized_at_ms.is_none() && b.phase == "sent" {
            return Err(WakeError("conflict"));
        }
        if now_ms() >= r.expires_at_ms {
            return Err(WakeError("expired"));
        }
        if b.phase == "sent" {
            r.phase = WakePhase::Sent;
            r.sent_at_ms = Some(now_ms());
            r.advance(now_ms(), target_seen(&s, &r.target_id));
        } else {
            r.phase = WakePhase::Failed;
            r.error_code = error;
        }
        Ok(r.clone())
    })
    .await?;
    Ok(Json(serde_json::to_value(r).unwrap()))
}
pub async fn cleanup(s: &AppState) {
    s.wake_runtime.pairings.lock().await.prune(now_ms());
    let now = now_ms();
    let mut agents = std::collections::HashSet::new();
    let mut targets = std::collections::HashSet::new();
    for user in s.users.iter() {
        agents.extend(user.wake.agents.iter().map(|a| a.id.clone()));
        targets.extend(user.wake.targets.iter().map(|t| t.id.clone()));
    }
    s.wake_runtime
        .agents
        .lock()
        .unwrap()
        .retain(|id, seen| agents.contains(id) && now.saturating_sub(*seen) < 604_800_000);
    s.wake_runtime
        .targets
        .lock()
        .unwrap()
        .retain(|id, seen| targets.contains(id) && now.saturating_sub(*seen) < 604_800_000);
    let owners: Vec<String> = s.users.iter().map(|u| u.user_id.clone()).collect();
    for owner in owners {
        if advance(s, &owner).await.is_err() {
            tracing::warn!("开机诊断清理暂时失败");
        }
    }
}
