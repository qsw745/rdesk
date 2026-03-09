//! Controller (viewer) side logic.
//!
//! [`RemoteClient`] represents the *controller* end of a remote desktop
//! session -- the machine whose user is viewing and controlling a remote
//! host. It connects to a [`RemoteServer`](crate::server::RemoteServer) via the
//! signaling infrastructure in `rdesk_net`, performs authentication through
//! `rdesk_crypto`, and then streams decoded video frames while forwarding
//! input events.

use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::{info, warn, error};

use rdesk_common::config::AppConfig;
use rdesk_common::protos::message::{MouseEvent, KeyEvent, TouchEvent};

use crate::codec::{self, VideoDecoder, DecodedFrame};
use crate::session::{Session, SessionState};

/// Controller-side remote desktop client.
///
/// After construction via [`connect`](RemoteClient::connect) the client holds
/// an active [`Session`] and can begin receiving video frames and forwarding
/// input events to the remote host.
pub struct RemoteClient {
    /// The underlying session.
    session: Arc<Session>,

    /// Video decoder for incoming frames.
    decoder: Arc<Mutex<Box<dyn VideoDecoder>>>,

    /// Device ID of the remote peer.
    remote_device_id: String,
}

impl RemoteClient {
    /// Connect to a remote device.
    ///
    /// 1. Resolves the target device through the rendezvous server.
    /// 2. Establishes a QUIC connection (direct or relayed).
    /// 3. Performs the Noise protocol handshake and password authentication.
    /// 4. Returns a ready-to-use `RemoteClient`.
    pub async fn connect(
        device_id: &str,
        password: &str,
        config: &AppConfig,
    ) -> anyhow::Result<Self> {
        info!(
            remote_device = %device_id,
            signaling_server = %config.signaling_server,
            "initiating remote connection"
        );

        // --- 1. Resolve peer via rendezvous server ---------------------------
        // TODO: Use rdesk_net::RendezvousClient to fetch the peer's public key
        // and NAT type from the signaling server.
        //
        // let rendezvous = RendezvousClient::connect(&config.signaling_server).await?;
        // let peer_info = rendezvous.fetch_peer(device_id).await?;

        // --- 2. Establish QUIC connection ------------------------------------
        // TODO: Attempt direct P2P connection via UDP hole punching. Fall back
        // to relay if the NAT combination does not allow direct connectivity.
        //
        // let connection = match hole_punch::punch(...).await {
        //     Ok(addr) => QuicClient::connect(addr).await?,
        //     Err(_) => {
        //         let relay = RelayClient::connect(&config.relay_server).await?;
        //         relay.open_tunnel(device_id).await?
        //     }
        // };

        // --- 3. Noise handshake + auth ---------------------------------------
        // TODO: Run the Noise XX handshake over the QUIC stream, then send a
        // LoginRequest with the password hash.
        //
        // let noise = NoiseSession::initiator(&keypair)?;
        // noise.handshake(&mut stream).await?;
        // let login_resp = send_login_request(&mut stream, password).await?;
        // if !login_resp.success { bail!("authentication failed: {}", login_resp.error); }

        // --- 4. Build session ------------------------------------------------
        let session_id = format!("client-{}-{}", &config.device_id, device_id);
        let mut session = Session::new(session_id);
        session.set_decoder(Box::new(codec::vpx::RawDecoder::new()));
        session.start()?;
        session.activate()?;
        let session = Arc::new(session);

        let decoder = session
            .decoder()
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("decoder was not attached to session"))?;

        info!(remote_device = %device_id, "client session created (stub connection)");

        Ok(Self {
            session,
            decoder,
            remote_device_id: device_id.to_string(),
        })
    }

    /// Begin receiving and decoding video frames from the remote host.
    ///
    /// This spawns a background task that reads encoded frames from the network
    /// stream, decodes them, and makes the decoded RGBA data available for
    /// rendering.
    pub async fn start_viewing(&self) -> anyhow::Result<()> {
        info!(remote_device = %self.remote_device_id, "start viewing remote desktop");

        // TODO: Spawn a tokio task that:
        //   1. Reads VideoFrame messages from the QUIC stream.
        //   2. Decodes each frame via self.decoder.
        //   3. Pushes the DecodedFrame into a render queue / callback.
        //
        // let decoder = self.decoder.clone();
        // let session = self.session.clone();
        // tokio::spawn(async move {
        //     while session.get_state() == SessionState::Active {
        //         let encoded = read_video_frame(&mut stream).await?;
        //         let mut dec = decoder.lock().await;
        //         let frame = dec.decode(&encoded.data, encoded.key)?;
        //         render_callback(frame);
        //     }
        // });

        info!("viewing loop would start here (stub)");
        Ok(())
    }

    /// Send a mouse event to the remote host.
    pub fn send_mouse_event(&self, event: MouseEvent) {
        if self.session.get_state() != SessionState::Active {
            warn!("cannot send mouse event: session not active");
            return;
        }

        // TODO: Serialize the MouseEvent as a protobuf Message and send it
        // over the encrypted QUIC stream.
        //
        // let msg = Message { union: Some(Union::MouseEvent(event)) };
        // self.connection.send(msg).await;

        tracing::trace!(
            x = event.x,
            y = event.y,
            event_type = ?event.event_type,
            "sending mouse event (stub)"
        );
    }

    /// Send a keyboard event to the remote host.
    pub fn send_key_event(&self, event: KeyEvent) {
        if self.session.get_state() != SessionState::Active {
            warn!("cannot send key event: session not active");
            return;
        }

        // TODO: Serialize and send over the encrypted QUIC stream.
        tracing::trace!(
            key_code = event.key_code,
            down = event.down,
            "sending key event (stub)"
        );
    }

    /// Send a touch event to the remote host.
    pub fn send_touch_event(&self, event: TouchEvent) {
        if self.session.get_state() != SessionState::Active {
            warn!("cannot send touch event: session not active");
            return;
        }

        // TODO: Serialize and send over the encrypted QUIC stream.
        tracing::trace!(
            num_points = event.points.len(),
            event_type = ?event.event_type,
            "sending touch event (stub)"
        );
    }

    /// Return a reference to the underlying session.
    pub fn session(&self) -> &Arc<Session> {
        &self.session
    }

    /// Disconnect from the remote host.
    pub async fn disconnect(&self) {
        info!(remote_device = %self.remote_device_id, "disconnecting client");
        self.session.stop();
        // TODO: Send a CloseSession message and tear down the QUIC connection.
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
