//! QUIC client endpoint.
//!
//! Creates a [`quinn::Endpoint`] that authenticates the server with real TLS
//! certificate verification by default ([`ServerVerification::WebPki`]).
//!
//! Historically this client installed a verifier that accepted *any* server
//! certificate, on the assumption that peer identity would be checked by the
//! Noise handshake layered on top. That handshake is not wired up (see the
//! TODOs in `rdesk_core::client::RemoteClient::connect`), so the assumption did
//! not hold and the transport had no authentication at all. The permissive
//! verifier now lives behind [`ServerVerification::DangerousAcceptAnyCert`],
//! which is off unless explicitly opted into.

use anyhow::{Context, Result};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use quinn::crypto::rustls::QuicClientConfig;
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::CryptoProvider;
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{RootCertStore, SignatureScheme};
use tracing::{debug, info, warn};

use crate::quic::stream::QuicConnection;

/// QUIC idle timeout.
const IDLE_TIMEOUT_MS: u32 = 30_000;

/// QUIC keep-alive interval.
const KEEP_ALIVE_INTERVAL: Duration = Duration::from_secs(10);

/// Environment variable that opts into [`ServerVerification::DangerousAcceptAnyCert`].
///
/// Deliberately verbose: anyone reading a deployment manifest should be able to
/// tell that this disables server authentication.
pub const INSECURE_SKIP_VERIFY_ENV: &str = "RDESK_QUIC_DANGEROUSLY_ACCEPT_ANY_SERVER_CERT";

/// How the QUIC client authenticates the server it connects to.
#[derive(Debug, Clone, Default)]
pub enum ServerVerification {
    /// Verify the server certificate chain against the Mozilla root CA bundle
    /// and check it matches the requested server name. This is the default.
    #[default]
    WebPki,

    /// Verify against an explicit set of DER-encoded trust anchors instead of
    /// the public root store, and still check the server name.
    ///
    /// This is the correct option for self-hosted relays: run your own CA,
    /// ship its certificate with the client, and keep full verification.
    CustomRoots(Vec<CertificateDer<'static>>),

    /// Accept *any* server certificate without verifying the chain or the
    /// server name.
    ///
    /// This removes all protection against an active man-in-the-middle: an
    /// attacker on the path can terminate the connection, present any
    /// certificate, and read or modify screen frames and input events. Only use
    /// it against a server you control on a network you trust.
    DangerousAcceptAnyCert,
}

impl ServerVerification {
    /// Read the verification mode from the environment.
    ///
    /// Returns [`ServerVerification::WebPki`] unless [`INSECURE_SKIP_VERIFY_ENV`]
    /// is set to a truthy value (`1`, `true`, `yes`, `on`).
    pub fn from_env() -> Self {
        Self::from_env_value(std::env::var(INSECURE_SKIP_VERIFY_ENV).ok().as_deref())
    }

    /// Pure form of [`from_env`](Self::from_env), so the parsing can be tested
    /// without mutating process-global state.
    fn from_env_value(raw: Option<&str>) -> Self {
        match raw.map(str::trim) {
            Some(v) if matches!(v.to_ascii_lowercase().as_str(), "1" | "true" | "yes" | "on") => {
                Self::DangerousAcceptAnyCert
            }
            _ => Self::WebPki,
        }
    }

    /// Resolve this mode into the material rustls needs to finish a client config.
    fn build_verifier(self, provider: Arc<CryptoProvider>) -> Result<VerifierSource> {
        match self {
            Self::WebPki => {
                let mut roots = RootCertStore::empty();
                roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
                Ok(VerifierSource::Roots(roots))
            }
            Self::CustomRoots(certs) => {
                if certs.is_empty() {
                    anyhow::bail!(
                        "ServerVerification::CustomRoots was given an empty trust anchor list; \
                         refusing to build a client that trusts nothing"
                    );
                }
                let mut roots = RootCertStore::empty();
                for cert in certs {
                    roots
                        .add(cert)
                        .context("failed to add custom root certificate to trust store")?;
                }
                info!(
                    trust_anchors = roots.len(),
                    "QUIC client using custom TLS trust anchors"
                );
                Ok(VerifierSource::Roots(roots))
            }
            Self::DangerousAcceptAnyCert => {
                warn!(
                    env = INSECURE_SKIP_VERIFY_ENV,
                    "!!! QUIC SERVER CERTIFICATE VERIFICATION IS DISABLED !!! \
                     Any host on the network path can impersonate the relay and read or \
                     modify screen data and input events. This must not be used in production."
                );
                Ok(VerifierSource::AcceptAny(Arc::new(
                    DangerousAcceptAnyServerCert::new(provider),
                )))
            }
        }
    }
}

/// The two ways a client config can be finished off.
///
/// `Roots` goes through rustls' ordinary, safe builder path; `AcceptAny` has to
/// go through `dangerous()`. Keeping them as distinct values means the unsafe
/// path is visible at the single call site that consumes this.
enum VerifierSource {
    Roots(RootCertStore),
    AcceptAny(Arc<dyn ServerCertVerifier>),
}

/// QUIC client wrapping a [`quinn::Endpoint`].
pub struct QuicClient {
    endpoint: quinn::Endpoint,
}

impl QuicClient {
    /// Create a QUIC client endpoint using the verification mode from the
    /// environment (see [`ServerVerification::from_env`]).
    ///
    /// This verifies server certificates against the public root store unless
    /// [`INSECURE_SKIP_VERIFY_ENV`] has been explicitly set.
    pub fn new() -> Result<Self> {
        Self::with_verification(ServerVerification::from_env())
    }

