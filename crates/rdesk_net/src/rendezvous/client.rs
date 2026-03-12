//! Signaling client placeholder.

use anyhow::Result;
use tracing::info;

use rdesk_common::protos::rendezvous::{
    FetchPeerResponse, PunchHoleResponse, RegisterPeerResponse,
};

/// Minimal rendezvous client that keeps the API surface stable while the real
/// signaling transport is implemented.
#[derive(Debug, Clone)]
pub struct RendezvousClient {
    server_addr: String,
}

impl RendezvousClient {
    pub async fn new(server_addr: &str) -> Result<Self> {
        info!(server_addr = %server_addr, "connecting to rendezvous server (stub)");
        Ok(Self {
            server_addr: server_addr.to_string(),
        })
    }

    pub fn server_addr(&self) -> &str {
        &self.server_addr
    }

    pub async fn fetch_peer(&mut self, device_id: &str) -> Result<FetchPeerResponse> {
        let found = rdesk_common::device_id::validate_device_id(device_id);
        Ok(FetchPeerResponse {
            found,
            pk: Vec::new(),
            nat_type: 0,
            online: found,
        })
    }

    pub async fn punch_hole(
        &mut self,
        _device_id: &str,
        _token: &str,
    ) -> Result<PunchHoleResponse> {
        Ok(PunchHoleResponse {
            socket_addr: Vec::new(),
            nat_type: 0,
            pk: Vec::new(),
            failure: 0,
        })
    }

    pub async fn register_peer(&mut self, _device_id: &str) -> Result<RegisterPeerResponse> {
        Ok(RegisterPeerResponse {
            success: true,
            error: String::new(),
        })
    }
}
