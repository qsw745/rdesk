//! Encrypted control channel: Noise XX over a QUIC bidirectional stream.
//!
//! QUIC/TLS authenticates the *server endpoint* and encrypts the wire; the
//! Noise layer on top authenticates the *peers* to each other and gives every
//! session a fresh handshake hash usable for channel binding.
//!
//! The handshake is driven here rather than through
//! [`rdesk_crypto::noise::complete_handshake_initiator`] and its responder twin:
//! those take synchronous `FnMut` closures for I/O, which cannot `.await` a QUIC
//! stream. The buffer-level primitives (`handshake_write` / `handshake_read`) do
//! no I/O of their own, so they compose cleanly with async transport.

use anyhow::{Context, Result};
use prost::Message as _;
use tracing::debug;

use rdesk_common::protos::message::Message;
use rdesk_crypto::keypair::KeyPair;
use rdesk_crypto::{noise, NoiseSession};
use rdesk_net::quic::stream::{recv_message, send_message, RecvStream, SendStream};

/// Snow's internal buffer size; a Noise transport message cannot exceed it.
const NOISE_MAX_MESSAGE_LEN: usize = 65535;

/// Largest plaintext that still fits once the 16-byte AEAD tag is added.
const MAX_PLAINTEXT_LEN: usize = NOISE_MAX_MESSAGE_LEN - 16;

/// A Noise-encrypted, length-delimited message channel over one QUIC stream.
pub struct SecureChannel {
    send: SendStream,
    recv: RecvStream,
    noise: NoiseSession,
}

impl SecureChannel {
    /// Run the XX handshake as the initiator (the connecting side).
    pub async fn initiator(keypair: &KeyPair, send: SendStream, recv: RecvStream) -> Result<Self> {
        let mut state = noise::build_initiator(keypair.private_key())
            .context("failed to build Noise initiator state")?;
        let mut send = send;
        let mut recv = recv;
        let mut buf = vec![0u8; NOISE_MAX_MESSAGE_LEN];
        let mut payload = vec![0u8; NOISE_MAX_MESSAGE_LEN];

        // 1. initiator -> responder: e
        let len = noise::handshake_write(&mut state, &[], &mut buf)
            .context("failed to write Noise message 1")?;
        send_message(&mut send, &buf[..len])
            .await
            .context("failed to send Noise message 1")?;

        // 2. responder -> initiator: e, ee, s, es
        let msg2 = recv_message(&mut recv)
            .await
            .context("failed to receive Noise message 2")?;
        noise::handshake_read(&mut state, &msg2, &mut payload)
            .context("failed to read Noise message 2")?;

        // 3. initiator -> responder: s, se
        let len = noise::handshake_write(&mut state, &[], &mut buf)
            .context("failed to write Noise message 3")?;
        send_message(&mut send, &buf[..len])
            .await
            .context("failed to send Noise message 3")?;

        let noise = NoiseSession::from_handshake(state)
            .context("Noise initiator failed to enter transport mode")?;
        debug!("Noise initiator handshake complete");

        Ok(Self { send, recv, noise })
    }

    /// Run the XX handshake as the responder (the accepting side).
    pub async fn responder(keypair: &KeyPair, send: SendStream, recv: RecvStream) -> Result<Self> {
        let mut state = noise::build_responder(keypair.private_key())
            .context("failed to build Noise responder state")?;
        let mut send = send;
        let mut recv = recv;
        let mut buf = vec![0u8; NOISE_MAX_MESSAGE_LEN];
        let mut payload = vec![0u8; NOISE_MAX_MESSAGE_LEN];

        // 1. initiator -> responder: e
        let msg1 = recv_message(&mut recv)
            .await
            .context("failed to receive Noise message 1")?;
        noise::handshake_read(&mut state, &msg1, &mut payload)
            .context("failed to read Noise message 1")?;

        // 2. responder -> initiator: e, ee, s, es
        let len = noise::handshake_write(&mut state, &[], &mut buf)
            .context("failed to write Noise message 2")?;
        send_message(&mut send, &buf[..len])
            .await
            .context("failed to send Noise message 2")?;

        // 3. initiator -> responder: s, se
        let msg3 = recv_message(&mut recv)
            .await
            .context("failed to receive Noise message 3")?;
        noise::handshake_read(&mut state, &msg3, &mut payload)
            .context("failed to read Noise message 3")?;

        let noise = NoiseSession::from_handshake(state)
            .context("Noise responder failed to enter transport mode")?;
        debug!("Noise responder handshake complete");

        Ok(Self { send, recv, noise })
    }

    /// The Noise handshake hash for this session.
    ///
    /// Identical on both ends, different for every session. See
    /// [`NoiseSession::handshake_hash`] for how to use it as a channel binding.
    pub fn handshake_hash(&self) -> &[u8] {
        self.noise.handshake_hash()
    }

    /// The peer's Noise static public key, learned during the handshake.
    pub fn remote_static(&self) -> Option<&[u8]> {
        self.noise.get_remote_static()
    }