    /// Create a QUIC client endpoint with an explicit verification mode.
    pub fn with_verification(verification: ServerVerification) -> Result<Self> {
        let provider = Arc::new(rustls::crypto::ring::default_provider());

        // Generate a self-signed certificate for the client identity. The
        // current QUIC server does not request client auth, but presenting one
        // keeps the door open for mutual TLS later.
        let cert_key = rcgen::generate_simple_self_signed(vec!["rdesk-client".to_string()])
            .context("failed to generate self-signed certificate")?;

        let cert_der = CertificateDer::from(cert_key.cert);
        let key_der =
            rustls::pki_types::PrivatePkcs8KeyDer::from(cert_key.key_pair.serialize_der());

        let builder = rustls::ClientConfig::builder_with_provider(provider.clone())
            .with_safe_default_protocol_versions()
            .context("failed to set protocol versions")?;

        let builder = match verification.build_verifier(provider)? {
            VerifierSource::Roots(roots) => builder.with_root_certificates(roots),
            VerifierSource::AcceptAny(verifier) => builder
                .dangerous()
                .with_custom_certificate_verifier(verifier),
        };

        let mut rustls_config = builder
            .with_client_auth_cert(vec![cert_der], key_der.into())
            .context("failed to set client auth certificate")?;

        rustls_config.alpn_protocols = vec![b"rdesk".to_vec()];

        let quic_client_config = QuicClientConfig::try_from(rustls_config)
            .context("failed to create QuicClientConfig")?;

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
    /// `server_name` is the name the server's certificate must be valid for
    /// (typically the relay's hostname). It is not merely cosmetic: unless the
    /// client was built with [`ServerVerification::DangerousAcceptAnyCert`], a
    /// certificate that does not cover this name is rejected.
    ///
    /// Returns a [`QuicConnection`] wrapping the established QUIC connection.
    pub async fn connect(&self, addr: SocketAddr, server_name: &str) -> Result<QuicConnection> {
        info!(%addr, server_name, "connecting to QUIC server");

        let connecting = self
            .endpoint
            .connect(addr, server_name)
            .context("failed to initiate QUIC connection")?;

        let connection = connecting.await.context("QUIC handshake failed")?;

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
/// Reachable only via [`ServerVerification::DangerousAcceptAnyCert`], which is
/// never the default. See that variant's docs for what it gives up.
#[derive(Debug)]
struct DangerousAcceptAnyServerCert {
    provider: Arc<CryptoProvider>,
}

impl DangerousAcceptAnyServerCert {
    fn new(provider: Arc<CryptoProvider>) -> Self {
        Self { provider }
    }
}

impl ServerCertVerifier for DangerousAcceptAnyServerCert {
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
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, rustls::Error> {
        // The chain is unverified, but the handshake signature still has to
        // match the presented key — otherwise the connection is not even
        // encrypted against a passive attacker.
        rustls::crypto::verify_tls12_signature(
            message,
            cert,
            dss,
            &self.provider.signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &self.provider.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.provider
            .signature_verification_algorithms
            .supported_schemes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_to_webpki_when_env_is_unset() {
        assert!(matches!(
            ServerVerification::from_env_value(None),
            ServerVerification::WebPki
        ));
    }

    #[test]
    fn defaults_to_webpki_for_non_truthy_values() {
        for raw in ["", "0", "false", "no", "off", "maybe"] {
            assert!(
                matches!(
                    ServerVerification::from_env_value(Some(raw)),
                    ServerVerification::WebPki
                ),
                "{raw:?} should not disable verification"
            );
        }
    }

    #[test]
    fn opts_into_permissive_mode_only_for_truthy_values() {
        for raw in ["1", "true", "TRUE", "yes", "on", " true "] {
            assert!(
                matches!(
                    ServerVerification::from_env_value(Some(raw)),
                    ServerVerification::DangerousAcceptAnyCert
                ),
                "{raw:?} should enable the permissive verifier"
            );
        }
    }

    #[test]
    fn rejects_empty_custom_root_list() {
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let err = ServerVerification::CustomRoots(Vec::new())
            .build_verifier(provider)
            .err()
            .expect("empty trust anchor list must be rejected");
        assert!(err.to_string().contains("empty trust anchor list"));
    }
}
