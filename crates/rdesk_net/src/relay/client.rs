//! Relay client placeholder.

use anyhow::Result;
use tracing::info;

/// Minimal relay client used while the real relay transport is under
/// construction.
#[derive(Debug, Clone)]
pub struct RelayClient {
    server_addr: String,
}

impl RelayClient {
    pub async fn connect(server_addr: &str) -> Result<Self> {
        info!(server_addr = %server_addr, "connecting to relay server (stub)");
        Ok(Self {
            server_addr: server_addr.to_string(),
        })
    }

    pub fn server_addr(&self) -> &str {
        &self.server_addr
    }
}
