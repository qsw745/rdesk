//! In-memory chat primitives for MVP bring-up.

use std::collections::HashMap;
use std::sync::{OnceLock, RwLock};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};

/// A chat message stored for a session.
#[derive(Debug, Clone)]
pub struct ChatMessageRecord {
    pub sender: String,
    pub content: String,
    pub timestamp: i64,
}

type ChatStore = RwLock<HashMap<String, Vec<ChatMessageRecord>>>;

fn store() -> &'static ChatStore {
    static STORE: OnceLock<ChatStore> = OnceLock::new();
    STORE.get_or_init(|| RwLock::new(HashMap::new()))
}

/// Append a chat message to a session-local transcript.
pub fn send_message(session_id: &str, sender: &str, content: &str) -> Result<ChatMessageRecord> {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .context("system clock is before UNIX_EPOCH")?
        .as_secs() as i64;

    let message = ChatMessageRecord {
        sender: sender.to_string(),
        content: content.to_string(),
        timestamp,
    };

    let mut sessions = store()
        .write()
        .map_err(|_| anyhow::anyhow!("chat store lock poisoned"))?;
    sessions
        .entry(session_id.to_string())
        .or_default()
        .push(message.clone());

    Ok(message)
}

/// Return the current chat transcript for a session.
pub fn list_messages(session_id: &str) -> Result<Vec<ChatMessageRecord>> {
    let sessions = store()
        .read()
        .map_err(|_| anyhow::anyhow!("chat store lock poisoned"))?;
    Ok(sessions.get(session_id).cloned().unwrap_or_default())
}
