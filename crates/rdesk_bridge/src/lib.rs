//! # rdesk_bridge
//!
//! FFI bridge between Rust and Flutter via `flutter_rust_bridge` v2.
//!
//! This crate exposes the rdesk core functionality through a set of plain Rust
//! API functions that `flutter_rust_bridge` codegen will pick up and generate
//! corresponding Dart bindings for.

pub mod api;
mod state;

/// Initialise the bridge.
///
/// This should be called once from the Flutter side during application startup.
/// It sets up the default `flutter_rust_bridge` user utilities (logging, panic
/// hooks, etc.) and initialises the tracing subscriber.
pub fn init() {
    flutter_rust_bridge::setup_default_user_utils();
    tracing::info!("rdesk_bridge initialized");
}
