//! QUIC client endpoint.
//!
//! Creates a [`quinn::Endpoint`] configured with a self-signed certificate and
//! a permissive server certificate verifier (identity is verified via the Noise
//! protocol layer, not TLS PKI).

use anyhow::{Context, Result};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use quinn::crypto::rustls::QuicClientConfig;
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::SignatureScheme;
use tracing::{debug, info};

use crate::quic::stream::QuicConnection;

/// QUIC idle timeout.
const IDLE_TIMEOUT_MS: u32 = 30_000;

/// QUIC keep-alive interval.
const KEEP_ALIVE_INTERVAL: Duration = Duration::from_secs(10);

/// QUIC client wrapping a [`quinn::Endpoint`].
pub struct QuicClient {
    endpoint: quinn::Endpoint,
}

impl QuicClient {
    /// Create a new QUIC client endpoint with a self-signed certificate.
    ///
    /// The client uses a permissive certificate verifier that accepts any
    /// server certificate, since peer identity is verified through the Noise
    /// protocol handshake rather than TLS PKI.
    pub fn new() -> Result<Self> {
        // Generate a self-signed certificate for the client identity.
        let cert_key = rcgen::generate_simple_self_signed(vec!["rdesk-client".to_string()])
            .context("failed to generate self-signed certificate")?;

        let cert_der = CertificateDer::from(cert_key.cert);
        let key_der = rustls::pki_types::PrivatePkcs8KeyDer::from(cert_key.key_pair.serialize_der());

        // Build rustls client config that accepts any server certificate.
        let mut rustls_config = rustls::ClientConfig::builder_with_provider(Arc::new(
            rustls::crypto::ring::default_provider(),
        ))
        .with_safe_default_protocol_versions()
        .context("failed to set protocol versions")?
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(SkipServerVerification))
        .with_client_auth_cert(vec![cert_der], key_der.into())
        .context("failed to set client auth certificate")?;

        rustls_config.alpn_protocols = vec![b"rdesk".to_vec()];

        let quic_client_config =
            QuicClientConfig::try_from(rustls_config).context("failed to create QuicClientConfig")?;

        let mut transport = quinn::TransportConfig::default();
        transport.max_idle_timeout(Some(
            quinn::IdleTimeout::try_from(Duration::from_millis(IDLE_TIMEOUT_MS as u64))
                .context("invalid idle timeout")?,
        ));
        transport.keep_alive_interval(Some(KEEP_ALIVE_INTERVAL));

        let mut client_config = quinn::ClientConfig::new(Arc::new(quic_client_config));
        client_config.transport_config(Arc::new(transport));

        let mut endpoint = quinn::Endpoint::client("0.0.0.0:0".parse().unwrap())
            .context("failed to create QUIC client endpoint")?;
        endpoint.set_default_client_config(client_config);

        debug!("QUIC client endpoint created");

        Ok(Self { endpoint })
    }

    /// Connect to a QUIC server at the given address.
    ///
    /// Returns a [`QuicConnection`] wrapping the established QUIC connection.
    pub async fn connect(&self, addr: SocketAddr) -> Result<QuicConnection> {
        info!(%addr, "connecting to QUIC server");

        let connecting = self
            .endpoint
            .connect(addr, "rdesk")
            .context("failed to initiate QUIC connection")?;

        let connection = connecting
            .await
            .context("QUIC handshake failed")?;

        info!(
            remote = %connection.remote_address(),
            "QUIC connection established"
        );

        Ok(QuicConnection::new(connection))
    }

    /// Return a reference to the underlying [`quinn::Endpoint`].
    pub fn endpoint(&self) -> &quinn::Endpoint {
        &self.endpoint
    }
}

/// A [`ServerCertVerifier`] that accepts any server certificate.
///
/// This is intentional: rdesk verifies peer identity through the Noise protocol
/// handshake, not through TLS PKI. The QUIC/TLS layer only provides transport
/// encryption, while authentication happens at the application layer.
#[derive(Debug)]
struct SkipServerVerification;

impl ServerCertVerifier for SkipServerVerification {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> std::result::Result<ServerCertVerified, rustls::Error> {
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, rustls::Error> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, rustls::Error> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        // Support all schemes so we never reject a valid handshake.
        vec![
            SignatureScheme::RSA_PKCS1_SHA256,
            SignatureScheme::RSA_PKCS1_SHA384,
            SignatureScheme::RSA_PKCS1_SHA512,
            SignatureScheme::ECDSA_NISTP256_SHA256,
            SignatureScheme::ECDSA_NISTP384_SHA384,
            SignatureScheme::ECDSA_NISTP521_SHA512,
            SignatureScheme::RSA_PSS_SHA256,
            SignatureScheme::RSA_PSS_SHA384,
            SignatureScheme::RSA_PSS_SHA512,
            SignatureScheme::ED25519,
            SignatureScheme::ED448,
        ]
    }
}
