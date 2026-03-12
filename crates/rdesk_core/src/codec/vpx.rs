//! Lightweight software codec placeholder.
//!
//! The implementation uses LZ4-compressed raw pixels so the rest of the stack
//! can be exercised before a real VP9 pipeline is introduced.

use anyhow::{Context, Result};
use lz4_flex::{compress_prepend_size, decompress_size_prepended};

use super::{CodecType, DecodedFrame, VideoDecoder, VideoEncoder};
use crate::capture::CapturedFrame;

const HEADER_LEN: usize = 9;

/// Raw frame encoder with an LZ4 payload.
pub struct RawEncoder;

impl RawEncoder {
    pub fn new() -> Self {
        Self
    }
}

impl Default for RawEncoder {
    fn default() -> Self {
        Self::new()
    }
}

impl VideoEncoder for RawEncoder {
    fn codec_type(&self) -> CodecType {
        CodecType::Raw
    }

    fn encode(&mut self, frame: &CapturedFrame, keyframe: bool) -> Result<Vec<u8>> {
        let compressed = compress_prepend_size(&frame.data);
        let mut out = Vec::with_capacity(HEADER_LEN + compressed.len());
        out.extend_from_slice(&frame.width.to_be_bytes());
        out.extend_from_slice(&frame.height.to_be_bytes());
        out.push(u8::from(keyframe));
        out.extend_from_slice(&compressed);
        Ok(out)
    }
}

/// Raw frame decoder matching [`RawEncoder`].
pub struct RawDecoder;

impl RawDecoder {
    pub fn new() -> Self {
        Self
    }
}

impl Default for RawDecoder {
    fn default() -> Self {
        Self::new()
    }
}

impl VideoDecoder for RawDecoder {
    fn codec_type(&self) -> CodecType {
        CodecType::Raw
    }

    fn decode(&mut self, data: &[u8], _keyframe: bool) -> Result<DecodedFrame> {
        if data.len() < HEADER_LEN {
            anyhow::bail!("encoded frame too short");
        }

        let width = u32::from_be_bytes(data[0..4].try_into().unwrap());
        let height = u32::from_be_bytes(data[4..8].try_into().unwrap());
        let payload = &data[HEADER_LEN..];
        let pixels =
            decompress_size_prepended(payload).context("failed to decompress raw frame payload")?;

        Ok(DecodedFrame {
            width,
            height,
            data: pixels,
        })
    }
}
