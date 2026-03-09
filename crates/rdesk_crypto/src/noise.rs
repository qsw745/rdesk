//! Noise Protocol implementation using the XX handshake pattern.
//!
//! The XX pattern is a three-message handshake where both sides transmit their
//! static keys during the handshake. This is suitable for remote desktop scenarios
//! where neither party knows the other's public key in advance.
//!
//! Pattern: `Noise_XX_25519_ChaChaPoly_SHA256`
//!
//! Message flow:
//!   1. Initiator -> Responder: e
//!   2. Responder -> Initiator: e, ee, s, es
//!   3. Initiator -> Responder: s, se

use snow::{Builder, HandshakeState, TransportState};
use tracing::{debug, trace};

use crate::{CryptoError, Result};

/// The Noise protocol pattern string used for all sessions.
const NOISE_PATTERN: &str = "Noise_XX_25519_ChaChaPoly_SHA256";

/// Maximum size of a Noise transport message (plaintext + 16-byte AEAD tag).
/// Snow uses a 65535-byte internal buffer by default.
const MAX_MESSAGE_LEN: usize = 65535;

/// Wraps a fully established `snow::TransportState` and provides
/// convenient encrypt / decrypt methods.
pub struct NoiseSession {
    transport: TransportState,
}

impl NoiseSession {
    /// Wrap an already-transitioned `TransportState`.
    pub fn new(transport: TransportState) -> Self {
        Self { transport }
    }

    /// Encrypt `plaintext` and return the ciphertext (includes 16-byte AEAD tag).
    pub fn encrypt(&mut self, plaintext: &[u8]) -> Result<Vec<u8>> {
        let mut buf = vec![0u8; plaintext.len() + 16];
        let len = self
            .transport
            .write_message(plaintext, &mut buf)
            .map_err(|e| CryptoError::Encryption(format!("noise encrypt failed: {e}")))?;
        buf.truncate(len);
        trace!(plaintext_len = plaintext.len(), ciphertext_len = len, "encrypted message");
        Ok(buf)
    }

    /// Decrypt `ciphertext` and return the plaintext.
    pub fn decrypt(&mut self, ciphertext: &[u8]) -> Result<Vec<u8>> {
        let mut buf = vec![0u8; ciphertext.len()];
        let len = self
            .transport
            .read_message(ciphertext, &mut buf)
            .map_err(|e| CryptoError::Decryption(format!("noise decrypt failed: {e}")))?;
        buf.truncate(len);
        trace!(ciphertext_len = ciphertext.len(), plaintext_len = len, "decrypted message");
        Ok(buf)
    }

    /// Return the remote peer's static public key, if available.
    pub fn get_remote_static(&self) -> Option<&[u8]> {
        self.transport.get_remote_static()
    }
}

// ---------------------------------------------------------------------------
// Handshake builders
// ---------------------------------------------------------------------------

/// Build an initiator `HandshakeState` using the XX pattern.
///
/// `local_private_key` must be a 32-byte X25519 private key.
pub fn build_initiator(local_private_key: &[u8]) -> Result<HandshakeState> {
    validate_key_length(local_private_key)?;
    let builder = Builder::new(NOISE_PATTERN.parse().map_err(|_| {
        CryptoError::Handshake("failed to parse noise pattern".into())
    })?)
    .local_private_key(local_private_key);

    let state = builder
        .build_initiator()
        .map_err(|e| CryptoError::Handshake(format!("failed to build initiator state: {e}")))?;

    debug!("built Noise XX initiator handshake state");
    Ok(state)
}

/// Build a responder `HandshakeState` using the XX pattern.
///
/// `local_private_key` must be a 32-byte X25519 private key.
pub fn build_responder(local_private_key: &[u8]) -> Result<HandshakeState> {
    validate_key_length(local_private_key)?;
    let builder = Builder::new(NOISE_PATTERN.parse().map_err(|_| {
        CryptoError::Handshake("failed to parse noise pattern".into())
    })?)
    .local_private_key(local_private_key);

    let state = builder
        .build_responder()
        .map_err(|e| CryptoError::Handshake(format!("failed to build responder state: {e}")))?;

    debug!("built Noise XX responder handshake state");
    Ok(state)
}

