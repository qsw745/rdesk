//! End-to-end checks that the QUIC client actually authenticates the server.
//!
//! These tests exist because the client used to install a verifier that
//! accepted any certificate. They pin down the property that matters: a
//! mismatched or untrusted certificate is rejected unless the permissive path
//! has been explicitly opted into — and, just as importantly, that a *verifying*
//! client can still reach a self-hosted server, so nobody has a reason to reach
//! for the permissive path.

use std::net::SocketAddr;
use std::path::PathBuf;
use std::time::Duration;

use rdesk_net::{QuicClient, QuicServer, ServerCertificate, ServerVerification};
use rustls::pki_types::CertificateDer;

/// Hostname the test relay's certificate is issued for.
const RELAY_NAME: &str = "relay.rdesk.test";

/// A hostname the test relay's certificate is *not* issued for.
const OTHER_NAME: &str = "attacker.rdesk.test";

/// Cap every handshake so a regression shows up as a failure, not a hang.
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(10);

/// Bind a server on loopback and keep answering handshakes for the test's
/// duration. The [`JoinHandle`](tokio::task::JoinHandle) must be held: dropping
/// it aborts the accept loop.
fn spawn_relay(certificate: ServerCertificate) -> (QuicServer, tokio::task::JoinHandle<()>) {
    let server = QuicServer::bind("127.0.0.1:0".parse().unwrap(), certificate)
        .expect("QUIC server binds on loopback");

    let endpoint = server.endpoint().clone();
    let accept_loop = tokio::spawn(async move {
        while let Some(incoming) = endpoint.accept().await {
            // A rejected handshake errors here; that is the point of the test.
            let _ = incoming.await;
        }
    });

    (server, accept_loop)
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

/// Trust exactly the anchor the self-signed server generated for this process.
fn pinned(anchor: &CertificateDer<'static>) -> ServerVerification {
    ServerVerification::CustomRoots(vec![anchor.clone()])
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
    let (server, _accept) = spawn_relay(ServerCertificate::self_signed([RELAY_NAME]));

    // The generated CA is not in the public root store, so the default client
    // has no path to it.
    let err = try_connect(
        ServerVerification::WebPki,
        server.local_addr().unwrap(),
        RELAY_NAME,
    )
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
    let (server, _accept) = spawn_relay(ServerCertificate::self_signed([RELAY_NAME]));

    try_connect(
        ServerVerification::DangerousAcceptAnyCert,
        server.local_addr().unwrap(),
        RELAY_NAME,
    )
    .await
    .expect("the permissive verifier accepts any certificate");
}

#[tokio::test]
async fn pinned_anchor_client_accepts_self_signed_server() {
    // The self-hosting story: full verification against a pinned anchor, with
    // no need to touch the permissive path at all.
    let (server, _accept) = spawn_relay(ServerCertificate::self_signed([RELAY_NAME]));
    let anchor = server
        .self_signed_anchor()
        .expect("the self-signed path exposes an anchor");

    try_connect(pinned(anchor), server.local_addr().unwrap(), RELAY_NAME)
        .await
        .expect("a pinned anchor verifies the server it was generated for");
}

#[tokio::test]
async fn pinned_anchor_client_rejects_hostname_mismatch() {
    let (server, _accept) = spawn_relay(ServerCertificate::self_signed([RELAY_NAME]));
    let anchor = server
        .self_signed_anchor()
        .expect("the self-signed path exposes an anchor");

    // Same trusted anchor, same live server — only the requested name differs.
    // This is the shape of a MITM that holds *a* valid certificate but not one
    // for the host being connected to.
    let err = try_connect(pinned(anchor), server.local_addr().unwrap(), OTHER_NAME)
        .await
        .expect_err("a certificate that does not cover the requested name must be rejected");

    let chain = error_chain(&err);
    assert!(
        chain.contains("certificate not valid for name") && chain.contains(OTHER_NAME),
        "expected a name-mismatch rejection, got: {chain}"
    );
}

#[tokio::test]
async fn pinned_anchor_from_one_server_rejects_another() {
    // Two independently generated self-signed identities. Pinning one must not
    // transitively trust the other, otherwise "self-signed" would collapse back
    // into "trust anything".
    let (trusted, _accept_a) = spawn_relay(ServerCertificate::self_signed([RELAY_NAME]));
    let (impostor, _accept_b) = spawn_relay(ServerCertificate::self_signed([RELAY_NAME]));

    let anchor = trusted.self_signed_anchor().unwrap();
    let err = try_connect(pinned(anchor), impostor.local_addr().unwrap(), RELAY_NAME)
        .await
        .expect_err("an anchor pinned to one server must not verify a different one");

    let chain = error_chain(&err);
    assert!(
        chain.contains("unknownissuer"),
        "expected an untrusted-issuer rejection, got: {chain}"
    );
}

#[tokio::test]
async fn server_serves_a_certificate_loaded_from_pem_files() {
    // Exercises the production path: a chain and key read off disk, verified by
    // a client that trusts the issuing CA.
    let fixture = PemFixture::write(RELAY_NAME).expect("write PEM fixture");

    let (server, _accept) = spawn_relay(ServerCertificate::pem_files(
        &fixture.cert_chain,
        &fixture.private_key,
    ));

    assert!(
        server.self_signed_anchor().is_none(),
        "a real certificate has no generated anchor to hand out"
    );

    try_connect(
        ServerVerification::CustomRoots(vec![fixture.ca_der.clone()]),
        server.local_addr().unwrap(),
        RELAY_NAME,
    )
    .await
    .expect("a PEM-loaded certificate verifies against its issuing CA");
}

/// A CA plus a leaf certificate written out as PEM files, cleaned up on drop.
struct PemFixture {
    dir: PathBuf,
    cert_chain: PathBuf,
    private_key: PathBuf,
    ca_der: CertificateDer<'static>,
}

impl PemFixture {
    fn write(subject_name: &str) -> anyhow::Result<Self> {
        let ca_key = rcgen::KeyPair::generate()?;
        let mut ca_params = rcgen::CertificateParams::new(vec!["pem-fixture-ca".to_string()])?;
        ca_params.is_ca = rcgen::IsCa::Ca(rcgen::BasicConstraints::Unconstrained);
        ca_params.key_usages = vec![
            rcgen::KeyUsagePurpose::KeyCertSign,
            rcgen::KeyUsagePurpose::CrlSign,
            rcgen::KeyUsagePurpose::DigitalSignature,
        ];
        let ca_cert = ca_params.self_signed(&ca_key)?;

        let leaf_key = rcgen::KeyPair::generate()?;
        let leaf_params = rcgen::CertificateParams::new(vec![subject_name.to_string()])?;
        let leaf_cert = leaf_params.signed_by(&leaf_key, &ca_cert, &ca_key)?;

        // Unique per process and per test binary run; no tempfile dependency.
        let dir = std::env::temp_dir().join(format!(
            "rdesk-pem-fixture-{}-{subject_name}",
            std::process::id()
        ));
        std::fs::create_dir_all(&dir)?;

        let cert_chain = dir.join("chain.pem");
        let private_key = dir.join("key.pem");
        std::fs::write(&cert_chain, leaf_cert.pem())?;
        std::fs::write(&private_key, leaf_key.serialize_pem())?;

        Ok(Self {
            dir,
            cert_chain,
            private_key,
            ca_der: ca_cert.der().clone(),
        })
    }
}

impl Drop for PemFixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}
