//! Host (controlled) side logic.
//!
//! [`RemoteServer`] represents the *host* end of a remote desktop session --
//! the machine whose screen is being shared and whose input devices are being
//! controlled. It listens for incoming connections via the signaling
//! infrastructure, performs authentication, and then drives the screen capture
//! loop and input simulation pipeline.

use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::{info, warn, error};

use rdesk_common::config::AppConfig;

use crate::capture;
use crate::codec;
use crate::input;
use crate::session::{Session, SessionState};

/// Host-side remote desktop server.
///
/// Listens for incoming connections from [`RemoteClient`](crate::client::RemoteClient)
/// instances, authenticates them, and manages the screen-capture / input-simulation
/// loop for each active session.
pub struct RemoteServer {
    /// Application configuration (signaling server, device ID, etc.).
    config: AppConfig,

    /// Whether the server is currently accepting connections.
    listening: Arc<std::sync::atomic::AtomicBool>,

    /// Active sessions (keyed by session ID).
    sessions: Arc<Mutex<Vec<Arc<Session>>>>,
}

impl RemoteServer {
    /// Start listening for incoming remote desktop connections.
    ///
    /// 1. Registers this device with the rendezvous server.
    /// 2. Begins listening for QUIC connections (direct and relayed).
    /// 3. Returns a `RemoteServer` ready to accept connections.
    pub async fn start(config: &AppConfig) -> anyhow::Result<Self> {
        info!(
            device_id = %config.device_id,
            signaling_server = %config.signaling_server,
            "starting remote desktop server"
        );

        // --- 1. Register with rendezvous server -----------------------------
        // TODO: Use rdesk_net::RendezvousClient to register this device's
        // public key and NAT type.
        //
        // let rendezvous = RendezvousClient::connect(&config.signaling_server).await?;
        // rendezvous.register_peer(&config.device_id, &keypair.public).await?;

        // --- 2. Start QUIC listener ------------------------------------------
        // TODO: Bind a QuicServer to listen for incoming connections. Also
        // register with the relay server as a fallback.
        //
        // let quic_server = QuicServer::bind("0.0.0.0:0").await?;
        // let relay = RelayClient::connect(&config.relay_server).await?;

        let listening = Arc::new(std::sync::atomic::AtomicBool::new(true));

        info!(device_id = %config.device_id, "server is listening (stub)");

        Ok(Self {
            config: config.clone(),
            listening,
            sessions: Arc::new(Mutex::new(Vec::new())),
        })
    }

    /// Accept the next incoming connection and return a fully-initialised [`Session`].
    ///
    /// This method blocks (asynchronously) until a new connection arrives,
    /// performs the Noise handshake and password verification, and then sets up
    /// all server-side subsystems (capture, encoder, input simulator).
    pub async fn accept_connection(&self) -> anyhow::Result<Arc<Session>> {
        if !self.listening.load(std::sync::atomic::Ordering::Relaxed) {
            anyhow::bail!("server is not listening");
        }

        info!("waiting for incoming connection...");

        // TODO: Accept a new QUIC connection from the listener.
        //
        // let stream = quic_server.accept().await?;

        // TODO: Perform Noise XX handshake (responder side).
        //
        // let noise = NoiseSession::responder(&keypair)?;
        // noise.handshake(&mut stream).await?;

        // TODO: Receive and verify LoginRequest.
        //
        // let login_req = read_login_request(&mut stream).await?;
        // let auth_ok = rdesk_crypto::auth::verify_password(
        //     &login_req.password_hash,
        //     &self.config.permanent_password,
        // );
        // if !auth_ok { bail!("authentication failed"); }

        // Build a session with all server-side subsystems attached.
        let session_id = format!(
            "server-{}-{}",
            &self.config.device_id,
            rand::random::<u32>(),
        );
        let mut session = Session::new(session_id);

        // Attach screen capturer.
        match capture::create_capturer() {
            Ok(capturer) => session.set_capturer(capturer),
            Err(e) => warn!("failed to create screen capturer: {}", e),
        }

        // Attach video encoder (raw/LZ4 for MVP).
        let encoder: Box<dyn codec::VideoEncoder> = Box::new(codec::vpx::RawEncoder::new());
        session.set_encoder(encoder);

        // Attach input simulator.
        match input::create_input_simulator() {
            Ok(sim) => session.set_input(sim),
            Err(e) => warn!("failed to create input simulator: {}", e),
        }

        session.start()?;
        session.activate()?;

        info!("new session accepted (stub connection)");

        // Track the session.
        let session = Arc::new(session);
        self.sessions.lock().await.push(session.clone());

        Ok(session)
    }

    /// Stop the server and disconnect all active sessions.
    pub async fn stop(&self) {
        info!(device_id = %self.config.device_id, "stopping remote desktop server");
        self.listening
            .store(false, std::sync::atomic::Ordering::Relaxed);

        let sessions = self.sessions.lock().await;
        for session in sessions.iter() {
            session.stop();
        }

        // TODO: Close the QUIC listener and deregister from the rendezvous server.
    }

    /// Return whether the server is currently listening.
    pub fn is_listening(&self) -> bool {
        self.listening.load(std::sync::atomic::Ordering::Relaxed)
    }

    /// Return the number of active sessions.
    pub async fn active_session_count(&self) -> usize {
        self.sessions.lock().await.len()
    }
}
