//! `rdesk_common` -- shared types and utilities for the rdesk remote desktop project.
//!
//! This crate is the foundation layer used by every other crate in the rdesk
//! workspace. It provides:
//!
//! * **Protobuf types** generated from `proto/message.proto` and
//!   `proto/rendezvous.proto` (re-exported via [`protos`]).
//! * **Application configuration** ([`config::AppConfig`]) with
//!   platform-aware persistence.
//! * **Device ID** generation and storage ([`device_id`]).
//! * **Password utilities** -- temporary password generation and Argon2
//!   hashing/verification ([`password`]).
//! * **Wire codec** -- length-delimited framing for TCP streams
//!   ([`bytes_codec`]).
//! * **Platform detection** ([`platform`]).

pub mod bytes_codec;
pub mod config;
pub mod device_id;
pub mod password;
pub mod platform;
pub mod protos;

// ---- Re-exports for convenience ----

pub use bytes_codec::{decode_message, encode_message, BytesCodec, CodecError};
pub use config::AppConfig;
pub use device_id::{generate_device_id, get_or_create_device_id, validate_device_id};
pub use password::{generate_temporary_password, hash_password, verify_password};
pub use platform::{current_platform, platform_name, Platform};
pub use protos::{message, rendezvous};
