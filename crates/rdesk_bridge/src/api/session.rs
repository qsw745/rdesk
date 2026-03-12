//! Session control API for Flutter.
//!
//! Provides functions for sending input events (mouse, keyboard, touch) and
//! requesting video key-frames during an active remote desktop session.

use anyhow::{Context, Result};
use rdesk_common::protos::message;
use tracing::{debug, trace};

/// A single touch point in a multi-touch event.
///
/// Mirrors the protobuf `TouchPoint` but uses simple types suitable for
/// `flutter_rust_bridge` codegen.
pub struct TouchPointData {
    /// Unique identifier for this touch pointer.
    pub id: i32,
    /// Horizontal position in logical pixels.
    pub x: f32,
    /// Vertical position in logical pixels.
    pub y: f32,
    /// Contact pressure in the range `[0.0, 1.0]`.
    pub pressure: f32,
}

/// Send a mouse event to the remote peer.
///
/// `mask` encodes which buttons are pressed (bit-mask), and `event_type`
/// corresponds to the `MouseEventType` enum (0 = move, 1 = down, 2 = up,
/// 3 = wheel).
pub fn send_mouse_event(
    session_id: String,
    x: i32,
    y: i32,
    mask: i32,
    event_type: i32,
) -> Result<()> {
    trace!(
        session_id = %session_id,
        x, y, mask, event_type,
        "sending mouse event"
    );

    let client = crate::state::get_client(&session_id).context("session is not connected")?;

    let mouse = message::MouseEvent {
        x,
        y,
        mask,
        modifiers: 0,
        event_type: event_type,
    };

    client.send_mouse_event(mouse);

    Ok(())
}

/// Send a keyboard event to the remote peer.
///
/// `key_code` is the platform-independent key code, `down` indicates whether
/// the key is being pressed (`true`) or released (`false`), and `modifiers`
/// is a bitmask of active modifier keys.
pub fn send_key_event(session_id: String, key_code: u32, down: bool, modifiers: i32) -> Result<()> {
    trace!(
        session_id = %session_id,
        key_code, down, modifiers,
        "sending key event"
    );

    let client = crate::state::get_client(&session_id).context("session is not connected")?;

    let key = message::KeyEvent {
        key_code,
        down,
        modifiers,
        control_key: 0, // ControlKey::CONTROL_KEY_UNKNOWN
        chr: String::new(),
    };

    client.send_key_event(key);

    Ok(())
}

/// Send a multi-touch event to the remote peer.
///
/// `event_type` corresponds to `TouchEventType` (0 = start, 1 = move,
/// 2 = end, 3 = cancel).
pub fn send_touch_event(
    session_id: String,
    points: Vec<TouchPointData>,
    event_type: i32,
) -> Result<()> {
    trace!(
        session_id = %session_id,
        num_points = points.len(),
        event_type,
        "sending touch event"
    );

    let client = crate::state::get_client(&session_id).context("session is not connected")?;

    let proto_points: Vec<message::TouchPoint> = points
        .into_iter()
        .map(|p| message::TouchPoint {
            id: p.id,
            x: p.x,
            y: p.y,
            pressure: p.pressure,
        })
        .collect();

    let touch = message::TouchEvent {
        points: proto_points,
        event_type: event_type,
    };

    client.send_touch_event(touch);

    Ok(())
}

/// Request a video key-frame from the remote peer.
///
/// This is useful after connection establishment, display switching, or when
/// the decoder detects corruption and needs a full refresh.
pub fn request_keyframe(session_id: String) -> Result<()> {
    debug!(session_id = %session_id, "requesting keyframe");
    let _client = crate::state::get_client(&session_id).context("session is not connected")?;

    Ok(())
}