    /// Encrypt and send a protobuf [`Message`].
    pub async fn send(&mut self, message: &Message) -> Result<()> {
        let plaintext = message.encode_to_vec();
        if plaintext.len() > MAX_PLAINTEXT_LEN {
            // Noise frames top out at 64 KiB. Bulk payloads (video, file blocks)
            // need chunking on their own stream rather than a bigger frame here.
            anyhow::bail!(
                "control message of {} bytes exceeds the {} byte Noise frame limit",
                plaintext.len(),
                MAX_PLAINTEXT_LEN
            );
        }

        let ciphertext = self
            .noise
            .encrypt(&plaintext)
            .context("failed to encrypt control message")?;
        send_message(&mut self.send, &ciphertext)
            .await
            .context("failed to send control message")
    }

    /// Receive and decrypt a protobuf [`Message`].
    pub async fn recv(&mut self) -> Result<Message> {
        let ciphertext = recv_message(&mut self.recv)
            .await
            .context("failed to receive control message")?;
        let plaintext = self
            .noise
            .decrypt(&ciphertext)
            .context("failed to decrypt control message")?;
        Message::decode(plaintext.as_slice()).context("failed to decode control message")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    use rdesk_common::protos::message::{message::Union, ChatMessage};
    use rdesk_crypto::keypair::generate_keypair;
    use rdesk_net::{QuicClient, QuicServer, ServerCertificate, ServerVerification};

    const RELAY_NAME: &str = "host.rdesk.test";

    /// Establish a client/server QUIC connection over loopback with full
    /// certificate verification, and return both ends of a control stream.
    async fn connected_pair() -> (SecureChannel, SecureChannel) {
        let server = QuicServer::bind(
            "127.0.0.1:0".parse().unwrap(),
            ServerCertificate::self_signed([RELAY_NAME]),
        )
        .expect("bind QUIC server");
        let addr = server.local_addr().unwrap();
        let anchor = server.self_signed_anchor().unwrap().clone();

        let host = tokio::spawn(async move {
            let conn = server.accept().await.expect("accept QUIC connection");
            let (_kind, send, recv) = conn.accept_stream().await.expect("accept control stream");
            let keypair = generate_keypair();
            SecureChannel::responder(&keypair, send, recv)
                .await
                .expect("responder handshake")
        });

        let client = QuicClient::with_verification(ServerVerification::CustomRoots(vec![anchor]))
            .expect("build QUIC client");
        let conn = client
            .connect(addr, RELAY_NAME)
            .await
            .expect("QUIC connection");
        let (send, recv) = conn
            .open_control_stream()
            .await
            .expect("open control stream");
        let keypair = generate_keypair();
        let controller = SecureChannel::initiator(&keypair, send, recv)
            .await
            .expect("initiator handshake");

        (controller, host.await.expect("host task"))
    }

    fn chat(content: &str) -> Message {
        Message {
            union: Some(Union::ChatMessage(ChatMessage {
                sender: "test".to_string(),
                content: content.to_string(),
                timestamp: 0,
            })),
        }
    }

    #[tokio::test]
    async fn both_ends_agree_on_the_handshake_hash() {
        let (controller, host) = connected_pair().await;

        assert!(!controller.handshake_hash().is_empty());
        assert_eq!(
            controller.handshake_hash(),
            host.handshake_hash(),
            "channel binding is worthless if the two ends disagree"
        );
    }

    #[tokio::test]
    async fn each_session_gets_a_distinct_handshake_hash() {
        let (first, _) = connected_pair().await;
        let (second, _) = connected_pair().await;

        assert_ne!(
            first.handshake_hash(),
            second.handshake_hash(),
            "a repeated handshake hash would let an auth response be replayed"
        );
    }

    #[tokio::test]
    async fn each_end_learns_the_other_static_key() {
        let (controller, host) = connected_pair().await;

        let seen_by_host = host.remote_static().expect("host learns controller key");
        let seen_by_controller = controller
            .remote_static()
            .expect("controller learns host key");
        assert_ne!(seen_by_host, seen_by_controller);
    }

    #[tokio::test]
    async fn messages_round_trip_in_both_directions() {
        let (mut controller, mut host) = connected_pair().await;

        controller.send(&chat("ping")).await.expect("send ping");
        let received = host.recv().await.expect("receive ping");
        assert!(matches!(
            received.union,
            Some(Union::ChatMessage(ref m)) if m.content == "ping"
        ));

        host.send(&chat("pong")).await.expect("send pong");
        let received = controller.recv().await.expect("receive pong");
        assert!(matches!(
            received.union,
            Some(Union::ChatMessage(ref m)) if m.content == "pong"
        ));
    }

    #[tokio::test]
    async fn oversized_control_messages_are_refused_before_encryption() {
        let (mut controller, _host) = connected_pair().await;

        let err = controller
            .send(&chat(&"x".repeat(MAX_PLAINTEXT_LEN + 1)))
            .await
            .expect_err("a message past the Noise frame limit must be refused");
        assert!(
            err.to_string().contains("Noise frame limit"),
            "got: {err:#}"
        );
    }
}
