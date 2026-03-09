//! QUIC stream management.
//!
//! Provides a [`QuicConnection`] wrapper around [`quinn::Connection`] with
//! multiplexed named streams (control, video, file, chat) and length-delimited
//! message framing.

use anyhow::{anyhow, Context, Result};
use quinn::{Connection, RecvStream, SendStream};
use tracing::{debug, trace};

/// Maximum message size: 16 MB. Prevents allocating unbounded buffers.
const MAX_MESSAGE_SIZE: u32 = 16 * 1024 * 1024;

/// Length prefix size in bytes (u32 big-endian).
const LENGTH_PREFIX_SIZE: usize = 4;

/// Stream type identifier sent as the first byte on each new stream so the
/// receiver can route it appropriately.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum StreamType {
    /// Control channel (session management, settings, heartbeat).
    Control = 0,
    /// Video/audio media data.
    Video = 1,
    /// File transfer data.
    File = 2,
    /// Chat messages.
    Chat = 3,
}

impl StreamType {
    /// Convert from byte, returning `None` for unknown values.
    pub fn from_u8(v: u8) -> Option<Self> {
        match v {
            0 => Some(StreamType::Control),
            1 => Some(StreamType::Video),
            2 => Some(StreamType::File),
            3 => Some(StreamType::Chat),
            _ => None,
        }
    }
}

/// Wrapper around a [`quinn::Connection`] providing multiplexed stream
/// management and message framing.
pub struct QuicConnection {
    connection: Connection,
}

impl QuicConnection {
    /// Wrap an established QUIC connection.
    pub fn new(connection: Connection) -> Self {
        Self { connection }
    }

    /// Open a new bidirectional stream tagged as a **control** stream.
    pub async fn open_control_stream(&self) -> Result<(SendStream, RecvStream)> {
        self.open_typed_stream(StreamType::Control).await
    }

    /// Open a new bidirectional stream tagged as a **video** stream.
    pub async fn open_video_stream(&self) -> Result<(SendStream, RecvStream)> {
        self.open_typed_stream(StreamType::Video).await
    }

    /// Open a new bidirectional stream tagged as a **file transfer** stream.
    pub async fn open_file_stream(&self) -> Result<(SendStream, RecvStream)> {
        self.open_typed_stream(StreamType::File).await
    }

    /// Open a new bidirectional stream tagged as a **chat** stream.
    pub async fn open_chat_stream(&self) -> Result<(SendStream, RecvStream)> {
        self.open_typed_stream(StreamType::Chat).await
    }

    /// Accept the next incoming bidirectional stream and read its type tag.
    ///
    /// Returns the stream type along with the send/recv halves.
    pub async fn accept_stream(&self) -> Result<(StreamType, SendStream, RecvStream)> {
        let (send, mut recv) = self
            .connection
            .accept_bi()
            .await
            .context("failed to accept bidirectional stream")?;

        // Read the 1-byte stream type tag.
        let mut tag = [0u8; 1];
        recv.read_exact(&mut tag)
            .await
            .context("failed to read stream type tag")?;

        let stream_type = StreamType::from_u8(tag[0])
            .ok_or_else(|| anyhow!("unknown stream type tag: {}", tag[0]))?;

        debug!(?stream_type, "accepted incoming stream");

        Ok((stream_type, send, recv))
    }

    /// Return the remote address of the peer.
    pub fn remote_address(&self) -> std::net::SocketAddr {
        self.connection.remote_address()
    }

    /// Return a reference to the underlying [`quinn::Connection`].
    pub fn inner(&self) -> &Connection {
        &self.connection
    }

    /// Close the connection gracefully.
    pub fn close(&self, code: u32, reason: &[u8]) {
        self.connection
            .close(quinn::VarInt::from_u32(code), reason);
    }

    // -- internal helpers --

    /// Open a bidirectional stream and write the type tag as the first byte.
    async fn open_typed_stream(
        &self,
        stream_type: StreamType,
    ) -> Result<(SendStream, RecvStream)> {
        let (mut send, recv) = self
            .connection
            .open_bi()
            .await
            .context("failed to open bidirectional stream")?;

        // Write the 1-byte stream type tag.
        send.write_all(&[stream_type as u8])
            .await
            .context("failed to write stream type tag")?;

        debug!(?stream_type, "opened new stream");

        Ok((send, recv))
    }
}

// ---------------------------------------------------------------------------
// Length-delimited message framing
// ---------------------------------------------------------------------------

/// Write a length-delimited message to a QUIC send stream.
///
/// The message is prefixed with its length as a 4-byte big-endian `u32`.
pub async fn send_message(stream: &mut SendStream, data: &[u8]) -> Result<()> {
    let len = data.len() as u32;
    if len > MAX_MESSAGE_SIZE {
        return Err(anyhow!(
            "message too large: {} bytes (max {})",
            len,
            MAX_MESSAGE_SIZE
        ));
    }

    trace!(len = len, "sending length-delimited message");

    stream
        .write_all(&len.to_be_bytes())
        .await
        .context("failed to write message length")?;
    stream
        .write_all(data)
        .await
        .context("failed to write message body")?;

    Ok(())
}

/// Read a length-delimited message from a QUIC receive stream.
///
/// Expects a 4-byte big-endian `u32` length prefix followed by the message
/// body. Returns the message body as a `Vec<u8>`.
///
/// Returns `Ok(None)` if the stream has been cleanly finished (EOF).
pub async fn recv_message(stream: &mut RecvStream) -> Result<Vec<u8>> {
    // Read the 4-byte length prefix.
    let mut len_buf = [0u8; LENGTH_PREFIX_SIZE];
    stream
        .read_exact(&mut len_buf)
        .await
        .context("failed to read message length")?;

    let len = u32::from_be_bytes(len_buf);

    if len > MAX_MESSAGE_SIZE {
        return Err(anyhow!(
            "incoming message too large: {} bytes (max {})",
            len,
            MAX_MESSAGE_SIZE
        ));
    }

    trace!(len = len, "reading length-delimited message");

    let mut buf = vec![0u8; len as usize];
    stream
        .read_exact(&mut buf)
        .await
        .context("failed to read message body")?;

    Ok(buf)
}
