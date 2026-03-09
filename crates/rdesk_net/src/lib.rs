//! # rdesk_net
//!
//! Networking crate for rdesk remote desktop software.
//!
//! Provides P2P connectivity (STUN, NAT detection, UDP hole punching),
//! QUIC transport (client, server, multiplexed streams), relay client,
//! and rendezvous (signaling) protocol support.

pub mod p2p;
pub mod quic;
pub mod relay;
pub mod rendezvous;

// Re-exports for downstream convenience.
pub use p2p::{hole_punch, nat_detect, stun};
pub use quic::{client::QuicClient, server::QuicServer, stream::QuicConnection};
pub use relay::client::RelayClient;
pub use rendezvous::client::RendezvousClient;
