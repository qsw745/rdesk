//! Session state machine.
//!
//! Manages the lifecycle of a single remote desktop connection from initial
//! connection through authentication, active streaming, and eventual
//! disconnection. The [`Session`] struct holds references to all subsystems
//! (capture, codec, input, clipboard, etc.) and coordinates their operation.

use std::sync::Arc;
use tokio::sync::{watch, Mutex};
use tracing::{info, warn};

use crate::capture::ScreenCapturer;
use crate::clipboard::ClipboardManager;
use crate::codec::{VideoDecoder, VideoEncoder};
use crate::input::InputSimulator;

/// States of a remote desktop session.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionState {
    /// TCP/QUIC connection is being established.
    Connecting,
    /// Cryptographic handshake and password verification in progress.
    Authenticating,
    /// Session is fully active -- media is streaming and input is accepted.
    Active,
    /// Session has ended (either cleanly or due to error).
    Disconnected,
}

impl std::fmt::Display for SessionState {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SessionState::Connecting => write!(f, "Connecting"),
            SessionState::Authenticating => write!(f, "Authenticating"),
            SessionState::Active => write!(f, "Active"),
            SessionState::Disconnected => write!(f, "Disconnected"),
        }
    }
}

/// A single remote desktop session.
///
/// The session owns (or holds shared references to) all subsystems required for
/// a remote connection: screen capture, video codec, input simulation, and
/// clipboard synchronisation. Higher-level code (client/server) creates and
/// drives the session through its state transitions.
pub struct Session {
    /// Unique identifier for this session.
    id: String,

    /// Current session state, observable via a watch channel.
    state_tx: watch::Sender<SessionState>,
    state_rx: watch::Receiver<SessionState>,

    /// Screen capturer (server-side only; `None` on the client).
    capturer: Option<Arc<Mutex<Box<dyn ScreenCapturer>>>>,

    /// Video encoder (server-side).
    encoder: Option<Arc<Mutex<Box<dyn VideoEncoder>>>>,

    /// Video decoder (client-side).
    decoder: Option<Arc<Mutex<Box<dyn VideoDecoder>>>>,

    /// Input simulator (server-side).
    input: Option<Arc<Mutex<Box<dyn InputSimulator>>>>,

    /// Clipboard manager shared across both sides.
    clipboard: Option<Arc<Mutex<ClipboardManager>>>,
}

impl Session {
    /// Create a new session in the [`SessionState::Connecting`] state.
    pub fn new(id: String) -> Self {
        let (state_tx, state_rx) = watch::channel(SessionState::Connecting);
        info!(session_id = %id, "session created");
        Self {
            id,
            state_tx,
            state_rx,
            capturer: None,
            encoder: None,
            decoder: None,
            input: None,
            clipboard: None,
        }
    }

    /// Return the session identifier.
    pub fn id(&self) -> &str {
        &self.id
    }

    // --- Subsystem setters ---------------------------------------------------

    /// Attach a screen capturer to this session (server-side).
    pub fn set_capturer(&mut self, capturer: Box<dyn ScreenCapturer>) {
        self.capturer = Some(Arc::new(Mutex::new(capturer)));
    }

    /// Attach a video encoder (server-side).
    pub fn set_encoder(&mut self, encoder: Box<dyn VideoEncoder>) {
        self.encoder = Some(Arc::new(Mutex::new(encoder)));
    }

    /// Attach a video decoder (client-side).
    pub fn set_decoder(&mut self, decoder: Box<dyn VideoDecoder>) {
        self.decoder = Some(Arc::new(Mutex::new(decoder)));
    }

    /// Attach an input simulator (server-side).
    pub fn set_input(&mut self, input: Box<dyn InputSimulator>) {
        self.input = Some(Arc::new(Mutex::new(input)));
    }

    /// Attach a clipboard manager.
    pub fn set_clipboard(&mut self, clipboard: ClipboardManager) {
        self.clipboard = Some(Arc::new(Mutex::new(clipboard)));
    }

    // --- Subsystem accessors -------------------------------------------------

    pub fn capturer(&self) -> Option<&Arc<Mutex<Box<dyn ScreenCapturer>>>> {
        self.capturer.as_ref()
    }

    pub fn encoder(&self) -> Option<&Arc<Mutex<Box<dyn VideoEncoder>>>> {
        self.encoder.as_ref()
    }

    pub fn decoder(&self) -> Option<&Arc<Mutex<Box<dyn VideoDecoder>>>> {
        self.decoder.as_ref()
    }

    pub fn input(&self) -> Option<&Arc<Mutex<Box<dyn InputSimulator>>>> {
        self.input.as_ref()
    }

    pub fn clipboard(&self) -> Option<&Arc<Mutex<ClipboardManager>>> {
        self.clipboard.as_ref()
    }

    // --- State management ----------------------------------------------------

    /// Return the current session state.
    pub fn get_state(&self) -> SessionState {
        *self.state_rx.borrow()
    }

    /// Subscribe to state changes. The returned receiver will yield the new
    /// state each time it changes.
    pub fn subscribe_state(&self) -> watch::Receiver<SessionState> {
        self.state_rx.clone()
    }

    /// Transition to a new state. Logs the transition and notifies watchers.
    fn set_state(&self, new_state: SessionState) {
        let old = *self.state_rx.borrow();
        if old != new_state {
            info!(
                session_id = %self.id,
                from = %old,
                to = %new_state,
                "session state transition"
            );
            let _ = self.state_tx.send(new_state);
        }
    }

    /// Start the session, transitioning from `Connecting` -> `Authenticating`.
    ///
    /// In a full implementation this would kick off the cryptographic handshake
    /// over the established connection.
    pub fn start(&self) -> anyhow::Result<()> {
        let current = self.get_state();
        if current != SessionState::Connecting {
            anyhow::bail!(
                "cannot start session: expected Connecting state, got {}",
                current,
            );
        }
        self.set_state(SessionState::Authenticating);
        // TODO: Begin Noise protocol handshake via rdesk_crypto::NoiseSession.
        Ok(())
    }

    /// Mark the session as fully active (after successful authentication).
    pub fn activate(&self) -> anyhow::Result<()> {
        let current = self.get_state();
        if current != SessionState::Authenticating {
            anyhow::bail!(
                "cannot activate session: expected Authenticating state, got {}",
                current,
            );
        }
        self.set_state(SessionState::Active);
        info!(session_id = %self.id, "session is now active");
        Ok(())
    }

    /// Stop the session, transitioning to `Disconnected` from any state.
    pub fn stop(&self) {
        let current = self.get_state();
        if current != SessionState::Disconnected {
            warn!(session_id = %self.id, from = %current, "session stopping");
            self.set_state(SessionState::Disconnected);
        }
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        if self.get_state() != SessionState::Disconnected {
            self.stop();
        }
    }
}
