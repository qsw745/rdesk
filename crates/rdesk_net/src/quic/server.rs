//! QUIC server endpoint.
//!
//! Creates a [`quinn::Endpoint`] that listens for incoming QUIC connections
//! using a self-signed certificate (identity is verified via the Noise
//! protocol layer, not TLS PKI).

use anyhow::{Context, Result};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use quinn::crypto::rustls::QuicServerConfig;
use rustls::pki_types::CertificateDer;
use tracing::{debug, info};

use crate::quic::stream::QuicConnection;

/// QUIC idle timeout.
const IDLE_TIMEOUT_MS: u32 = 30_000;

/// QUIC keep-alive interval.
const KEEP_ALIVE_INTERVAL: Duration = Duration::from_secs(10);

/// QUIC server wrapping a [`quinn::Endpoint`].
pub struct QuicServer {
    endpoint: quinn::Endpoint,
}

impl QuicServer {
    /// Create a new QUIC server endpoint bound to `bind_addr` with a
    /// self-signed certificate.
    pub fn new(bind_addr: SocketAddr) -> Result<Self> {
        // Generate a self-signed certificate for the server.
        let cert_key = rcgen::generate_simple_self_signed(vec!["rdesk-server".to_string()])
            .context("failed to generate self-signed certificate")?;

        let cert_der = CertificateDer::from(cert_key.cert);
        let key_der =
            rustls::pki_types::PrivatePkcs8KeyDer::from(cert_key.key_pair.serialize_der());

        // Build rustls server config.
        let mut rustls_config = rustls::ServerConfig::builder_with_provider(Arc::new(
            rustls::crypto::ring::default_provider(),
        ))
        .with_safe_default_protocol_versions()
        .context("failed to set protocol versions")?
        .with_no_client_auth()
        .with_single_cert(vec![cert_der], key_der.into())
        .context("failed to set server certificate")?;

        rustls_config.alpn_protocols = vec![b"rdesk".to_vec()];

        let quic_server_config = QuicServerConfig::try_from(rustls_config)
            .context("failed to create QuicServerConfig")?;

        let mut transport = quinn::TransportConfig::default();
        transport.max_idle_timeout(Some(
            quinn::IdleTimeout::try_from(Duration::from_millis(IDLE_TIMEOUT_MS as u64))
                .context("invalid idle timeout")?,
        ));
        transport.keep_alive_interval(Some(KEEP_ALIVE_INTERVAL));

        let mut server_config = quinn::ServerConfig::with_crypto(Arc::new(quic_server_config));
        server_config.transport_config(Arc::new(transport));

        let endpoint = quinn::Endpoint::server(server_config, bind_addr)
            .context("failed to create QUIC server endpoint")?;

        info!(%bind_addr, "QUIC server endpoint created");

        Ok(Self { endpoint })
    }

    /// Accept the next incoming QUIC connection.
    ///
    /// This method blocks until a new connection arrives or the endpoint is
    /// closed.
    pub async fn accept(&self) -> Result<QuicConnection> {
        debug!("waiting for incoming QUIC connection");

        let incoming = self
            .endpoint
            .accept()
            .await
            .ok_or_else(|| anyhow::anyhow!("QUIC endpoint closed"))?;

        let connection = incoming.await.context("failed to accept QUIC connection")?;

        info!(
            remote = %connection.remote_address(),
            "accepted QUIC connection"
        );

        Ok(QuicConnection::new(connection))
    }

    /// Return a reference to the underlying [`quinn::Endpoint`].
    pub fn endpoint(&self) -> &quinn::Endpoint {
        &self.endpoint
    }

    /// Return the local address the server is bound to.
    pub fn local_addr(&self) -> Result<SocketAddr> {
        self.endpoint
            .local_addr()
            .context("failed to get local address")
    }
}
