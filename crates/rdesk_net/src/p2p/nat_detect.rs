//! NAT type detection.
//!
//! Determines the NAT type by sending STUN Binding Requests from the same
//! local port to multiple STUN servers and comparing the mapped (external)
//! addresses returned.
//!
//! Classification logic:
//! - If the mapped address (IP **and** port) is identical across all servers,
//!   the NAT is cone-type (Full Cone, Restricted Cone, or Port-Restricted Cone).
//! - If the mapped port differs between servers, the NAT is **Symmetric**.
//!
//! Distinguishing between Full Cone, Restricted Cone, and Port-Restricted Cone
//! requires additional tests (e.g. asking the server to reply from a different
//! port), which are not always supported. This implementation classifies the
//! cone sub-type as `FullCone` when ports are consistent, since the exact
//! sub-type is refined by the signaling server when needed.

use anyhow::{anyhow, Result};
use std::net::SocketAddr;
use tokio::net::UdpSocket;
use tracing::{debug, info, warn};

use crate::p2p::stun;

/// Describes the detected NAT type.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum NatType {
    /// Could not determine the NAT type.
    Unknown,
    /// Symmetric NAT -- mapped port changes per destination.
    Symmetric,
    /// Full Cone NAT -- any external host can reach the mapped address.
    FullCone,
    /// Restricted Cone NAT -- only hosts the client has contacted can reach it.
    RestrictedCone,
    /// Port-Restricted Cone -- like Restricted Cone but also filters on port.
    PortRestrictedCone,
}

impl std::fmt::Display for NatType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            NatType::Unknown => write!(f, "Unknown"),
            NatType::Symmetric => write!(f, "Symmetric"),
            NatType::FullCone => write!(f, "Full Cone"),
            NatType::RestrictedCone => write!(f, "Restricted Cone"),
            NatType::PortRestrictedCone => write!(f, "Port-Restricted Cone"),
        }
    }
}

impl From<NatType> for i32 {
    fn from(nt: NatType) -> i32 {
        match nt {
            NatType::Unknown => 0,
            NatType::Symmetric => 1,
            NatType::FullCone => 2,
            NatType::RestrictedCone => 3,
            NatType::PortRestrictedCone => 4,
        }
    }
}

impl From<i32> for NatType {
    fn from(v: i32) -> Self {
        match v {
            1 => NatType::Symmetric,
            2 => NatType::FullCone,
            3 => NatType::RestrictedCone,
            4 => NatType::PortRestrictedCone,
            _ => NatType::Unknown,
        }
    }
}

/// Minimum number of STUN servers required for NAT detection.
const MIN_STUN_SERVERS: usize = 2;

/// Detect the NAT type by querying multiple STUN servers from the same local
/// port and comparing the mapped addresses.
///
/// At least two STUN servers must be provided. If fewer are given, the function
/// returns [`NatType::Unknown`].
pub async fn detect_nat_type(stun_servers: &[&str]) -> Result<NatType> {
    if stun_servers.len() < MIN_STUN_SERVERS {
        warn!(
            count = stun_servers.len(),
            "not enough STUN servers for NAT detection, need at least {}", MIN_STUN_SERVERS
        );
        return Ok(NatType::Unknown);
    }

    // Bind a single UDP socket so all requests share the same local port.
    let socket = UdpSocket::bind("0.0.0.0:0")
        .await
        .map_err(|e| anyhow!("failed to bind UDP socket for NAT detection: {}", e))?;

    let local_addr = socket.local_addr()?;
    debug!(%local_addr, "NAT detection using local socket");

    let mut mapped_addrs: Vec<SocketAddr> = Vec::new();

    for server in stun_servers {
        match stun::discover_external_addr_with_socket(server, Some(&socket)).await {
            Ok(addr) => {
                debug!(%addr, server = %server, "STUN response received");
                mapped_addrs.push(addr);
            }
            Err(e) => {
                warn!(server = %server, %e, "STUN request failed, skipping server");
            }
        }
    }

    if mapped_addrs.len() < MIN_STUN_SERVERS {
        warn!(
            responses = mapped_addrs.len(),
            "not enough STUN responses for NAT detection"
        );
        return Ok(NatType::Unknown);
    }

    // Compare mapped addresses.
    let first = mapped_addrs[0];
    let all_same_ip = mapped_addrs.iter().all(|a| a.ip() == first.ip());
    let all_same_port = mapped_addrs.iter().all(|a| a.port() == first.port());

    let nat_type = if all_same_ip && all_same_port {
        // Mapped address is consistent -- this is some form of cone NAT.
        // Without additional server-side cooperation we cannot distinguish
        // Full Cone from Restricted/Port-Restricted, so default to FullCone.
        // The signaling server can refine this with TestNat messages.
        if first.ip() == local_addr.ip() {
            // Mapped IP matches local IP -- could be no NAT at all (direct),
            // which we treat as FullCone for hole-punching purposes.
            info!("external IP matches local IP, likely no NAT");
        }
        NatType::FullCone
    } else if all_same_ip && !all_same_port {
        // Same IP but different port per destination -- Port-Restricted Cone or Symmetric.
        // In practice, different ports across servers is the hallmark of Symmetric NAT.
        NatType::Symmetric
    } else {
        // Different IPs -- unusual, might be multi-homed or load-balanced STUN.
        // Treat as Symmetric to be conservative.
        NatType::Symmetric
    };

    info!(%nat_type, "NAT type detection complete");
    Ok(nat_type)
}
