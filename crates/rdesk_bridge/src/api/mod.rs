//! Flutter-facing API modules.
//!
//! Each sub-module groups related functionality that is exposed to the Flutter
//! UI layer through `flutter_rust_bridge` codegen. The codegen scans all
//! public functions and structs in these modules to generate Dart bindings.

pub mod chat;
pub mod connection;
pub mod device;
pub mod file_transfer;
pub mod session;
pub mod settings;