// ---------------------------------------------------------------------------
// XX three-message handshake helpers
// ---------------------------------------------------------------------------

/// Send a handshake message (write into `buf`).
///
/// `payload` can be empty for pure key-exchange messages.
/// Returns the number of bytes written into `buf`.
pub fn handshake_write(
    state: &mut HandshakeState,
    payload: &[u8],
    buf: &mut [u8],
) -> Result<usize> {
    let len = state
        .write_message(payload, buf)
        .map_err(|e| CryptoError::Handshake(format!("handshake write failed: {e}")))?;
    trace!(payload_len = payload.len(), msg_len = len, "handshake write");
    Ok(len)
}

/// Receive a handshake message (read from `message` into `payload_buf`).
///
/// Returns the number of payload bytes read.
pub fn handshake_read(
    state: &mut HandshakeState,
    message: &[u8],
    payload_buf: &mut [u8],
) -> Result<usize> {
    let len = state
        .read_message(message, payload_buf)
        .map_err(|e| CryptoError::Handshake(format!("handshake read failed: {e}")))?;
    trace!(msg_len = message.len(), payload_len = len, "handshake read");
    Ok(len)
}

/// Drive a complete XX handshake for the **initiator** side.
///
/// `send_fn` is called whenever the initiator needs to transmit a message.
/// `recv_fn` is called whenever the initiator needs to receive a message.
///
/// Returns a `NoiseSession` ready for encrypted transport.
pub fn complete_handshake_initiator<S, R>(
    state: HandshakeState,
    mut send_fn: S,
    mut recv_fn: R,
) -> Result<NoiseSession>
where
    S: FnMut(&[u8]) -> Result<()>,
    R: FnMut() -> Result<Vec<u8>>,
{
    let mut state = state;
    let mut buf = vec![0u8; MAX_MESSAGE_LEN];

    // Message 1: initiator -> responder  (e)
    let len = handshake_write(&mut state, &[], &mut buf)?;
    send_fn(&buf[..len])?;
    debug!("initiator sent handshake message 1");

    // Message 2: responder -> initiator  (e, ee, s, es)
    let msg2 = recv_fn()?;
    let mut payload_buf = vec![0u8; MAX_MESSAGE_LEN];
    let _payload_len = handshake_read(&mut state, &msg2, &mut payload_buf)?;
    debug!("initiator received handshake message 2");

    // Message 3: initiator -> responder  (s, se)
    let len = handshake_write(&mut state, &[], &mut buf)?;
    send_fn(&buf[..len])?;
    debug!("initiator sent handshake message 3");

    // Transition to transport mode.
    let transport = state
        .into_transport_mode()
        .map_err(|e| CryptoError::Handshake(format!("failed to enter transport mode: {e}")))?;

    debug!("initiator handshake complete, transport mode active");
    Ok(NoiseSession::new(transport))
}

