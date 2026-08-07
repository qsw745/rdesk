//! QUIC server endpoint.
//!
//! Creates a [`quinn::Endpoint`] that listens for incoming QUIC connections.
//!
//! The certificate is chosen explicitly via [`ServerCertificate`]. There is no
//! implicit default: a server that silently invents its own throwaway identity
//! is exactly what made the old permissive client verifier look harmless.
//! Production deployments load a real certificate with
//! [`ServerCertificate::PemFiles`]; [`ServerCertificate::SelfSigned`] is for
//! development and tests, and hands back a trust anchor so a *verifying* client
//! can still be pointed at it.

use anyhow::{Context, Result};
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use quinn::crypto::rustls::QuicServerConfig;
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
use tracing::{debug, info, warn};

use crate::quic::stream::QuicConnection;

/// QUIC idle timeout.
const IDLE_TIMEOUT_MS: u32 = 30_000;

/// QUIC keep-alive interval.
const KEEP_ALIVE_INTERVAL: Duration = Duration::from_secs(10);

/// Common-name prefix of the throwaway CA minted for
/// [`ServerCertificate::SelfSigned`]. A random suffix is appended per CA.
const SELF_SIGNED_CA_CN_PREFIX: &str = "rdesk self-signed CA";

/// Where the server's TLS identity comes from.
///
/// Not `Clone`: the `Der` variant carries private key material, which
/// [`PrivateKeyDer`] deliberately makes awkward to copy around.
#[derive(Debug)]
pub enum ServerCertificate {
    /// Load a PEM certificate chain and private key from disk.
    ///
    /// This is the production option. The chain should be leaf-first, and the
    /// leaf must be valid for the name clients pass to
    /// [`QuicClient::connect`](crate::quic::client::QuicClient::connect).
    PemFiles {
        /// PEM file holding the certificate chain, leaf first.
        cert_chain: PathBuf,
        /// PEM file holding the matching private key (PKCS#8, PKCS#1, or SEC1).
        private_key: PathBuf,
    },

    /// Use a chain and key already held in memory.
    Der {
        /// DER certificate chain, leaf first.
        chain: Vec<CertificateDer<'static>>,
        /// DER private key matching the leaf.
        private_key: PrivateKeyDer<'static>,
    },

    /// Mint a throwaway CA and a leaf certificate for `subject_names`.
    ///
    /// Development and tests only. The material is regenerated on every start,
    /// so clients cannot pin it across restarts; within one process, a client
    /// can verify this server by feeding [`QuicServer::self_signed_anchor`] to
    /// [`ServerVerification::CustomRoots`](crate::quic::client::ServerVerification::CustomRoots).
    SelfSigned {
        /// DNS names (or IPs) the generated leaf certificate is valid for.
        subject_names: Vec<String>,
    },
}

impl ServerCertificate {
    /// Convenience constructor for [`ServerCertificate::PemFiles`].
    pub fn pem_files(cert_chain: impl Into<PathBuf>, private_key: impl Into<PathBuf>) -> Self {
        Self::PemFiles {
            cert_chain: cert_chain.into(),
            private_key: private_key.into(),
        }
    }

    /// Convenience constructor for [`ServerCertificate::SelfSigned`].
    pub fn self_signed(subject_names: impl IntoIterator<Item = impl Into<String>>) -> Self {
        Self::SelfSigned {
            subject_names: subject_names.into_iter().map(Into::into).collect(),
        }
    }

