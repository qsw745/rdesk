//! Screen capture trait and platform factory.
//!
//! Defines the [`ScreenCapturer`] trait used by the server-side session to grab
//! frames from the host's display(s), and provides a factory function
//! [`create_capturer`] that returns the appropriate platform implementation.

pub mod desktop;

use anyhow::Result;

/// Information about a cursor overlaid on a captured frame.
#[derive(Debug, Clone)]
pub struct CursorInfo {
    /// Cursor hot-spot X relative to the cursor image.
    pub hotspot_x: i32,
    /// Cursor hot-spot Y relative to the cursor image.
    pub hotspot_y: i32,
    /// Cursor position X on the display.
    pub x: i32,
    /// Cursor position Y on the display.
    pub y: i32,
    /// Cursor image width.
    pub width: u32,
    /// Cursor image height.
    pub height: u32,
    /// Cursor image pixel data (BGRA).
    pub data: Vec<u8>,
}

/// A single captured frame from a display.
#[derive(Debug, Clone)]
pub struct CapturedFrame {
    /// Width of the frame in pixels.
    pub width: u32,
    /// Height of the frame in pixels.
    pub height: u32,
    /// Number of bytes per row (may include padding).
    pub stride: u32,
    /// Raw pixel data in BGRA format.
    pub data: Vec<u8>,
    /// Optional cursor information if a hardware cursor was captured separately.
    pub cursor: Option<CursorInfo>,
}

/// Information about a connected display/monitor.
#[derive(Debug, Clone)]
pub struct DisplayInfo {
    /// Unique display identifier.
    pub id: u32,
    /// Human-readable name (e.g. "Built-in Retina Display").
    pub name: String,
    /// X position in the virtual screen coordinate space.
    pub x: i32,
    /// Y position in the virtual screen coordinate space.
    pub y: i32,
    /// Width in pixels.
    pub width: u32,
    /// Height in pixels.
    pub height: u32,
    /// Whether this is the primary display.
    pub is_primary: bool,
}

/// Trait for platform-specific screen capture implementations.
///
/// Implementors must be [`Send`] so they can be held in a `tokio::sync::Mutex`
/// and used across async task boundaries.
pub trait ScreenCapturer: Send {
    /// Capture a single frame from the current display.
    fn capture_frame(&mut self) -> Result<CapturedFrame>;

    /// List all connected displays.
    fn displays(&self) -> Result<Vec<DisplayInfo>>;
}

/// Create a screen capturer for the current platform.
///
/// Returns a [`desktop::DesktopCapturer`] that uses the `xcap` crate.
pub fn create_capturer() -> Result<Box<dyn ScreenCapturer>> {
    let capturer = desktop::DesktopCapturer::new()?;
    Ok(Box::new(capturer))
}
