//! Account-bound short-lived enrollment. No permanent credential crosses the phone.
use super::{
    model::*,
    routes::{account, bearer, digest, name},
    store::update_wake,
};
use crate::{now_ms, AppState, AUTH_SESSION_TTL_MS};
use axum::{
    extract::{DefaultBodyLimit, Path, State},
    http::HeaderMap,
    routing::post,
    Json, Router,
};
use rand::{rngs::OsRng, RngCore};
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::HashMap;

const TTL: u64 = 300_000;
const ALPHABET: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
#[derive(Default)]
pub struct PairingRuntime {
    pub(super) sessions: HashMap<String, Pairing>,
    limits: HashMap<String, Limit>,
}
#[derive(Default)]
struct Limit {
    since: u64,
    creates: u8,
    failures: u8,
}
#[derive(Clone)]
pub(super) struct Pairing {
    owner: String,
    creator: String,
    name: String,
    device_id: String,
    mac: String,
    qr_hash: String,
    desktop_hash: String,
    manual_hash: String,
    pub(super) expires: u64,
    confirmed: bool,
    cancelled: bool,
    claimed: Option<(String, String)>,
}
impl PairingRuntime {
    pub fn prune(&mut self, now: u64) {
        self.sessions.retain(|_, p| now < p.expires);
        self.limits.retain(|_, l| now.saturating_sub(l.since) < TTL);
    }
    fn limit(&mut self, owner: &str, now: u64) -> WakeResult<&mut Limit> {
        self.limits.retain(|_, l| now.saturating_sub(l.since) < TTL);
        if !self.limits.contains_key(owner) && self.limits.len() >= 2000 {
            return Err(WakeError("rate_limited"));
        }
        Ok(self.limits.entry(owner.into()).or_insert(Limit {
            since: now,
            ..Default::default()
        }))
    }
}
impl Pairing {
    fn valid(&self, s: &AppState, owner: &str) -> WakeResult<()> {
        if self.owner != owner {
            return Err(WakeError("not_found"));
        }
        if now_ms() >= self.expires {
            return Err(WakeError("expired"));
        }
        if self.cancelled || !creator_valid(s, self) {
            return Err(WakeError("conflict"));
        }
        Ok(())
    }
    fn phase(&self) -> &'static str {
        if now_ms() >= self.expires {
            "expired"
        } else if self.claimed.is_some() {
            "claimed"
        } else if self.confirmed {
            "confirmed"
        } else {
            "pending"
        }
    }
}
fn creator_valid(s: &AppState, p: &Pairing) -> bool {
    s.users.contains_key(&p.owner)
        && s.auth_sessions.iter().any(|a| {
            a.user_id == p.owner
                && now_ms().saturating_sub(a.last_seen_ms) <= AUTH_SESSION_TTL_MS
                && equal(&digest(a.key()), &p.creator)
        })
}
fn equal(a: &str, b: &str) -> bool {
    a.len() == b.len()
        && a.as_bytes()
            .iter()
            .zip(b.as_bytes())
            .fold(0u8, |n, (a, b)| n | (a ^ b))
            == 0
}
fn random(bytes: usize) -> WakeResult<Vec<u8>> {
    let mut data = vec![0; bytes];
    OsRng
        .try_fill_bytes(&mut data)
        .map_err(|_| WakeError("storage"))?;
    Ok(data)
}
fn proof() -> WakeResult<String> {
    Ok(random(32)?.iter().map(|b| format!("{b:02x}")).collect())
}
fn valid_proof(p: &str) -> bool {
    p.len() == 64 && p.bytes().all(|b| b.is_ascii_hexdigit())
}
fn manual(raw: &str) -> Option<String> {
    let code = raw.to_ascii_uppercase();
    (code.len() == 16 && code.bytes().all(|b| ALPHABET.contains(&b))).then_some(code)
}
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/api/wake/pairings", post(create))
        .route("/api/wake/pairings/resolve", post(resolve))
        .route("/api/wake/pairings/cancel-all", post(cancel_all))
        .route("/api/wake/pairings/:id/confirm", post(confirm))
        .route("/api/wake/pairings/:id/status", post(status))
        .route("/api/wake/pairings/:id/claim", post(claim))
        .route("/api/wake/pairings/:id/cancel", post(cancel))
        .route("/api/wake/targets/:id/complete", post(complete))
        .layer(DefaultBodyLimit::max(16 * 1024))
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Create {
    name: String,
    device_id: String,
    mac: String,
}
async fn create(
    State(s): State<AppState>,
    h: HeaderMap,
    Json(b): Json<Create>,
) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    let name = name(&b.name)?;
    if b.device_id.trim().is_empty() || b.device_id.len() > 128 {
        return Err(WakeError("invalid_device"));
    }
    let mac = MacAddress::parse(&b.mac)?.normalized();
    let mut rt = s.wake_runtime.pairings.lock().await;
    let now = now_ms();
    rt.prune(now);
    if rt.limit(&u.user_id, now)?.creates >= 6
        || rt.sessions.len() >= 1000
        || rt
            .sessions
            .values()
            .filter(|p| p.owner == u.user_id && p.claimed.is_none() && !p.cancelled)
            .count()
            >= 3
    {
        return Err(WakeError("rate_limited"));
    }
    let id: String = random(16)?.iter().map(|b| format!("{b:02x}")).collect();
    let qr = proof()?;
    let desktop = proof()?;
    let manual: String = random(16)?
        .iter()
        .map(|b| ALPHABET[(b & 31) as usize] as char)
        .collect();
    let p = Pairing {
        owner: u.user_id.clone(),
        creator: digest(bearer(&h)?),
        name,
        device_id: b.device_id,
        mac,
        qr_hash: digest(&qr),
        desktop_hash: digest(&desktop),
        manual_hash: digest(&manual),
        expires: now + TTL,
        confirmed: false,
        cancelled: false,
        claimed: None,
    };
    // Recheck after acquiring the pairing lock, including logout/deletion races.
    p.valid(&s, &u.user_id)?;
    rt.limit(&u.user_id, now)?.creates += 1;
    rt.sessions.insert(id.clone(), p);
    Ok(Json(
        json!({"id":id,"qr_proof":qr,"desktop_proof":desktop,"manual_code":manual,"expires_at_ms":now+TTL}),
    ))
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct PhoneProof {
    id: Option<String>,
    qr_proof: Option<String>,
    manual_code: Option<String>,
}
fn phone_matches(p: &Pairing, b: &PhoneProof) -> bool {
    match (&b.qr_proof, &b.manual_code) {
        (Some(qr), None) => valid_proof(qr) && equal(&digest(qr), &p.qr_hash),
        (None, Some(code)) => manual(code).is_some_and(|c| equal(&digest(&c), &p.manual_hash)),
        _ => false,
    }
}
fn phone_session(
    rt: &mut PairingRuntime,
    s: &AppState,
    owner: &str,
    id: Option<&str>,
    b: &PhoneProof,
) -> WakeResult<(String, Pairing)> {
    if rt.limit(owner, now_ms())?.failures >= 20 {
        return Err(WakeError("rate_limited"));
    }
    let found = if let Some(id) = id {
        rt.sessions
            .get(id)
            .filter(|p| p.owner == owner && phone_matches(p, b))
            .map(|p| (id.to_string(), p.clone()))
    } else if b.id.is_none() && b.qr_proof.is_none() {
        rt.sessions
            .iter()
            .find(|(_, p)| p.owner == owner && phone_matches(p, b))
            .map(|(id, p)| (id.clone(), p.clone()))
    } else {
        None
    };
    let result = found.ok_or(WakeError("not_found")).and_then(|(id, p)| {
        p.valid(s, owner)?;
        Ok((id, p))
    });
    if result.is_err() {
        rt.limit(owner, now_ms())?.failures += 1;
    }
    result
}
fn summary(id: &str, p: &Pairing) -> Value {
    json!({"id":id,"name":p.name,"device_id":p.device_id,"state":p.phase(),"expires_at_ms":p.expires,"target_id":p.claimed.as_ref().map(|c|&c.0)})
}
async fn resolve(
    State(s): State<AppState>,
    h: HeaderMap,
    Json(b): Json<PhoneProof>,
) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    // QR requires exactly id+proof; manual code never accepts an id.
    let shape = (b.id.is_some() && b.qr_proof.is_some() && b.manual_code.is_none())
        || (b.id.is_none() && b.qr_proof.is_none() && b.manual_code.is_some());
    let mut rt = s.wake_runtime.pairings.lock().await;
    if !shape {
        return Err(WakeError("invalid_proof"));
    }
    let (id, p) = phone_session(&mut rt, &s, &u.user_id, b.id.as_deref(), &b)?;
    Ok(Json(summary(&id, &p)))
}
async fn confirm(
    State(s): State<AppState>,
    Path(id): Path<String>,
    h: HeaderMap,
    Json(b): Json<PhoneProof>,
) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    if b.id.is_some() {
        return Err(WakeError("invalid_proof"));
    }
    let mut rt = s.wake_runtime.pairings.lock().await;
    let (_, p) = phone_session(&mut rt, &s, &u.user_id, Some(&id), &b)?;
    if p.confirmed || p.claimed.is_some() {
        return Err(WakeError("conflict"));
    }
    let p = rt.sessions.get_mut(&id).unwrap();
    p.confirmed = true;
    Ok(Json(summary(&id, p)))
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct DesktopProof {
    desktop_proof: String,
}
fn desktop_session(
    rt: &PairingRuntime,
    s: &AppState,
    owner: &str,
    id: &str,
    proof: &str,
) -> WakeResult<Pairing> {
    let p = rt
        .sessions
        .get(id)
        .filter(|p| {
            p.owner == owner && valid_proof(proof) && equal(&digest(proof), &p.desktop_hash)
        })
        .ok_or(WakeError("not_found"))?;
    p.valid(s, owner)?;
    Ok(p.clone())
}
async fn status(
    State(s): State<AppState>,
    Path(id): Path<String>,
    h: HeaderMap,
    Json(b): Json<DesktopProof>,
) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    let rt = s.wake_runtime.pairings.lock().await;
    let p = desktop_session(&rt, &s, &u.user_id, &id, &b.desktop_proof)?;
    Ok(Json(summary(&id, &p)))
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Claim {
    desktop_proof: String,
    enrollment_token: String,
}
async fn claim(
    State(s): State<AppState>,
    Path(id): Path<String>,
    h: HeaderMap,
    Json(b): Json<Claim>,
) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    if !valid_proof(&b.enrollment_token) {
        return Err(WakeError("invalid_token"));
    }
    let mut rt = s.wake_runtime.pairings.lock().await;
    let p = desktop_session(&rt, &s, &u.user_id, &id, &b.desktop_proof)?;
    if !p.confirmed {
        return Err(WakeError("conflict"));
    }
    let hash = digest(&b.enrollment_token);
    let target_id = if let Some((id, old_hash)) = &p.claimed {
        if !equal(old_hash, &hash) {
            return Err(WakeError("conflict"));
        }
        let user = s.users.get(&u.user_id).ok_or(WakeError("not_found"))?;
        if !user
            .wake
            .targets
            .iter()
            .any(|t| t.id == *id && equal(&t.token_hash, &hash))
        {
            return Err(WakeError("conflict"));
        }
        id.clone()
    } else {
        let target_id = crate::new_token();
        update_wake(&s, &u.user_id, |d| {
            p.valid(&s, &u.user_id)?;
            account(&s, &h)?;
            if d.targets.len() >= 20 {
                return Err(WakeError("rate_limited"));
            }
            if d.targets.iter().any(|t| t.device_id == p.device_id) {
                return Err(WakeError("conflict"));
            }
            d.targets.push(WakeTarget {
                id: target_id.clone(),
                name: p.name.clone(),
                device_id: p.device_id.clone(),
                mac: p.mac.clone(),
                agent_id: String::new(),
                revision: 1,
                token_hash: hash.clone(),
                created_at_ms: now_ms(),
                setup_complete: false,
            });
            Ok(())
        })
        .await?;
        rt.sessions.get_mut(&id).unwrap().claimed = Some((target_id.clone(), hash));
        target_id
    };
    Ok(Json(json!({"target_id":target_id})))
}
async fn cancel(
    State(s): State<AppState>,
    Path(id): Path<String>,
    h: HeaderMap,
    Json(b): Json<DesktopProof>,
) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    let mut rt = s.wake_runtime.pairings.lock().await;
    let p = desktop_session(&rt, &s, &u.user_id, &id, &b.desktop_proof)?;
    if p.claimed.is_some() {
        return Err(WakeError("conflict"));
    }
    rt.sessions.get_mut(&id).unwrap().cancelled = true;
    Ok(Json(json!({"ok":true})))
}
async fn cancel_all(State(s): State<AppState>, h: HeaderMap) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    let creator = digest(bearer(&h)?);
    let mut rt = s.wake_runtime.pairings.lock().await;
    for p in rt
        .sessions
        .values_mut()
        .filter(|p| p.owner == u.user_id && equal(&p.creator, &creator) && p.claimed.is_none())
    {
        p.cancelled = true;
    }
    Ok(Json(json!({"ok":true})))
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Complete {
    agent_id: String,
    bios_confirmed: bool,
}
async fn complete(
    State(s): State<AppState>,
    Path(id): Path<String>,
    h: HeaderMap,
    Json(b): Json<Complete>,
) -> WakeResult<Json<Value>> {
    let u = account(&s, &h)?;
    if !b.bios_confirmed {
        return Err(WakeError("setup_incomplete"));
    }
    update_wake(&s, &u.user_id, |d| {
        account(&s, &h)?;
        if !d.agents.iter().any(|a| a.id == b.agent_id && a.enabled) {
            return Err(WakeError("not_found"));
        }
        let t = d
            .targets
            .iter_mut()
            .find(|t| t.id == id)
            .ok_or(WakeError("not_found"))?;
        t.agent_id = b.agent_id;
        t.setup_complete = true;
        t.revision += 1;
        d.cancel_target(&id);
        Ok(())
    })
    .await?;
    Ok(Json(json!({"id":id,"setup_complete":true})))
}
