//! Connection management API for Flutter.
//!
//! Provides functions for device identification, password management, and
//! establishing or tearing down remote desktop sessions.

use anyhow::{Context, Result};
use rdesk_common::config::AppConfig;
use rdesk_common::device_id;
use rdesk_common::password;
use tracing::{debug, info};

/// Return the local device's unique 9-digit identifier.
///
/// The device ID is loaded from persistent storage on the first call and
/// generated if it does not yet exist.
pub fn get_device_id() -> String {
    match device_id::get_or_create_device_id() {
        Ok(id) => {
            debug!(device_id = %id, "returning device ID");
            id
        }
        Err(e) => {
            tracing::error!("failed to get device ID: {e:#}");
            // Return the ID from config as a fallback.
            AppConfig::load().map(|c| c.device_id).unwrap_or_default()
        }
    }
}

/// Generate a new random 6-character temporary password.
///
/// This password is intended for one-time session authentication and should
/// be displayed to the host user so a remote peer can use it to connect.
pub fn generate_temporary_password() -> String {
    let pwd = password::generate_temporary_password();
    debug!("generated temporary password");
    pwd
}

/// Set (or update) the permanent password.
///
/// The password is hashed with Argon2id before being stored in the
/// application configuration file. Pass an empty string to clear the
/// permanent password.
pub fn set_permanent_password(password_value: String) -> Result<()> {
    let mut config = AppConfig::load().context("failed to load config")?;

    if password_value.is_empty() {
        config.permanent_password = None;
        info!("permanent password cleared");
    } else {
        let hash = password::hash_password(&password_value).context("failed to hash password")?;
        config.permanent_password = Some(hash);
        info!("permanent password updated");
    }

    config.save().context("failed to save config")?;
    Ok(())
}

/// Connect to a remote peer.
///
/// Initiates the signaling flow (rendezvous lookup, hole punching, optional
/// relay fallback) and performs the Noise XX handshake to establish an
/// encrypted session.
///
/// Returns a unique session identifier on success that can be used with the
/// session, file-transfer, and chat APIs.
pub async fn connect_to_peer(device_id: String, password_value: String) -> Result<String> {
    info!(peer = %device_id, "initiating connection to peer");

    let config = AppConfig::load().context("failed to load config")?;
    let client = rdesk_core::RemoteClient::connect(&device_id, &password_value, &config)
        .await
        .context("failed to establish encrypted session")?;
    client
        .start_viewing()
        .await
        .context("failed to start viewing loop")?;
    let session_id = crate::state::register_client(client)
        .context("failed to register session in bridge state")?;

    debug!(peer = %device_id, session_id = %session_id, "peer connected");
    info!(session_id = %session_id, peer = %device_id, "session established");
    Ok(session_id)
}

/// Disconnect an active session.
///
/// Sends a close-session message to the remote peer and tears down the
/// local transport.
pub async fn disconnect(session_id: String) -> Result<()> {
    info!(session_id = %session_id, "disconnecting session");

    let Some(client) = crate::state::remove_client(&session_id)
        .context("failed to access bridge session registry")?
    else {
        anyhow::bail!("session not found: {}", session_id);
    };

    client.disconnect().await;

    info!(session_id = %session_id, "session disconnected");
    Ok(())
}