/// Drive a complete XX handshake for the **responder** side.
///
/// `send_fn` is called whenever the responder needs to transmit a message.
/// `recv_fn` is called whenever the responder needs to receive a message.
///
/// Returns a `NoiseSession` ready for encrypted transport.
pub fn complete_handshake_responder<S, R>(
    state: HandshakeState,
    mut send_fn: S,
    mut recv_fn: R,
) -> Result<NoiseSession>
where
    S: FnMut(&[u8]) -> Result<()>,
    R: FnMut() -> Result<Vec<u8>>,
{
    let mut state = state;
    let mut buf = vec![0u8; MAX_MESSAGE_LEN];

    // Message 1: initiator -> responder  (e)
    let msg1 = recv_fn()?;
    let mut payload_buf = vec![0u8; MAX_MESSAGE_LEN];
    let _payload_len = handshake_read(&mut state, &msg1, &mut payload_buf)?;
    debug!("responder received handshake message 1");

    // Message 2: responder -> initiator  (e, ee, s, es)
    let len = handshake_write(&mut state, &[], &mut buf)?;
    send_fn(&buf[..len])?;
    debug!("responder sent handshake message 2");

    // Message 3: initiator -> responder  (s, se)
    let msg3 = recv_fn()?;
    let _payload_len = handshake_read(&mut state, &msg3, &mut payload_buf)?;
    debug!("responder received handshake message 3");

    // Transition to transport mode.
    let transport = state
        .into_transport_mode()
        .map_err(|e| CryptoError::Handshake(format!("failed to enter transport mode: {e}")))?;

    debug!("responder handshake complete, transport mode active");
    Ok(NoiseSession::new(transport))
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn validate_key_length(key: &[u8]) -> Result<()> {
    if key.len() != 32 {
        return Err(CryptoError::InvalidKey(format!(
            "expected 32-byte key, got {} bytes",
            key.len()
        )));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::VecDeque;
    use std::sync::{Arc, Mutex};

    /// In-memory channel for testing handshakes without real I/O.
    fn make_channel() -> (
        impl FnMut(&[u8]) -> Result<()>,
        impl FnMut() -> Result<Vec<u8>>,
    ) {
        let queue: Arc<Mutex<VecDeque<Vec<u8>>>> = Arc::new(Mutex::new(VecDeque::new()));
        let q_send = Arc::clone(&queue);
        let q_recv = queue;

        let send = move |data: &[u8]| -> Result<()> {
            q_send.lock().unwrap().push_back(data.to_vec());
            Ok(())
        };
        let recv = move || -> Result<Vec<u8>> {
            q_recv
                .lock()
                .unwrap()
                .pop_front()
                .ok_or_else(|| CryptoError::Handshake("channel empty".into()))
        };
        (send, recv)
    }

    #[test]
    fn test_full_handshake_and_transport() {
        // Generate two keypairs.
        let initiator_key = crate::keypair::generate_keypair();
        let responder_key = crate::keypair::generate_keypair();

        // Shared queues: initiator->responder and responder->initiator.
        let (i_send, r_recv) = make_channel();
        let (r_send, i_recv) = make_channel();

        let i_state = build_initiator(initiator_key.private_key()).unwrap();
        let r_state = build_responder(responder_key.private_key()).unwrap();

        // Run both sides of the handshake on the same thread, interleaving
        // manually since our channel is synchronous.
        //
        // The XX pattern has 3 messages, so we step through them.
        let mut i_hs = i_state;
        let mut r_hs = r_state;
        let mut buf = vec![0u8; MAX_MESSAGE_LEN];
        let mut payload_buf = vec![0u8; MAX_MESSAGE_LEN];

        // Msg 1: I -> R
        let len = handshake_write(&mut i_hs, &[], &mut buf).unwrap();
        let msg1 = buf[..len].to_vec();
        let _ = handshake_read(&mut r_hs, &msg1, &mut payload_buf).unwrap();

        // Msg 2: R -> I
        let len = handshake_write(&mut r_hs, &[], &mut buf).unwrap();
        let msg2 = buf[..len].to_vec();
        let _ = handshake_read(&mut i_hs, &msg2, &mut payload_buf).unwrap();

        // Msg 3: I -> R
        let len = handshake_write(&mut i_hs, &[], &mut buf).unwrap();
        let msg3 = buf[..len].to_vec();
        let _ = handshake_read(&mut r_hs, &msg3, &mut payload_buf).unwrap();

        // Transition to transport.
        let mut i_session = NoiseSession::new(i_hs.into_transport_mode().unwrap());
        let mut r_session = NoiseSession::new(r_hs.into_transport_mode().unwrap());

        // Test encrypt/decrypt round-trip.
        let plaintext = b"Hello, remote desktop!";
        let ciphertext = i_session.encrypt(plaintext).unwrap();
        let decrypted = r_session.decrypt(&ciphertext).unwrap();
        assert_eq!(plaintext.as_slice(), decrypted.as_slice());

        // Test the reverse direction.
        let plaintext2 = b"Response from responder";
        let ciphertext2 = r_session.encrypt(plaintext2).unwrap();
        let decrypted2 = i_session.decrypt(&ciphertext2).unwrap();
        assert_eq!(plaintext2.as_slice(), decrypted2.as_slice());
    }

    #[test]
    fn test_invalid_key_length() {
        let short_key = vec![0u8; 16];
        assert!(build_initiator(&short_key).is_err());
        assert!(build_responder(&short_key).is_err());
    }
}
