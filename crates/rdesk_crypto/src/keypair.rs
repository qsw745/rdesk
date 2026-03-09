//! X25519 key pair management.
//!
//! Generates, saves, and loads X25519 key pairs used for Noise Protocol
//! handshakes. Private keys are zeroized on drop.

use std::fmt;
use std::path::Path;

use rand::rngs::OsRng;
use serde::{Deserialize, Serialize};
use tracing::debug;
use x25519_dalek::{PublicKey, StaticSecret};
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::{CryptoError, Result};

/// Persistent representation stored as hex-encoded JSON.
#[derive(Serialize, Deserialize)]
struct KeyPairFile {
    /// Hex-encoded 32-byte public key.
    public_key: String,
    /// Hex-encoded 32-byte private key.
    private_key: String,
}

/// An X25519 key pair suitable for use with the Noise Protocol.
///
/// The private key is zeroized when this value is dropped.
pub struct KeyPair {
    public: [u8; 32],
    #[allow(dead_code)]
    private: PrivateKeyBytes,
}

/// New-type wrapper so we can derive `ZeroizeOnDrop`.
#[derive(Zeroize, ZeroizeOnDrop)]
struct PrivateKeyBytes([u8; 32]);

impl KeyPair {
    /// Construct a `KeyPair` from raw 32-byte arrays.
    pub fn from_bytes(public: [u8; 32], private: [u8; 32]) -> Self {
        Self {
            public,
            private: PrivateKeyBytes(private),
        }
    }

    /// The 32-byte public key.
    pub fn public_key(&self) -> &[u8; 32] {
        &self.public
    }

    /// The 32-byte private key.
    pub fn private_key(&self) -> &[u8] {
        &self.private.0
    }
}

impl fmt::Debug for KeyPair {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("KeyPair")
            .field("public_key", &hex::encode(self.public))
            .field("private_key", &"[REDACTED]")
            .finish()
    }
}

/// Generate a fresh random X25519 key pair.
pub fn generate_keypair() -> KeyPair {
    let secret = StaticSecret::random_from_rng(OsRng);
    let public = PublicKey::from(&secret);

    let private_bytes: [u8; 32] = secret.to_bytes();
    let public_bytes: [u8; 32] = public.to_bytes();

    debug!(public_key = %hex::encode(public_bytes), "generated new X25519 key pair");

    KeyPair::from_bytes(public_bytes, private_bytes)
}

/// Save a key pair to `path` as a hex-encoded JSON file.
///
/// The file is created with restrictive permissions (owner-only read/write on
/// Unix systems).
pub fn save_keypair(keypair: &KeyPair, path: &Path) -> Result<()> {
    let file = KeyPairFile {
        public_key: hex::encode(keypair.public),
        private_key: hex::encode(keypair.private.0),
    };

    let json = serde_json::to_string_pretty(&file)?;

    // Ensure parent directory exists.
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    std::fs::write(path, json.as_bytes())?;

    // On Unix, restrict permissions to owner-only.
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    }

    debug!(path = %path.display(), "saved key pair");
    Ok(())
}

/// Load a key pair from a hex-encoded JSON file at `path`.
pub fn load_keypair(path: &Path) -> Result<KeyPair> {
    let data = std::fs::read_to_string(path)?;
    let file: KeyPairFile = serde_json::from_str(&data)?;

    let public = decode_hex_key(&file.public_key, "public")?;
    let private = decode_hex_key(&file.private_key, "private")?;

    debug!(path = %path.display(), "loaded key pair");
    Ok(KeyPair::from_bytes(public, private))
}

/// Decode a hex string into a fixed-size 32-byte array.
fn decode_hex_key(hex_str: &str, label: &str) -> Result<[u8; 32]> {
    let bytes = hex::decode(hex_str).map_err(|e| {
        CryptoError::InvalidKey(format!("invalid hex in {label} key: {e}"))
    })?;
    let arr: [u8; 32] = bytes.try_into().map_err(|v: Vec<u8>| {
        CryptoError::InvalidKey(format!(
            "{label} key has wrong length: expected 32, got {}",
            v.len()
        ))
    })?;
    Ok(arr)
}

// ---------------------------------------------------------------------------
// Tiny hex helpers (avoids pulling in the `hex` crate as a full dependency).
// ---------------------------------------------------------------------------
mod hex {
    /// Encode bytes as a lowercase hex string.
    pub fn encode(bytes: impl AsRef<[u8]>) -> String {
        bytes
            .as_ref()
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect()
    }

    /// Decode a hex string into bytes.
    pub fn decode(s: &str) -> std::result::Result<Vec<u8>, String> {
        if s.len() % 2 != 0 {
            return Err("odd-length hex string".into());
        }
        (0..s.len())
            .step_by(2)
            .map(|i| {
                u8::from_str_radix(&s[i..i + 2], 16)
                    .map_err(|e| format!("invalid hex at offset {i}: {e}"))
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_keypair() {
        let kp = generate_keypair();
        assert_eq!(kp.public_key().len(), 32);
        assert_eq!(kp.private_key().len(), 32);
        // Public and private keys should differ.
        assert_ne!(kp.public_key().as_slice(), kp.private_key());
    }

    #[test]
    fn test_save_load_roundtrip() {
        let dir = std::env::temp_dir().join("rdesk_crypto_test_keypair");
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("test_key.json");

        let original = generate_keypair();
        save_keypair(&original, &path).unwrap();

        let loaded = load_keypair(&path).unwrap();
        assert_eq!(original.public_key(), loaded.public_key());
        assert_eq!(original.private_key(), loaded.private_key());

        // Cleanup.
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_dir(&dir);
    }

    #[test]
    fn test_debug_redacts_private_key() {
        let kp = generate_keypair();
        let debug_str = format!("{kp:?}");
        assert!(debug_str.contains("[REDACTED]"));
        assert!(!debug_str.contains(&hex::encode(kp.private_key())));
    }

    #[test]
    fn test_hex_roundtrip() {
        let data = [0xde, 0xad, 0xbe, 0xef];
        let encoded = hex::encode(data);
        assert_eq!(encoded, "deadbeef");
        let decoded = hex::decode(&encoded).unwrap();
        assert_eq!(decoded, data);
    }
}