    /// Turn the configuration into concrete TLS material.
    fn resolve(self) -> Result<ResolvedCertificate> {
        match self {
            Self::PemFiles {
                cert_chain,
                private_key,
            } => {
                let chain = load_pem_chain(&cert_chain)?;
                let key = load_pem_key(&private_key)?;
                info!(
                    cert_chain = %cert_chain.display(),
                    chain_len = chain.len(),
                    "QUIC server loaded TLS certificate from disk"
                );
                Ok(ResolvedCertificate {
                    chain,
                    private_key: key,
                    self_signed_anchor: None,
                })
            }

            Self::Der { chain, private_key } => {
                if chain.is_empty() {
                    anyhow::bail!("ServerCertificate::Der was given an empty certificate chain");
                }
                Ok(ResolvedCertificate {
                    chain,
                    private_key,
                    self_signed_anchor: None,
                })
            }

            Self::SelfSigned { subject_names } => {
                if subject_names.is_empty() {
                    anyhow::bail!(
                        "ServerCertificate::SelfSigned needs at least one subject name; \
                         a certificate valid for nothing cannot be verified by any client"
                    );
                }
                let generated = generate_self_signed(&subject_names)?;
                warn!(
                    names = ?subject_names,
                    "QUIC server is using an EPHEMERAL self-signed certificate. It is regenerated \
                     on every restart, so no client can verify it across restarts. Use \
                     ServerCertificate::PemFiles in production."
                );
                Ok(generated)
            }
        }
    }
}

/// Concrete TLS material plus, for the self-signed path, the anchor that makes
/// it verifiable.
struct ResolvedCertificate {
    chain: Vec<CertificateDer<'static>>,
    private_key: PrivateKeyDer<'static>,
    self_signed_anchor: Option<CertificateDer<'static>>,
}

/// Read a PEM certificate chain from `path`.
fn load_pem_chain(path: &Path) -> Result<Vec<CertificateDer<'static>>> {
    let pem = std::fs::read(path)
        .with_context(|| format!("failed to read certificate chain {}", path.display()))?;

    let chain = rustls_pemfile::certs(&mut pem.as_slice())
        .collect::<std::result::Result<Vec<_>, _>>()
        .with_context(|| format!("failed to parse certificate chain {}", path.display()))?;

    if chain.is_empty() {
        anyhow::bail!("no CERTIFICATE block found in {}", path.display());
    }
    Ok(chain)
}

/// Read a PEM private key from `path`.
fn load_pem_key(path: &Path) -> Result<PrivateKeyDer<'static>> {
    // Deliberately no logging of file contents anywhere on this path.
    let pem = std::fs::read(path)
        .with_context(|| format!("failed to read private key {}", path.display()))?;

    rustls_pemfile::private_key(&mut pem.as_slice())
        .with_context(|| format!("failed to parse private key {}", path.display()))?
        .with_context(|| format!("no PRIVATE KEY block found in {}", path.display()))
}

/// Mint a throwaway CA and a leaf certificate valid for `subject_names`.
///
/// A bare self-signed leaf cannot act as its own webpki trust anchor, so a
/// client that still verifies would have no way to accept it. Issuing a proper
/// CA and a leaf beneath it keeps the self-signed path compatible with real
/// verification instead of forcing callers back to the permissive verifier.
fn generate_self_signed(subject_names: &[String]) -> Result<ResolvedCertificate> {
    use rand::Rng;

    let ca_key = rcgen::KeyPair::generate().context("failed to generate self-signed CA key")?;
    let mut ca_params = rcgen::CertificateParams::default();
    ca_params.is_ca = rcgen::IsCa::Ca(rcgen::BasicConstraints::Constrained(0));
    ca_params.key_usages = vec![
        rcgen::KeyUsagePurpose::KeyCertSign,
        rcgen::KeyUsagePurpose::CrlSign,
        rcgen::KeyUsagePurpose::DigitalSignature,
    ];

    // rcgen defaults every certificate to `CN=rcgen self signed cert`. Left
    // alone, two independently generated CAs share an issuer name, so a client
    // pinned to one would match the other by name and only then fail on the
    // signature. Give each CA a distinct name so unrelated identities are
    // actually distinguishable.
    let ca_id: u64 = rand::thread_rng().gen();
    let mut ca_dn = rcgen::DistinguishedName::new();
    ca_dn.push(
        rcgen::DnType::CommonName,
        format!("{SELF_SIGNED_CA_CN_PREFIX} {ca_id:016x}"),
    );
    ca_params.distinguished_name = ca_dn;

    let ca_cert = ca_params
        .self_signed(&ca_key)
        .context("failed to self-sign CA certificate")?;

    let leaf_key = rcgen::KeyPair::generate().context("failed to generate server key")?;
    let mut leaf_params = rcgen::CertificateParams::new(subject_names.to_vec())
        .with_context(|| format!("invalid subject names for certificate: {subject_names:?}"))?;
    let mut leaf_dn = rcgen::DistinguishedName::new();
    leaf_dn.push(rcgen::DnType::CommonName, subject_names[0].clone());
    leaf_params.distinguished_name = leaf_dn;

    let leaf_cert = leaf_params
        .signed_by(&leaf_key, &ca_cert, &ca_key)
        .context("failed to sign server certificate")?;

    Ok(ResolvedCertificate {
        chain: vec![leaf_cert.der().clone()],
        private_key: PrivatePkcs8KeyDer::from(leaf_key.serialize_der()).into(),
        self_signed_anchor: Some(ca_cert.der().clone()),
    })
}

