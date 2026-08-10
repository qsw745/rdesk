//! Controller (viewer) side logic.
//!
//! [`RemoteClient`] represents the *controller* end of a remote desktop
//! session -- the machine whose user is viewing and controlling a remote
//! host. It connects to a [`RemoteServer`](crate::server::RemoteServer) over
//! QUIC, performs a Noise handshake and password authentication, and then
//! forwards input events to the host.

use std::net::SocketAddr;
use std::sync::Arc;
use tokio::sync::{mpsc, Mutex};
use tracing::{error, info, warn};

use rdesk_common::config::AppConfig;
use rdesk_common::platform::platform_name;
use rdesk_common::protos::message::{
    message::Union, KeyEvent, LoginRequest, Message, MouseEvent, TouchEvent,
};
use rdesk_crypto::keypair::generate_keypair;
use rdesk_net::{QuicClient, ServerVerification};

use crate::codec::{self, VideoDecoder};
use crate::session::{Session, SessionState};
use crate::transport::SecureChannel;

/// Version string reported to the host in [`LoginRequest`].
const CLIENT_VERSION: &str = env!("CARGO_PKG_VERSION");

/// Where and how to reach a host directly, without going through signaling.
#[derive(Debug, Clone)]
pub struct DirectTarget {
    /// The host's QUIC socket address.
    pub addr: SocketAddr,
    /// The name the host's certificate must be valid for.
    pub server_name: String,
    /// How to verify that certificate. Defaults to full public-PKI verification.
    pub verification: ServerVerification,
}

impl DirectTarget {
    /// Target `addr`, expecting a publicly-trusted certificate for `server_name`.
    pub fn new(addr: SocketAddr, server_name: impl Into<String>) -> Self {
        Self {
            addr,
            server_name: server_name.into(),
            verification: ServerVerification::WebPki,
        }
    }

    /// Verify against an explicit trust anchor instead of the public root store.
    pub fn with_verification(mut self, verification: ServerVerification) -> Self {
        self.verification = verification;
        self
    }
}

/// Controller-side remote desktop client.
pub struct RemoteClient {
    /// The underlying session.
    session: Arc<Session>,

    /// Video decoder for incoming frames.
    decoder: Arc<Mutex<Box<dyn VideoDecoder>>>,

    /// Device ID of the remote peer.
    remote_device_id: String,

    /// Outbound control messages, drained by a background task that owns the
    /// encrypted channel. This keeps the input-forwarding methods synchronous,
    /// which is what the `rdesk_bridge` FFI layer calls them from.
    outbound: mpsc::UnboundedSender<Message>,
}

impl RemoteClient {
    /// Connect to a remote device by device ID, via the rendezvous server.
    ///
    /// Not implemented: this needs the signaling and hole-punching path, which
    /// is still stubbed out in `rdesk_net::rendezvous` and `rdesk_net::p2p`.
    /// Use [`connect_direct`](Self::connect_direct) when the host's address is
    /// already known.
    pub async fn connect(
        device_id: &str,
        _password: &str,
        config: &AppConfig,
    ) -> anyhow::Result<Self> {
        info!(
            remote_device = %device_id,
            signaling_server = %config.signaling_server,
            "initiating remote connection"
        );

        anyhow::bail!(
            "connecting by device ID needs the rendezvous server to resolve {device_id} to an \
             address, and rdesk_net::rendezvous is still a stub. Use \
             RemoteClient::connect_direct() with a known host address."
        )
    }

