//! Length-delimited message framing codec.
//!
//! Provides utilities for encoding and decoding byte messages with a 4-byte
//! big-endian length prefix. This is the wire format used by rdesk for all
//! TCP-based protocol communication.
//!
//! The module also provides a [`BytesCodec`] struct that can be used for
//! incremental decoding of a stream of length-delimited frames from a
//! [`bytes::BytesMut`] buffer (similar in spirit to `tokio_util::codec` but
//! without the `tokio_util` dependency).

use bytes::{Buf, BufMut, BytesMut};

/// Size of the length prefix in bytes.
const LENGTH_PREFIX_SIZE: usize = 4;

/// Encode a message by prepending a 4-byte big-endian length header.
///
/// The returned `Vec<u8>` contains `[len(4 bytes BE) | payload]`.
pub fn encode_message(msg: &[u8]) -> Vec<u8> {
    let len = msg.len() as u32;
    let mut buf = Vec::with_capacity(LENGTH_PREFIX_SIZE + msg.len());
    buf.extend_from_slice(&len.to_be_bytes());
    buf.extend_from_slice(msg);
    buf
}

/// Try to decode a single length-delimited frame from `buf`.
///
/// If a complete frame is available the payload bytes are returned and the
/// consumed bytes (header + payload) are removed from the front of `buf`.
///
/// Returns `None` if there are not enough bytes to form a complete frame.
pub fn decode_message(buf: &mut BytesMut) -> Option<Vec<u8>> {
    if buf.len() < LENGTH_PREFIX_SIZE {
        return None;
    }

    // Peek at the length without advancing the cursor yet.
    let len = u32::from_be_bytes([buf[0], buf[1], buf[2], buf[3]]) as usize;

    if buf.len() < LENGTH_PREFIX_SIZE + len {
        return None;
    }

    // Consume the length prefix.
    buf.advance(LENGTH_PREFIX_SIZE);

    // Split off the payload.
    let payload = buf.split_to(len).to_vec();
    Some(payload)
}

/// A stateless codec for reading and writing length-delimited frames.
///
/// # Encoding
///
/// Call [`BytesCodec::encode`] to append a length-prefixed frame to an output
/// buffer.
///
/// # Decoding
///
/// Call [`BytesCodec::decode`] with a mutable reference to a [`BytesMut`]
/// accumulation buffer. The method returns `Ok(Some(data))` when a complete
/// frame has been extracted, `Ok(None)` when more data is needed, or an error
/// if the frame length exceeds [`BytesCodec::max_frame_length`].
#[derive(Debug, Clone)]
pub struct BytesCodec {
    max_frame_length: usize,
}

/// Error returned when a frame exceeds the configured maximum length.
#[derive(Debug, thiserror::Error)]
pub enum CodecError {
    #[error("frame length {length} exceeds maximum allowed {max}")]
    FrameTooLarge { length: usize, max: usize },
}

impl Default for BytesCodec {
    fn default() -> Self {
        Self::new()
    }
}

impl BytesCodec {
    /// Default maximum frame length: 16 MiB.
    const DEFAULT_MAX_FRAME_LENGTH: usize = 16 * 1024 * 1024;

    /// Create a new codec with the default maximum frame length (16 MiB).
    pub fn new() -> Self {
        Self {
            max_frame_length: Self::DEFAULT_MAX_FRAME_LENGTH,
        }
    }

    /// Create a new codec with a custom maximum frame length.
    pub fn with_max_frame_length(max_frame_length: usize) -> Self {
        Self { max_frame_length }
    }

    /// Return the maximum frame length.
    pub fn max_frame_length(&self) -> usize {
        self.max_frame_length
    }

    /// Try to decode a single frame from `buf`.
    ///
    /// Returns:
    /// - `Ok(Some(payload))` when a complete frame has been read.
    /// - `Ok(None)` when more data is required.
    /// - `Err(CodecError::FrameTooLarge)` when the advertised frame length
    ///   exceeds the configured maximum.
    pub fn decode(&self, buf: &mut BytesMut) -> Result<Option<Vec<u8>>, CodecError> {
        if buf.len() < LENGTH_PREFIX_SIZE {
            return Ok(None);
        }

        let len = u32::from_be_bytes([buf[0], buf[1], buf[2], buf[3]]) as usize;

        if len > self.max_frame_length {
            return Err(CodecError::FrameTooLarge {
                length: len,
                max: self.max_frame_length,
            });
        }

        if buf.len() < LENGTH_PREFIX_SIZE + len {
            // Reserve space so the next read has room.
            buf.reserve(LENGTH_PREFIX_SIZE + len - buf.len());
            return Ok(None);
        }

        buf.advance(LENGTH_PREFIX_SIZE);
        let payload = buf.split_to(len).to_vec();
        Ok(Some(payload))
    }

    /// Encode a message into `buf` with a 4-byte big-endian length prefix.
    pub fn encode(&self, msg: &[u8], buf: &mut BytesMut) -> Result<(), CodecError> {
        let len = msg.len();
        if len > self.max_frame_length {
            return Err(CodecError::FrameTooLarge {
                length: len,
                max: self.max_frame_length,
            });
        }
        buf.reserve(LENGTH_PREFIX_SIZE + len);
        buf.put_u32(len as u32);
        buf.put_slice(msg);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encode_decode_roundtrip() {
        let original = b"hello, rdesk!";
        let encoded = encode_message(original);
        let mut buf = BytesMut::from(&encoded[..]);
        let decoded = decode_message(&mut buf).expect("should decode");
        assert_eq!(decoded, original);
        assert!(buf.is_empty());
    }

    #[test]
    fn decode_incomplete() {
        let mut buf = BytesMut::from(&[0u8, 0, 0, 5, 1, 2][..]);
        assert!(decode_message(&mut buf).is_none());
    }

    #[test]
    fn codec_roundtrip() {
        let codec = BytesCodec::new();
        let msg = b"codec test";
        let mut buf = BytesMut::new();
        codec.encode(msg, &mut buf).unwrap();
        let decoded = codec.decode(&mut buf).unwrap().expect("should decode");
        assert_eq!(decoded, msg);
    }

    #[test]
    fn codec_rejects_oversized_frame() {
        let codec = BytesCodec::with_max_frame_length(8);
        let mut buf = BytesMut::new();
        // Manually write a header claiming 100 bytes.
        buf.put_u32(100);
        buf.put_slice(&[0u8; 100]);
        let result = codec.decode(&mut buf);
        assert!(result.is_err());
    }
}
