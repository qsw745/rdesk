//! Device ID generation and persistence.
//!
//! Each rdesk installation is assigned a unique 9-digit numeric identifier that
//! is used to locate the device through the signaling server. The ID is stored
//! alongside the application configuration so that it survives restarts.

use anyhow::{Context, Result};
use directories::ProjectDirs;
use rand::Rng;
use std::fs;
use std::path::PathBuf;

/// File name for the persisted device ID.
const DEVICE_ID_FILE: &str = "device_id";

/// Number of digits in a device ID.
const DEVICE_ID_LENGTH: usize = 9;

/// Generate a random 9-digit numeric device ID.
///
/// The generated ID always has exactly 9 digits (i.e. the first digit is never
/// zero), producing values in the range `100_000_000..=999_999_999`.
///
/// # Example
///
/// ```
/// let id = rdesk_common::device_id::generate_device_id();
/// assert_eq!(id.len(), 9);
/// assert!(id.chars().all(|c| c.is_ascii_digit()));
/// ```
pub fn generate_device_id() -> String {
    let mut rng = rand::thread_rng();
    let id: u32 = rng.gen_range(100_000_000..=999_999_999);
    id.to_string()
}

/// Validate that a string is a well-formed device ID.
///
/// A valid device ID consists of exactly 9 ASCII digits with a non-zero
/// leading digit.
pub fn validate_device_id(id: &str) -> bool {
    id.len() == DEVICE_ID_LENGTH
        && id.starts_with(|c: char| c.is_ascii_digit() && c != '0')
        && id.chars().all(|c| c.is_ascii_digit())
}

/// Return the path to the persisted device ID file.
fn device_id_path() -> Result<PathBuf> {
    let dirs =
        ProjectDirs::from("com", "rdesk", "rdesk").context("failed to determine data directory")?;
    let data_dir = dirs.data_dir().to_path_buf();
    if !data_dir.exists() {
        fs::create_dir_all(&data_dir)
            .with_context(|| format!("failed to create data dir: {}", data_dir.display()))?;
    }
    Ok(data_dir.join(DEVICE_ID_FILE))
}

/// Load the device ID from persistent storage.
///
/// Returns `Ok(None)` if no device ID has been saved yet.
pub fn load_device_id() -> Result<Option<String>> {
    let path = device_id_path()?;
    if !path.exists() {
        return Ok(None);
    }
    let id = fs::read_to_string(&path)
        .with_context(|| format!("failed to read device ID file: {}", path.display()))?
        .trim()
        .to_string();
    if validate_device_id(&id) {
        Ok(Some(id))
    } else {
        tracing::warn!("invalid device ID on disk, will regenerate");
        Ok(None)
    }
}

/// Save a device ID to persistent storage.
pub fn save_device_id(id: &str) -> Result<()> {
    let path = device_id_path()?;
    fs::write(&path, id)
        .with_context(|| format!("failed to write device ID file: {}", path.display()))?;
    Ok(())
}

/// Load the device ID from disk, or generate and persist a new one.
pub fn get_or_create_device_id() -> Result<String> {
    if let Some(id) = load_device_id()? {
        return Ok(id);
    }
    let id = generate_device_id();
    save_device_id(&id)?;
    Ok(id)
}
