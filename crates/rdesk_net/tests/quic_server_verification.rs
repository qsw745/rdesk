//! End-to-end checks that the QUIC client actually authenticates the server.
//!
//! These tests exist because the client used to install a verifier that
//! accepted any certificate. They pin down the property that matters: a
//! mismatched or untrusted certificate is rejected unless the permissive path
//! has been explicitly opted into.

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use quinn::crypto::rustls::QuicServerConfig;
use rustls::pki_types::{CertificateDer, PrivatePkcs8KeyDer};

use rdesk_net::{QuicClient, QuicServer, ServerVerification};

/// Hostname the test relay's certificate is issued for.
const RELAY_NAME: &str = "relay.rdesk.test";

/// A hostname the test relay's certificate is *not* issued for.
const OTHER_NAME: &str = "attacker.rdesk.test";

/// Cap every handshake so a regression shows up as a failure, not a hang.
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(10);

/// A QUIC server whose certificate is signed by a throwaway CA.
struct TestRelay {
    endpoint: quinn::Endpoint,
    ca_der: CertificateDer<'static>,
}

impl TestRelay {
    /// Start a relay on loopback with a leaf certificate valid for `RELAY_NAME`.
    fn start() -> anyhow::Result<Self> {
        let ca_key = rcgen::KeyPair::generate()?;
        let mut ca_params = rcgen::CertificateParams::new(vec!["rdesk-test-ca".to_string()])?;
        ca_params.is_ca = rcgen::IsCa::Ca(rcgen::BasicConstraints::Unconstrained);
        ca_params.key_usages = vec![
            rcgen::KeyUsagePurpose::KeyCertSign,
            rcgen::KeyUsagePurpose::CrlSign,
            rcgen::KeyUsagePurpose::DigitalSignature,
        ];
        let ca_cert = ca_params.self_signed(&ca_key)?;

        let leaf_key = rcgen::KeyPair::generate()?;
        let leaf_params = rcgen::CertificateParams::new(vec![RELAY_NAME.to_string()])?;
        let leaf_cert = leaf_params.signed_by(&leaf_key, &ca_cert, &ca_key)?;

        let mut rustls_config = rustls::ServerConfig::builder_with_provider(Arc::new(
            rustls::crypto::ring::default_provider(),
        ))
        .with_safe_default_protocol_versions()?
        .with_no_client_auth()
        .with_single_cert(
            vec![leaf_cert.der().clone()],
            PrivatePkcs8KeyDer::from(leaf_key.serialize_der()).into(),
        )?;
        rustls_config.alpn_protocols = vec![b"rdesk".to_vec()];

        let server_config =
            quinn::ServerConfig::with_crypto(Arc::new(QuicServerConfig::try_from(rustls_config)?));
        let endpoint = quinn::Endpoint::server(server_config, "127.0.0.1:0".parse()?)?;

        Ok(Self {
            endpoint,
            ca_der: ca_cert.der().clone(),
        })
    }

    fn addr(&self) -> SocketAddr {
        self.endpoint.local_addr().expect("relay has a local addr")
    }

    /// Keep answering handshakes for the lifetime of the returned task.
    fn serve(&self) -> tokio::task::JoinHandle<()> {
        let endpoint = self.endpoint.clone();
        tokio::spawn(async move {
            while let Some(incoming) = endpoint.accept().await {
                // A rejected handshake errors here; that is the point of the test.
                let _ = incoming.await;
            }
        })
    }
}

/// Attempt a handshake and return the result, bounded by `HANDSHAKE_TIMEOUT`.
async fn try_connect(
    verification: ServerVerification,
    addr: SocketAddr,
    server_name: &str,
) -> anyhow::Result<()> {
    let client = QuicClient::with_verification(verification)?;
    tokio::time::timeout(HANDSHAKE_TIMEOUT, client.connect(addr, server_name))
        .await
        .map_err(|_| anyhow::anyhow!("handshake did not settle within {HANDSHAKE_TIMEOUT:?}"))?
        .map(|_conn| ())
}

/// Flatten an error chain into one lowercase string for substring assertions.
fn error_chain(err: &anyhow::Error) -> String {
    err.chain()
        .map(|e| e.to_string())
        .collect::<Vec<_>>()
        .join(": ")
        .to_lowercase()
}

#[tokio::test]
async fn default_client_rejects_untrusted_self_signed_server() {
    let server = QuicServer::new("127.0.0.1:0".parse().unwrap()).expect("start QUIC server");
    let addr = server.local_addr().expect("server addr");
    let endpoint = server.endpoint().clone();
    let _accept = tokio::spawn(async move {
        while let Some(incoming) = endpoint.accept().await {
            let _ = incoming.await;
        }
    });

    // `QuicServer` presents an ephemeral self-signed cert for "rdesk-server",
    // which chains to nothing in the public root store.
    let err = try_connect(ServerVerification::WebPki, addr, "rdesk-server")
        .await
        .expect_err("a self-signed server must not be accepted under WebPki verification");

    let chain = error_chain(&err);
    assert!(
        chain.contains("unknownissuer"),
        "expected an untrusted-issuer rejection, got: {chain}"
    );
}

#[tokio::test]
async fn permissive_opt_in_accepts_untrusted_self_signed_server() {
    // Positive control: the only difference from the test above is the
    // verification mode, so that test cannot be passing for an unrelated reason
    // (wrong port, ALPN mismatch, dead server).
    let server = QuicServer::new("127.0.0.1:0".parse().unwrap()).expect("start QUIC server");
    let addr = server.local_addr().expect("server addr");
    let endpoint = server.endpoint().clone();
    let _accept = tokio::spawn(async move {
        while let Some(incoming) = endpoint.accept().await {
            let _ = incoming.await;
        }
    });

    try_connect(
        ServerVerification::DangerousAcceptAnyCert,
        addr,
        "rdesk-server",
    )
    .await
    .expect("the permissive verifier accepts any certificate");
}

#[tokio::test]
async fn custom_root_client_accepts_matching_hostname() {
    let relay = TestRelay::start().expect("start test relay");
    let _accept = relay.serve();

    try_connect(
        ServerVerification::CustomRoots(vec![relay.ca_der.clone()]),
        relay.addr(),
        RELAY_NAME,
    )
    .await
    .expect("a cert issued by a trusted CA for the requested name is accepted");
}

#[tokio::test]
async fn custom_root_client_rejects_hostname_mismatch() {
    let relay = TestRelay::start().expect("start test relay");
    let _accept = relay.serve();

    // Same trusted CA, same live server — only the requested name differs. This
    // is the shape of a MITM that holds *a* valid certificate but not one for
    // the host being connected to.
    let err = try_connect(
        ServerVerification::CustomRoots(vec![relay.ca_der.clone()]),
        relay.addr(),
        OTHER_NAME,
    )
    .await
    .expect_err("a certificate that does not cover the requested name must be rejected");

    let chain = error_chain(&err);
    assert!(
        chain.contains("certificate not valid for name") && chain.contains(OTHER_NAME),
        "expected a name-mismatch rejection, got: {chain}"
    );
}
