//! Host (controlled) side logic.
//!
//! [`RemoteServer`] represents the *host* end of a remote desktop session --
//! the machine whose screen is being shared and whose input devices are being
//! controlled. It listens for QUIC connections, runs the Noise handshake,
//! verifies the controller's password, and then owns the screen-capture and
//! input-simulation subsystems for each active session.

use std::net::SocketAddr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::{info, warn};

use rdesk_common::config::AppConfig;
use rdesk_common::password::verify_password;
use rdesk_common::platform::platform_name;
use rdesk_common::protos::message::{message::Union, LoginResponse, Message, PeerInfo};
use rdesk_crypto::keypair::{generate_keypair, KeyPair};
use rdesk_crypto::AuthState;
use rdesk_net::quic::server::CertificateDer;
use rdesk_net::quic::stream::StreamType;
use rdesk_net::{QuicServer, ServerCertificate};

use crate::capture;
use crate::codec;
use crate::input;
use crate::session::Session;
use crate::transport::SecureChannel;

/// Version string reported to controllers in [`LoginResponse`].
const HOST_VERSION: &str = env!("CARGO_PKG_VERSION");

/// Codec advertised to controllers. Matches `codec::vpx::RawEncoder`.
const SELECTED_CODEC: &str = "raw";

/// What a rejected controller is told. Deliberately uninformative: a controller
/// that guessed wrong learns only that it was wrong.
const REJECTION_MESSAGE: &str = "authentication failed";

/// An authenticated session together with the channel it arrived on.
///
/// The channel is retained rather than dropped: dropping it would reset the
/// QUIC stream immediately after login, so no input event could ever arrive.
struct SessionEntry {
    session: Arc<Session>,
    channel: Arc<Mutex<SecureChannel>>,
}

/// Host-side remote desktop server.
pub struct RemoteServer {
    /// Application configuration (device ID, stored password hash, etc.).
    config: AppConfig,

    /// Long-lived Noise static identity for this host.
    keypair: KeyPair,

    /// The QUIC listener.
    quic: Arc<QuicServer>,

    /// Whether the server is currently accepting connections.
    listening: Arc<AtomicBool>,

    /// Active sessions, each holding its authenticated control channel open.
    sessions: Arc<Mutex<Vec<SessionEntry>>>,
}

impl RemoteServer {
    /// Start listening for incoming remote desktop connections on `bind_addr`.
    ///
    /// `certificate` is the host's TLS identity; see [`ServerCertificate`] for
    /// the production and development options.
    ///
    /// Fails if `config.permanent_password` is unset — a host that accepts
    /// connections without a password to check would let anyone who can reach
    /// the port take control.
    pub async fn start(
        bind_addr: SocketAddr,
        certificate: ServerCertificate,
        config: &AppConfig,
    ) -> anyhow::Result<Self> {
        info!(
            device_id = %config.device_id,
            %bind_addr,
            "starting remote desktop server"
        );

        if config
            .permanent_password
            .as_deref()
            .map(str::trim)
            .filter(|p| !p.is_empty())
            .is_none()
        {
            anyhow::bail!(
                "refusing to listen: AppConfig::permanent_password is not set, so no controller \
                 could be authenticated. Set one with rdesk_common::password::hash_password()."
            );
        }

        // Registering with the rendezvous server so controllers can find this
        // host by device ID needs rdesk_net::rendezvous, which is still a stub.
        // Direct connections to `bind_addr` work without it.
        let quic = QuicServer::bind(bind_addr, certificate)?;

        Ok(Self {
            config: config.clone(),
            keypair: generate_keypair(),
            quic: Arc::new(quic),
            listening: Arc::new(AtomicBool::new(true)),
            sessions: Arc::new(Mutex::new(Vec::new())),
        })
    }

