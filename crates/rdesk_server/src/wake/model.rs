use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::json;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WakeError(pub &'static str);
impl IntoResponse for WakeError {
    fn into_response(self) -> Response {
        let (status, message) = match self.0 {
            "unauthorized" => (401, "开机凭据已失效，请重新配置"),
            "not_found" => (404, "开机配置不存在"),
            "agent_offline" => (409, "家中开机助手离线"),
            "target_online" => (409, "电脑已经在线"),
            "setup_incomplete" => (409, "请先完成家中助手和 BIOS 设置"),
            "conflict" => (409, "配置已变更或请求状态已变化"),
            "expired" => (410, "开机请求已过期"),
            "rate_limited" => (429, "操作过于频繁，请稍后再试"),
            "storage" => (503, "保存开机数据失败，请重试"),
            _ => (400, "开机配置参数不正确"),
        };
        (
            StatusCode::from_u16(status).unwrap(),
            Json(json!({"code":self.0,"message":message})),
        )
            .into_response()
    }
}
pub type WakeResult<T> = Result<T, WakeError>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MacAddress(pub [u8; 6]);
impl MacAddress {
    pub fn parse(raw: &str) -> WakeResult<Self> {
        let raw = raw.trim().replace('-', ":");
        let parts: Vec<_> = raw.split(':').collect();
        if parts.len() != 6 || parts.iter().any(|p| p.len() != 2) {
            return Err(WakeError("invalid_mac"));
        }
        let mut bytes = [0; 6];
        for (i, p) in parts.iter().enumerate() {
            bytes[i] = u8::from_str_radix(p, 16).map_err(|_| WakeError("invalid_mac"))?;
        }
        if bytes == [0; 6] || bytes[0] & 1 != 0 {
            return Err(WakeError("invalid_mac"));
        }
        Ok(Self(bytes))
    }
    pub fn normalized(&self) -> String {
        self.0
            .iter()
            .map(|b| format!("{b:02X}"))
            .collect::<Vec<_>>()
            .join(":")
    }
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WakeTarget {
    #[serde(default = "default_setup_complete")]
    pub setup_complete: bool,
    pub id: String,
    pub name: String,
    pub device_id: String,
    pub mac: String,
    pub agent_id: String,
    pub revision: u64,
    pub token_hash: String,
    pub created_at_ms: u64,
}
fn default_setup_complete() -> bool {
    true
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WakeAgent {
    pub id: String,
    pub name: String,
    pub token_hash: String,
    pub enabled: bool,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WakePhase {
    Queued,
    Claimed,
    Sent,
    Online,
    Unconfirmed,
    Expired,
    Failed,
    Cancelled,
    Interrupted,
}
impl WakePhase {
    pub fn active(self) -> bool {
        matches!(self, Self::Queued | Self::Claimed | Self::Sent)
    }
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WakeRequest {
    pub id: String,
    pub target_id: String,
    pub agent_id: String,
    pub target_revision: u64,
    pub created_at_ms: u64,
    pub expires_at_ms: u64,
    pub observe_until_ms: u64,
    pub phase: WakePhase,
    pub claimed_at_ms: Option<u64>,
    pub authorized_at_ms: Option<u64>,
    pub sent_at_ms: Option<u64>,
    pub online_at_ms: Option<u64>,
    pub error_code: Option<String>,
}
impl WakeRequest {
    pub fn advance(&mut self, now: u64, heartbeat: Option<u64>) {
        if self.phase == WakePhase::Sent {
            if observed_online(self.created_at_ms, self.sent_at_ms, heartbeat, now) {
                self.phase = WakePhase::Online;
                self.online_at_ms = heartbeat;
            } else if now >= self.observe_until_ms {
                self.phase = WakePhase::Unconfirmed;
            }
        } else if matches!(self.phase, WakePhase::Queued | WakePhase::Claimed)
            && now >= self.expires_at_ms
        {
            self.phase = WakePhase::Expired;
        }
    }
}
pub fn observed_online(created: u64, sent: Option<u64>, heartbeat: Option<u64>, now: u64) -> bool {
    sent.is_some()
        && heartbeat.is_some_and(|seen| seen > created && seen <= now && now - seen < 30_000)
}
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct WakeAccountData {
    pub targets: Vec<WakeTarget>,
    pub agents: Vec<WakeAgent>,
    pub requests: Vec<WakeRequest>,
}
impl WakeAccountData {
    pub fn prune(&mut self, now: u64) {
        self.requests
            .retain(|r| now.saturating_sub(r.created_at_ms) < 604_800_000);
        self.requests
            .sort_by_key(|r| std::cmp::Reverse(r.created_at_ms));
        self.requests.truncate(50);
    }
    pub fn recover_after_restart(&mut self, now: u64) {
        self.prune(now);
        for r in &mut self.requests {
            if r.phase.active() {
                r.phase = WakePhase::Interrupted;
                r.error_code = Some("server_restarted".into());
            }
        }
    }
    pub fn cancel_target(&mut self, id: &str) {
        for r in &mut self.requests {
            if r.target_id == id && r.phase.active() {
                r.phase = WakePhase::Cancelled;
            }
        }
    }
}
