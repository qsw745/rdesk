//! Clipboard state helpers.
//!
//! The full platform clipboard integration can be layered on top of this
//! in-memory representation later.

use anyhow::Result;

/// Clipboard payloads supported by the MVP protocol.
#[derive(Debug, Clone)]
pub enum ClipboardContent {
    Text(String),
    Html(String),
    ImagePng {
        width: u32,
        height: u32,
        data: Vec<u8>,
    },
}

/// In-memory clipboard manager used by session state.
#[derive(Debug, Default, Clone)]
pub struct ClipboardManager {
    current: Option<ClipboardContent>,
}

impl ClipboardManager {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn set_content(&mut self, content: ClipboardContent) -> Result<()> {
        self.current = Some(content);
        Ok(())
    }

    pub fn content(&self) -> Option<&ClipboardContent> {
        self.current.as_ref()
    }

    pub fn clear(&mut self) {
        self.current = None;
    }
}
