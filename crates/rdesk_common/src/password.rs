//! Password utilities for rdesk.
//!
//! Provides helpers for generating temporary session passwords and for hashing
//! / verifying permanent passwords using Argon2id.

use anyhow::Result;
use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use rand::Rng;

/// Character set used for temporary password generation.
const TEMP_PASSWORD_CHARS: &[u8] =
    b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

/// Length of a temporary password.
const TEMP_PASSWORD_LEN: usize = 6;

/// Generate a random 6-character alphanumeric temporary password.
///
/// The password is intended for one-time sessions and is displayed to the user
/// on the host side so that a remote peer can authenticate.
///
/// # Example
///
/// ```
/// let pwd = rdesk_common::password::generate_temporary_password();
/// assert_eq!(pwd.len(), 6);
/// assert!(pwd.chars().all(|c| c.is_ascii_alphanumeric()));
/// ```
pub fn generate_temporary_password() -> String {
    let mut rng = rand::thread_rng();
    (0..TEMP_PASSWORD_LEN)
        .map(|_| {
            let idx = rng.gen_range(0..TEMP_PASSWORD_CHARS.len());
            TEMP_PASSWORD_CHARS[idx] as char
        })
        .collect()
}

/// Hash a password using Argon2id.
///
/// Returns the PHC-formatted hash string which embeds the salt, algorithm
/// parameters, and the hash itself.
pub fn hash_password(password: &str) -> Result<String> {
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    let hash = argon2
        .hash_password(password.as_bytes(), &salt)
        .map_err(|e| anyhow::anyhow!("password hashing failed: {}", e))?;
    Ok(hash.to_string())
}

/// Verify a plaintext password against an Argon2 PHC hash string.
///
/// Returns `Ok(true)` if the password matches, `Ok(false)` otherwise.
pub fn verify_password(password: &str, hash: &str) -> Result<bool> {
    let parsed_hash = PasswordHash::new(hash)
        .map_err(|e| anyhow::anyhow!("failed to parse password hash: {}", e))?;
    let result = Argon2::default().verify_password(password.as_bytes(), &parsed_hash);
    Ok(result.is_ok())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn temporary_password_format() {
        let pwd = generate_temporary_password();
        assert_eq!(pwd.len(), TEMP_PASSWORD_LEN);
        assert!(pwd.chars().all(|c| c.is_ascii_alphanumeric()));
    }

    #[test]
    fn hash_and_verify() {
        let password = "hunter2";
        let hash = hash_password(password).unwrap();
        assert!(verify_password(password, &hash).unwrap());
        assert!(!verify_password("wrong", &hash).unwrap());
    }
}
