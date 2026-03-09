//! Video codec abstractions.

pub mod vpx;

use anyhow::Result;

use crate::capture::CapturedFrame;

/// Video codec identifiers used during capability negotiation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CodecType {
    Raw,
    Vp9,
    H264,
    H265,
}

/// Decoded RGBA/BGRA video frame ready for rendering.
#[derive(Debug, Clone)]
pub struct DecodedFrame {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u8>,
}

/// Encoder interface for outbound screen frames.
pub trait VideoEncoder: Send {
    fn codec_type(&self) -> CodecType;
    fn encode(&mut self, frame: &CapturedFrame, keyframe: bool) -> Result<Vec<u8>>;
}

/// Decoder interface for inbound video frames.
pub trait VideoDecoder: Send {
    fn codec_type(&self) -> CodecType;
    fn decode(&mut self, data: &[u8], keyframe: bool) -> Result<DecodedFrame>;
}
