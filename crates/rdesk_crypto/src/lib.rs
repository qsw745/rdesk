//! # rdesk_crypto
//!
//! Cryptography crate for rdesk remote desktop software.
//!
//! Provides Noise Protocol (XX pattern) encrypted transport, X25519 key management,
//! password-based authentication, and session key derivation.

pub mod auth;
pub mod keypair;
pub mod noise;
pub mod session_key;

use thiserror::Error;

/// Unified error type for all cryptographic operations in rdesk.
#[derive(Debug, Error)]
pub enum CryptoError {
    #[error("Noise protocol error: {0}")]
    Noise(#[from] snow::Error),

    #[error("Key generation error: {0}")]
    KeyGen(String),

    #[error("Encryption error: {0}")]
    Encryption(String),

    #[error("Decryption error: {0}")]
    Decryption(String),

    #[error("Authentication failed: {0}")]
    AuthFailed(String),

    #[error("Handshake error: {0}")]
    Handshake(String),

    #[error("Invalid key material: {0}")]
    InvalidKey(String),

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
}

/// Convenience alias used throughout the crate.
pub type Result<T> = std::result::Result<T, CryptoError>;

// Re-exports for downstream convenience.
pub use auth::AuthState;
pub use keypair::KeyPair;
pub use noise::NoiseSession;