    /// Accept the next incoming connection and return a fully-initialised
    /// [`Session`].
    ///
    /// Blocks until a controller connects, then runs the Noise handshake,
    /// verifies its password, and attaches the host-side subsystems.
    pub async fn accept_connection(&self) -> anyhow::Result<Arc<Session>> {
        if !self.listening.load(Ordering::Relaxed) {
            anyhow::bail!("server is not listening");
        }

        info!("waiting for incoming connection...");
        let connection = self.quic.accept().await?;
        let remote = connection.remote_address();

        let (stream_type, send, recv) = connection.accept_stream().await?;
        if stream_type != StreamType::Control {
            anyhow::bail!("controller opened a {stream_type:?} stream before authenticating");
        }

        let mut auth_state = AuthState::WaitingForHandshake;
        info!(%remote, %auth_state, "controller connected; starting Noise handshake");
        let mut channel = SecureChannel::responder(&self.keypair, send, recv).await?;
        auth_state = AuthState::HandshakeComplete;
        info!(%remote, %auth_state, "Noise handshake complete");

        // --- Password verification ------------------------------------------
        let login = match channel.recv().await?.union {
            Some(Union::LoginRequest(req)) => req,
            other => {
                anyhow::bail!("expected a LoginRequest from the controller, got {other:?}");
            }
        };

        let stored = self
            .config
            .permanent_password
            .as_deref()
            .expect("start() rejects a config without a password");

        // `verify_password` errors on a malformed stored hash; that is a host
        // misconfiguration, not a wrong guess, so keep the two apart.
        let authenticated = match verify_password(&login.password, stored) {
            Ok(ok) => ok,
            Err(e) => {
                warn!(error = %e, "stored password hash is unusable; rejecting controller");
                false
            }
        };

        if !authenticated {
            auth_state = AuthState::Failed;
            warn!(%remote, %auth_state, "rejecting controller: password did not match");
            // Tell the controller before tearing down, so it can report a clean
            // error instead of a transport failure.
            let _ = channel
                .send(&Message {
                    union: Some(Union::LoginResponse(LoginResponse {
                        success: false,
                        error: REJECTION_MESSAGE.to_string(),
                        peer_info: None,
                        selected_codec: String::new(),
                    })),
                })
                .await;
            connection.close(0, b"authentication failed");
            anyhow::bail!("controller at {remote} failed authentication");
        }

        auth_state = AuthState::Authenticated;
        info!(%remote, %auth_state, "controller authenticated");

        channel
            .send(&Message {
                union: Some(Union::LoginResponse(LoginResponse {
                    success: true,
                    error: String::new(),
                    peer_info: Some(PeerInfo {
                        hostname: self.config.device_id.clone(),
                        os: platform_name().to_string(),
                        displays: Vec::new(),
                        version: HOST_VERSION.to_string(),
                    }),
                    selected_codec: SELECTED_CODEC.to_string(),
                })),
            })
            .await?;

        // --- Session setup ----------------------------------------------------
        let session_id = format!("server-{}-{}", self.config.device_id, rand::random::<u32>());
        let mut session = Session::new(session_id);

        match capture::create_capturer() {
            Ok(capturer) => session.set_capturer(capturer),
            Err(e) => warn!("failed to create screen capturer: {}", e),
        }

        let encoder: Box<dyn codec::VideoEncoder> = Box::new(codec::vpx::RawEncoder::new());
        session.set_encoder(encoder);

        match input::create_input_simulator() {
            Ok(sim) => session.set_input(sim),
            Err(e) => warn!("failed to create input simulator: {}", e),
        }

        session.start()?;
        session.activate()?;

        // TODO: Spawn the capture->encode->send loop on a video stream, and an
        // inbound loop that applies MouseEvent/KeyEvent/TouchEvent through
        // `session.input()`. Until then `recv_control` is the seam for reading
        // what the controller sends.
        let session = Arc::new(session);
        self.sessions.lock().await.push(SessionEntry {
            session: session.clone(),
            channel: Arc::new(Mutex::new(channel)),
        });

        Ok(session)
    }

    /// Stop the server and disconnect all active sessions.
    pub async fn stop(&self) {
        info!(device_id = %self.config.device_id, "stopping remote desktop server");
        self.listening.store(false, Ordering::Relaxed);

        let sessions = self.sessions.lock().await;
        for entry in sessions.iter() {
            entry.session.stop();
        }

        self.quic.endpoint().close(0u32.into(), b"server stopping");
        // Deregistering from the rendezvous server is a no-op until that client
        // stops being a stub.
    }

    /// Return whether the server is currently listening.
    pub fn is_listening(&self) -> bool {
        self.listening.load(Ordering::Relaxed)
    }

    /// The address the QUIC listener is bound to.
    pub fn local_addr(&self) -> anyhow::Result<SocketAddr> {
        self.quic.local_addr()
    }

    /// The trust anchor for a [`ServerCertificate::SelfSigned`] identity, for a
    /// controller to pin. `None` when a real certificate is in use.
    pub fn self_signed_anchor(&self) -> Option<&CertificateDer<'static>> {
        self.quic.self_signed_anchor()
    }

    /// Return the number of active sessions.
    pub async fn active_session_count(&self) -> usize {
        self.sessions.lock().await.len()
    }

    /// Identifiers of all sessions currently held open.
    pub async fn session_ids(&self) -> Vec<String> {
        self.sessions
            .lock()
            .await
            .iter()
            .map(|e| e.session.id().to_string())
            .collect()
    }

    /// Receive the next control message from an authenticated controller.
    ///
    /// A seam for the inbound event loop that `accept_connection` does not yet
    /// spawn. Blocks until the controller sends something.
    pub async fn recv_control(&self, session_id: &str) -> anyhow::Result<Message> {
        // Clone the channel handle out before awaiting, so a blocked read does
        // not hold the session-list lock.
        let channel = {
            let sessions = self.sessions.lock().await;
            sessions
                .iter()
                .find(|e| e.session.id() == session_id)
                .map(|e| e.channel.clone())
                .ok_or_else(|| anyhow::anyhow!("unknown session id: {session_id}"))?
        };
        let message = channel.lock().await.recv().await?;
        Ok(message)
    }
}