/// QUIC server wrapping a [`quinn::Endpoint`].
pub struct QuicServer {
    endpoint: quinn::Endpoint,
    self_signed_anchor: Option<CertificateDer<'static>>,
}

impl QuicServer {
    /// Bind a QUIC server to `bind_addr` using `certificate`.
    pub fn bind(bind_addr: SocketAddr, certificate: ServerCertificate) -> Result<Self> {
        let resolved = certificate.resolve()?;

        let mut rustls_config = rustls::ServerConfig::builder_with_provider(Arc::new(
            rustls::crypto::ring::default_provider(),
        ))
        .with_safe_default_protocol_versions()
        .context("failed to set protocol versions")?
        .with_no_client_auth()
        .with_single_cert(resolved.chain, resolved.private_key)
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

        Ok(Self {
            endpoint,
            self_signed_anchor: resolved.self_signed_anchor,
        })
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

    /// The CA certificate backing a [`ServerCertificate::SelfSigned`] identity,
    /// or `None` for a real certificate.
    ///
    /// Feed this to
    /// [`ServerVerification::CustomRoots`](crate::quic::client::ServerVerification::CustomRoots)
    /// so a client can verify this server without disabling verification. It is
    /// only valid for the lifetime of this process.
    pub fn self_signed_anchor(&self) -> Option<&CertificateDer<'static>> {
        self.self_signed_anchor.as_ref()
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn self_signed_requires_at_least_one_subject_name() {
        let err = ServerCertificate::SelfSigned {
            subject_names: Vec::new(),
        }
        .resolve()
        .err()
        .expect("a certificate valid for no names must be rejected");
        assert!(err.to_string().contains("at least one subject name"));
    }

    #[test]
    fn der_variant_rejects_empty_chain() {
        let key = rcgen::KeyPair::generate().unwrap();
        let err = ServerCertificate::Der {
            chain: Vec::new(),
            private_key: PrivatePkcs8KeyDer::from(key.serialize_der()).into(),
        }
        .resolve()
        .err()
        .expect("an empty certificate chain must be rejected");
        assert!(err.to_string().contains("empty certificate chain"));
    }

    #[test]
    fn self_signed_yields_a_pinnable_anchor_distinct_from_the_leaf() {
        let resolved = ServerCertificate::self_signed(["relay.example"])
            .resolve()
            .expect("self-signed generation succeeds");

        let anchor = resolved
            .self_signed_anchor
            .expect("the self-signed path must expose an anchor to pin");
        assert_eq!(resolved.chain.len(), 1, "server presents the leaf only");
        assert_ne!(
            anchor.as_ref(),
            resolved.chain[0].as_ref(),
            "the anchor must be the issuing CA, not the leaf itself"
        );
    }

    #[test]
    fn missing_pem_files_fail_with_the_offending_path() {
        let err = ServerCertificate::pem_files("/nonexistent/chain.pem", "/nonexistent/key.pem")
            .resolve()
            .err()
            .expect("missing files must fail");
        let chain = err
            .chain()
            .map(|e| e.to_string())
            .collect::<Vec<_>>()
            .join(": ");
        assert!(chain.contains("/nonexistent/chain.pem"), "got: {chain}");
    }
}
