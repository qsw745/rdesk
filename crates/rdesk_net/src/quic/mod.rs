//! QUIC transport layer.
//!
//! Provides client and server QUIC endpoints built on [`quinn`]. The client
//! verifies the server certificate with real TLS PKI by default; see
//! [`client::ServerVerification`] for the self-hosted and (opt-in) permissive
//! alternatives. Also provides multiplexed stream management for control,
//! video, file transfer, and chat channels.

pub mod client;
pub mod server;
pub mod stream;

pub use client::{QuicClient, ServerVerification};
pub use server::{CertificateDer, QuicServer, ServerCertificate};
pub use stream::QuicConnection;
