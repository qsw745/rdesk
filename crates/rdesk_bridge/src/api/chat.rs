//! Chat API exposed to Flutter.

use anyhow::Result;

/// Bridge-friendly chat payload.
pub struct ChatMessageData {
    pub sender: String,
    pub content: String,
    pub timestamp: i64,
}

pub fn send_chat_message(
    session_id: String,
    sender: String,
    content: String,
) -> Result<ChatMessageData> {
    let message = rdesk_core::chat::send_message(&session_id, &sender, &content)?;
    Ok(ChatMessageData {
        sender: message.sender,
        content: message.content,
        timestamp: message.timestamp,
    })
}

pub fn list_chat_messages(session_id: String) -> Result<Vec<ChatMessageData>> {
    let messages = rdesk_core::chat::list_messages(&session_id)?;
    Ok(messages
        .into_iter()
        .map(|message| ChatMessageData {
            sender: message.sender,
            content: message.content,
            timestamp: message.timestamp,
        })
        .collect())
}