    /// Connect directly to a host whose address is already known.
    ///
    /// Establishes QUIC, runs the Noise XX handshake, authenticates with
    /// `password`, and returns a client whose session is `Active`.
    pub async fn connect_direct(
        target: DirectTarget,
        password: &str,
        config: &AppConfig,
    ) -> anyhow::Result<Self> {
        info!(
            addr = %target.addr,
            server_name = %target.server_name,
            "connecting to host over QUIC"
        );

        // --- 1. QUIC connection ---------------------------------------------
        let quic = QuicClient::with_verification(target.verification)?;
        let connection = quic.connect(target.addr, &target.server_name).await?;

        // --- 2. Noise XX handshake over the control stream -------------------
        // The Noise static key is generated per connection. Persisting it (see
        // rdesk_crypto::keypair::{save_keypair, load_keypair}) is what would let
        // a host recognise a returning controller; nothing depends on that yet.
        let keypair = generate_keypair();
        let (send, recv) = connection.open_control_stream().await?;
        let mut channel = SecureChannel::initiator(&keypair, send, recv).await?;

        // --- 3. Password authentication --------------------------------------
        let session_id = format!("client-{}-{}", config.device_id, rand::random::<u32>());
        let session = Arc::new(Session::new(session_id));
        session.start()?;

        let login = LoginRequest {
            username: config.device_id.clone(),
            // Sent inside the Noise channel; the host verifies it with Argon2.
            password: password.to_string(),
            client_version: CLIENT_VERSION.to_string(),
            supported_codecs: vec!["raw".to_string()],
            os_type: platform_name().to_string(),
        };
        channel
            .send(&Message {
                union: Some(Union::LoginRequest(login)),
            })
            .await?;

        let response = match channel.recv().await?.union {
            Some(Union::LoginResponse(resp)) => resp,
            other => {
                session.stop();
                anyhow::bail!("expected a LoginResponse from the host, got {other:?}");
            }
        };

        if !response.success {
            session.stop();
            // The host deliberately keeps this reason vague.
            anyhow::bail!("authentication rejected by host: {}", response.error);
        }

        session.activate()?;
        info!(
            session_id = session.id(),
            codec = %response.selected_codec,
            "remote session authenticated and active"
        );

        // --- 4. Outbound pump -------------------------------------------------
        let (outbound, mut rx) = mpsc::unbounded_channel::<Message>();
        let pump_session = session.clone();
        tokio::spawn(async move {
            while let Some(message) = rx.recv().await {
                if let Err(e) = channel.send(&message).await {
                    error!(error = %e, "control channel send failed; ending session");
                    pump_session.stop();
                    return;
                }
            }
            // Sender dropped: the client is gone.
            pump_session.stop();
        });

        Ok(Self {
            session,
            decoder: Arc::new(Mutex::new(
                Box::new(codec::vpx::RawDecoder::new()) as Box<dyn VideoDecoder>
            )),
            remote_device_id: target.server_name,
            outbound,
        })
    }

    /// Begin receiving and decoding video frames from the remote host.
    ///
    /// Not implemented: video arrives on its own QUIC stream, which nothing
    /// opens yet. The decoder is wired up and ready for it.
    pub async fn start_viewing(&self) -> anyhow::Result<()> {
        info!(remote_device = %self.remote_device_id, "start viewing remote desktop");

        // TODO: Open/accept the video stream, read VideoFrame messages, decode
        // via self.decoder, and hand DecodedFrames to a render callback.
        warn!("video streaming is not wired up yet; no frames will arrive");
        Ok(())
    }

    /// Queue a mouse event for delivery to the remote host.
    pub fn send_mouse_event(&self, event: MouseEvent) {
        self.enqueue(Union::MouseEvent(event), "mouse");
    }

    /// Queue a keyboard event for delivery to the remote host.
    pub fn send_key_event(&self, event: KeyEvent) {
        self.enqueue(Union::KeyEvent(event), "key");
    }

    /// Queue a touch event for delivery to the remote host.
    pub fn send_touch_event(&self, event: TouchEvent) {
        self.enqueue(Union::TouchEvent(event), "touch");
    }

    /// Hand a message to the outbound pump, dropping it if the session is not
    /// active or the pump has stopped.
    fn enqueue(&self, union: Union, kind: &str) {
        if self.session.get_state() != SessionState::Active {
            warn!(kind, "cannot send input event: session not active");
            return;
        }
        if self.outbound.send(Message { union: Some(union) }).is_err() {
            warn!(kind, "control channel closed; dropping input event");
            self.session.stop();
        }
    }

    /// Return a reference to the underlying session.
    pub fn session(&self) -> &Arc<Session> {
        &self.session
    }

    /// Return the video decoder for this session.
    pub fn decoder(&self) -> &Arc<Mutex<Box<dyn VideoDecoder>>> {
        &self.decoder
    }

    /// Disconnect from the remote host.
    pub async fn disconnect(&self) {
        info!(remote_device = %self.remote_device_id, "disconnecting client");
        self.session.stop();
        // Dropping the last sender ends the pump task, which closes the stream.
    }
}

impl Drop for RemoteClient {
    fn drop(&mut self) {
        if self.session.get_state() != SessionState::Disconnected {
            error!("RemoteClient dropped without calling disconnect()");
            self.session.stop();
        }
    }
}
