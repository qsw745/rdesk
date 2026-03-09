//! UDP hole punching.
//!
//! Establishes a direct UDP path between two peers behind NAT by sending
//! periodic probes to the peer's expected external address while simultaneously
//! listening for incoming probes from the peer.

use anyhow::{anyhow, Context, Result};
use std::net::SocketAddr;
use tokio::net::UdpSocket;
use tokio::time::{interval, timeout, Duration, Instant};
use tracing::{debug, info, trace, warn};

/// Magic bytes prepended to hole-punch probes so we can distinguish them
/// from other UDP traffic.
const PUNCH_MAGIC: &[u8; 4] = b"RDPN";

/// Interval between outgoing probe packets.
const PROBE_INTERVAL: Duration = Duration::from_millis(200);

/// Maximum size of a probe packet.
const PROBE_MAX_SIZE: usize = 64;

/// Attempt to punch a UDP hole to `peer_addr` from a socket bound to
/// `local_port`.
///
/// The function simultaneously:
/// 1. Sends periodic UDP probes to `peer_addr`.
/// 2. Listens for incoming probes from the peer.
///
/// When a valid probe is received from the peer, the socket is "connected" to
/// the peer address and returned. If no probe is received within `timeout_dur`,
/// an error is returned.
///
/// Both sides must call this function concurrently for hole punching to succeed.
pub async fn punch_hole(
    local_port: u16,
    peer_addr: SocketAddr,
    timeout_dur: Duration,
) -> Result<UdpSocket> {
    let bind_addr: SocketAddr = if peer_addr.is_ipv4() {
        format!("0.0.0.0:{}", local_port).parse().unwrap()
    } else {
        format!("[::]:{}", local_port).parse().unwrap()
    };

    let socket = UdpSocket::bind(bind_addr)
        .await
        .with_context(|| format!("failed to bind UDP socket on port {}", local_port))?;

    let local_addr = socket.local_addr()?;
    info!(%local_addr, %peer_addr, "starting UDP hole punch");

    let deadline = Instant::now() + timeout_dur;
    let mut probe_ticker = interval(PROBE_INTERVAL);

    // Build the probe payload.
    let probe = build_probe(local_addr.port());

    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            return Err(anyhow!(
                "hole punch timed out after {:?} (peer: {})",
                timeout_dur,
                peer_addr
            ));
        }

        tokio::select! {
            // Send a probe at each tick.
            _ = probe_ticker.tick() => {
                trace!(%peer_addr, "sending hole-punch probe");
                if let Err(e) = socket.send_to(&probe, peer_addr).await {
                    warn!(%peer_addr, %e, "failed to send probe");
                }
            }
            // Listen for incoming data.
            result = async {
                let mut buf = [0u8; PROBE_MAX_SIZE];
                timeout(remaining, socket.recv_from(&mut buf))
                    .await
                    .map(|result| result.map(|(n, src)| (buf, n, src)))
            } => {
                match result {
                    Ok(Ok((buf, n, src))) => {
                        if is_valid_probe(&buf[..n]) {
                            info!(%src, "received valid hole-punch probe, connection established");
                            // Send a few more probes to ensure the peer also
                            // receives at least one.
                            for _ in 0..3 {
                                let _ = socket.send_to(&probe, peer_addr).await;
                            }
                            // "Connect" the socket to the peer so subsequent
                            // send/recv calls target the peer directly.
                            socket.connect(peer_addr).await.context(
                                "failed to connect UDP socket to peer",
                            )?;
                            return Ok(socket);
                        } else {
                            debug!(%src, bytes = n, "received non-probe UDP packet, ignoring");
                        }
                    }
                    Ok(Err(e)) => {
                        debug!(%e, "recv_from error during hole punch");
                    }
                    Err(_) => {
                        // Timeout expired.
                        return Err(anyhow!(
                            "hole punch timed out after {:?} (peer: {})",
                            timeout_dur,
                            peer_addr
                        ));
                    }
                }
            }
        }
    }
}

/// Build a probe packet: magic bytes followed by the sender's local port
/// (big-endian).
fn build_probe(local_port: u16) -> Vec<u8> {
    let mut pkt = Vec::with_capacity(PUNCH_MAGIC.len() + 2);
    pkt.extend_from_slice(PUNCH_MAGIC);
    pkt.extend_from_slice(&local_port.to_be_bytes());
    pkt
}

/// Check whether a received packet is a valid hole-punch probe.
fn is_valid_probe(data: &[u8]) -> bool {
    data.len() >= PUNCH_MAGIC.len() && data[..PUNCH_MAGIC.len()] == PUNCH_MAGIC[..]
}
