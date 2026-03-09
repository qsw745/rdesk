//! QUIC transport layer.
//!
//! Provides client and server QUIC endpoints built on [`quinn`] with
//! self-signed certificates (identity is verified via the Noise protocol
//! layer, not TLS PKI). Also provides multiplexed stream management for
//! control, video, file transfer, and chat channels.

pub mod client;
pub mod server;
pub mod stream;

pub use client::QuicClient;
pub use server::QuicServer;
pub use stream::QuicConnection;
