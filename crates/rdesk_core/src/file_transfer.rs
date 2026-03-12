//! Minimal file transfer helpers.

use std::path::Path;
use std::time::UNIX_EPOCH;

use anyhow::{Context, Result};

/// Bridge-friendly directory entry.
#[derive(Debug, Clone)]
pub struct FileEntry {
    pub name: String,
    pub is_dir: bool,
    pub size: u64,
    pub modified: i64,
}

/// List a directory on the local filesystem.
pub async fn list_directory(path: &str) -> Result<Vec<FileEntry>> {
    let mut entries = tokio::fs::read_dir(path)
        .await
        .with_context(|| format!("failed to read directory: {path}"))?;
    let mut out = Vec::new();

    while let Some(entry) = entries
        .next_entry()
        .await
        .context("failed to read directory entry")?
    {
        let metadata = entry
            .metadata()
            .await
            .with_context(|| format!("failed to stat {}", entry.path().display()))?;
        let modified = metadata
            .modified()
            .ok()
            .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
            .map(|value| value.as_secs() as i64)
            .unwrap_or_default();

        out.push(FileEntry {
            name: entry.file_name().to_string_lossy().into_owned(),
            is_dir: metadata.is_dir(),
            size: metadata.len(),
            modified,
        });
    }

    out.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(out)
}

/// Validate and stage a local upload.
pub async fn send_file(session_id: &str, local_path: &str, remote_path: &str) -> Result<()> {
    if session_id.is_empty() {
        anyhow::bail!("session id cannot be empty");
    }

    let metadata = tokio::fs::metadata(local_path)
        .await
        .with_context(|| format!("failed to stat local file: {local_path}"))?;

    if !metadata.is_file() {
        anyhow::bail!("path is not a regular file: {local_path}");
    }

    if remote_path.is_empty() {
        anyhow::bail!("remote path cannot be empty");
    }

    Ok(())
}

/// Create a placeholder local file for a not-yet-implemented remote download.
pub async fn receive_file(session_id: &str, remote_path: &str, local_path: &str) -> Result<()> {
    if session_id.is_empty() {
        anyhow::bail!("session id cannot be empty");
    }
    if remote_path.is_empty() {
        anyhow::bail!("remote path cannot be empty");
    }

    if let Some(parent) = Path::new(local_path).parent() {
        if !parent.as_os_str().is_empty() {
            tokio::fs::create_dir_all(parent)
                .await
                .with_context(|| format!("failed to create {}", parent.display()))?;
        }
    }

    let placeholder =
        format!("rdesk stub download\nsession={session_id}\nremote_path={remote_path}\n");
    tokio::fs::write(local_path, placeholder)
        .await
        .with_context(|| format!("failed to write placeholder file: {local_path}"))?;

    Ok(())
}
