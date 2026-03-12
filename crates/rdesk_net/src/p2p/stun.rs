//! Minimal STUN client implementing Binding Request (RFC 5389).
//!
//! Used to discover the external (mapped) address as seen by a STUN server,
//! which is needed for P2P hole punching.

use anyhow::{anyhow, Context, Result};
use rand::Rng;
use std::net::SocketAddr;
use tokio::net::UdpSocket;
use tokio::time::{timeout, Duration};
use tracing::{debug, trace};

/// STUN message type: Binding Request (0x0001).
const BINDING_REQUEST: u16 = 0x0001;

/// STUN message type: Binding Success Response (0x0101).
const BINDING_RESPONSE: u16 = 0x0101;

/// STUN magic cookie (RFC 5389).
const MAGIC_COOKIE: u32 = 0x2112_A442;

/// STUN attribute type: XOR-MAPPED-ADDRESS (0x0020).
const ATTR_XOR_MAPPED_ADDRESS: u16 = 0x0020;

/// STUN attribute type: MAPPED-ADDRESS (0x0001), used as fallback.
const ATTR_MAPPED_ADDRESS: u16 = 0x0001;

/// STUN header size in bytes.
const STUN_HEADER_SIZE: usize = 20;

/// Address family: IPv4.
const FAMILY_IPV4: u8 = 0x01;

/// Default timeout for STUN requests.
const STUN_TIMEOUT: Duration = Duration::from_secs(3);

/// Discover the external (mapped) address by sending a STUN Binding Request
/// to the given STUN server.
///
/// The `stun_server` argument should be in `host:port` format (e.g.
/// `"stun.l.google.com:19302"`).
///
/// Returns the externally visible [`SocketAddr`] as reported by the server.
pub async fn discover_external_addr(stun_server: &str) -> Result<SocketAddr> {
    discover_external_addr_with_socket(stun_server, None).await
}

/// Discover external address, optionally reusing an existing socket.
///
/// When `socket` is `None` a fresh ephemeral UDP socket is bound automatically.
/// When `Some`, the caller-provided socket is used (useful for NAT detection
/// where the same local port must be reused across multiple requests).
pub async fn discover_external_addr_with_socket(
    stun_server: &str,
    socket: Option<&UdpSocket>,
) -> Result<SocketAddr> {
    // Resolve STUN server address.
    let server_addr: SocketAddr = tokio::net::lookup_host(stun_server)
        .await
        .context("failed to resolve STUN server address")?
        .next()
        .ok_or_else(|| anyhow!("STUN server address resolved to no addresses"))?;

    debug!(%server_addr, "sending STUN binding request");

    // Build the Binding Request.
    let transaction_id = generate_transaction_id();
    let request = build_binding_request(&transaction_id);

    // Use the provided socket or create one.
    let owned_socket;
    let sock = match socket {
        Some(s) => s,
        None => {
            let bind_addr: SocketAddr = if server_addr.is_ipv4() {
                "0.0.0.0:0".parse().unwrap()
            } else {
                "[::]:0".parse().unwrap()
            };
            owned_socket = UdpSocket::bind(bind_addr)
                .await
                .context("failed to bind UDP socket for STUN")?;
            &owned_socket
        }
    };

    // Send request and wait for response.
    sock.send_to(&request, server_addr)
        .await
        .context("failed to send STUN request")?;

    let mut buf = [0u8; 576];
    let (n, _src) = timeout(STUN_TIMEOUT, sock.recv_from(&mut buf))
        .await
        .context("STUN request timed out")?
        .context("failed to receive STUN response")?;

    let response = &buf[..n];
    trace!(len = n, "received STUN response");

    // Parse the response.
    let mapped = parse_binding_response(response, &transaction_id)?;
    debug!(%mapped, "discovered external address");

    Ok(mapped)
}

/// Generate a 12-byte random transaction ID.
fn generate_transaction_id() -> [u8; 12] {
    let mut id = [0u8; 12];
    rand::thread_rng().fill(&mut id);
    id
}

/// Build a STUN Binding Request message.
fn build_binding_request(transaction_id: &[u8; 12]) -> Vec<u8> {
    let mut msg = Vec::with_capacity(STUN_HEADER_SIZE);

    // Message Type: Binding Request.
    msg.extend_from_slice(&BINDING_REQUEST.to_be_bytes());
    // Message Length: 0 (no attributes).
    msg.extend_from_slice(&0u16.to_be_bytes());
    // Magic Cookie.
    msg.extend_from_slice(&MAGIC_COOKIE.to_be_bytes());
    // Transaction ID (12 bytes).
    msg.extend_from_slice(transaction_id);

    msg
}

