//! File transfer API for Flutter.
//!
//! Provides functions for browsing remote directories and transferring files
//! between the local and remote machines during an active session.

use anyhow::{Context, Result};
use tracing::{debug, info};

/// Metadata for a single file or directory entry.
///
/// This is a bridge-friendly representation of the protobuf `FileEntry` type,
/// using only simple types that `flutter_rust_bridge` codegen can handle.
pub struct FileEntryData {
    /// File or directory name (not a full path).
    pub name: String,
    /// `true` if this entry is a directory.
    pub is_dir: bool,
    /// Size in bytes (0 for directories).
    pub size: u64,
    /// Last modification time as a Unix timestamp (seconds since epoch).
    pub modified: i64,
}

/// List the contents of a directory on the remote machine.
///
/// Returns a vector of [`FileEntryData`] describing the files and
/// subdirectories found at `path`.
pub async fn list_remote_dir(
    session_id: String,
    path: String,
) -> Result<Vec<FileEntryData>> {
    debug!(session_id = %session_id, path = %path, "listing remote directory");

    let _client = crate::state::get_client(&session_id)
        .context("session is not connected")?;
    let entries: Vec<FileEntryData> = rdesk_core::file_transfer::list_directory(&path)
        .await
        .context("failed to list remote directory")?
        .into_iter()
        .map(|entry| FileEntryData {
            name: entry.name,
            is_dir: entry.is_dir,
            size: entry.size,
            modified: entry.modified,
        })
        .collect();

    debug!(
        session_id = %session_id,
        path = %path,
        count = entries.len(),
        "remote directory listed"
    );
    Ok(entries)
}

/// Send a local file to the remote machine.
///
/// `local_path` is the absolute path on the local filesystem, and
/// `remote_path` is the destination path on the remote machine.
pub async fn send_file(
    session_id: String,
    local_path: String,
    remote_path: String,
) -> Result<()> {
    info!(
        session_id = %session_id,
        local = %local_path,
        remote = %remote_path,
        "sending file to remote"
    );

    let _client = crate::state::get_client(&session_id)
        .context("session is not connected")?;
    rdesk_core::file_transfer::send_file(&session_id, &local_path, &remote_path)
        .await
        .context("file send failed")?;

    info!(
        session_id = %session_id,
        local = %local_path,
        remote = %remote_path,
        "file sent successfully"
    );
    Ok(())
}

/// Receive a file from the remote machine.
///
/// `remote_path` is the path on the remote machine, and `local_path` is
/// where the file should be saved locally.
pub async fn receive_file(
    session_id: String,
    remote_path: String,
    local_path: String,
) -> Result<()> {
    info!(
        session_id = %session_id,
        remote = %remote_path,
        local = %local_path,
        "receiving file from remote"
    );

    let _client = crate::state::get_client(&session_id)
        .context("session is not connected")?;
    rdesk_core::file_transfer::receive_file(&session_id, &remote_path, &local_path)
        .await
        .context("file receive failed")?;

    info!(
        session_id = %session_id,
        remote = %remote_path,
        local = %local_path,
        "file received successfully"
    );
    Ok(())
}
