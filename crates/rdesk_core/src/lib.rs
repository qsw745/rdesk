//! # rdesk_core
//!
//! Core engine crate for rdesk remote desktop software.
//!
//! This crate provides the fundamental building blocks for remote desktop
//! sessions including screen capture, video encoding/decoding, input simulation,
//! clipboard synchronisation, file transfer, and chat. It ties together the
//! networking (`rdesk_net`), cryptography (`rdesk_crypto`), and common types
//! (`rdesk_common`) crates into a cohesive session lifecycle.

pub mod capture;
pub mod chat;
pub mod clipboard;
pub mod codec;
pub mod client;
pub mod file_transfer;
pub mod input;
pub mod server;
pub mod session;

// Re-exports for downstream convenience.
pub use capture::{CapturedFrame, ScreenCapturer};
pub use client::RemoteClient;
pub use clipboard::{ClipboardContent, ClipboardManager};
pub use codec::{CodecType, DecodedFrame, VideoDecoder, VideoEncoder};
pub use input::InputSimulator;
pub use server::RemoteServer;
pub use session::{Session, SessionState};