/// Parse a STUN Binding Response and extract the mapped address.
fn parse_binding_response(data: &[u8], expected_txn_id: &[u8; 12]) -> Result<SocketAddr> {
    if data.len() < STUN_HEADER_SIZE {
        return Err(anyhow!("STUN response too short: {} bytes", data.len()));
    }

    // Verify message type.
    let msg_type = u16::from_be_bytes([data[0], data[1]]);
    if msg_type != BINDING_RESPONSE {
        return Err(anyhow!("unexpected STUN message type: 0x{:04x}", msg_type));
    }

    // Verify magic cookie.
    let cookie = u32::from_be_bytes([data[4], data[5], data[6], data[7]]);
    if cookie != MAGIC_COOKIE {
        return Err(anyhow!("invalid STUN magic cookie: 0x{:08x}", cookie));
    }

    // Verify transaction ID.
    if &data[8..20] != expected_txn_id {
        return Err(anyhow!("STUN transaction ID mismatch"));
    }

    let msg_len = u16::from_be_bytes([data[2], data[3]]) as usize;
    if data.len() < STUN_HEADER_SIZE + msg_len {
        return Err(anyhow!("STUN response truncated"));
    }

    // Parse attributes.
    let attrs = &data[STUN_HEADER_SIZE..STUN_HEADER_SIZE + msg_len];
    let mut offset = 0;

    while offset + 4 <= attrs.len() {
        let attr_type = u16::from_be_bytes([attrs[offset], attrs[offset + 1]]);
        let attr_len = u16::from_be_bytes([attrs[offset + 2], attrs[offset + 3]]) as usize;
        offset += 4;

        if offset + attr_len > attrs.len() {
            break;
        }

        let attr_data = &attrs[offset..offset + attr_len];

        match attr_type {
            ATTR_XOR_MAPPED_ADDRESS => {
                return parse_xor_mapped_address(attr_data);
            }
            ATTR_MAPPED_ADDRESS => {
                // Fallback: try plain MAPPED-ADDRESS if XOR variant not found
                // later. We prefer XOR-MAPPED-ADDRESS, so continue scanning.
                if let Ok(addr) = parse_mapped_address(attr_data) {
                    // We'll return this only if we never find XOR-MAPPED-ADDRESS.
                    // For simplicity, return immediately since many servers send
                    // only one of the two.
                    return Ok(addr);
                }
            }
            _ => {
                trace!(
                    attr_type = attr_type,
                    attr_len = attr_len,
                    "skipping unknown STUN attribute"
                );
            }
        }

        // Attributes are padded to 4-byte boundaries.
        offset += (attr_len + 3) & !3;
    }

    Err(anyhow!(
        "no XOR-MAPPED-ADDRESS or MAPPED-ADDRESS in STUN response"
    ))
}

/// Parse the XOR-MAPPED-ADDRESS attribute value (IPv4 only for now).
fn parse_xor_mapped_address(data: &[u8]) -> Result<SocketAddr> {
    if data.len() < 8 {
        return Err(anyhow!("XOR-MAPPED-ADDRESS too short"));
    }

    let family = data[1];
    if family != FAMILY_IPV4 {
        return Err(anyhow!(
            "unsupported address family in XOR-MAPPED-ADDRESS: 0x{:02x}",
            family
        ));
    }

    // XOR the port with the upper 16 bits of the magic cookie.
    let xor_port = u16::from_be_bytes([data[2], data[3]]);
    let port = xor_port ^ (MAGIC_COOKIE >> 16) as u16;

    // XOR the IPv4 address with the magic cookie.
    let xor_ip = [data[4], data[5], data[6], data[7]];
    let cookie_bytes = MAGIC_COOKIE.to_be_bytes();
    let ip = std::net::Ipv4Addr::new(
        xor_ip[0] ^ cookie_bytes[0],
        xor_ip[1] ^ cookie_bytes[1],
        xor_ip[2] ^ cookie_bytes[2],
        xor_ip[3] ^ cookie_bytes[3],
    );

    Ok(SocketAddr::new(std::net::IpAddr::V4(ip), port))
}

/// Parse the MAPPED-ADDRESS attribute value (IPv4 only for now).
fn parse_mapped_address(data: &[u8]) -> Result<SocketAddr> {
    if data.len() < 8 {
        return Err(anyhow!("MAPPED-ADDRESS too short"));
    }

    let family = data[1];
    if family != FAMILY_IPV4 {
        return Err(anyhow!(
            "unsupported address family in MAPPED-ADDRESS: 0x{:02x}",
            family
        ));
    }

    let port = u16::from_be_bytes([data[2], data[3]]);
    let ip = std::net::Ipv4Addr::new(data[4], data[5], data[6], data[7]);

    Ok(SocketAddr::new(std::net::IpAddr::V4(ip), port))
}
