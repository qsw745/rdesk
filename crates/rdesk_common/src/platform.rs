//! Platform detection utilities.
//!
//! Provides a [`Platform`] enum and helper functions to identify the operating
//! system at compile time. This is used throughout rdesk to adapt behaviour
//! (e.g. choosing a screen-capture backend or input-injection method) to the
//! host platform.

use std::fmt;

/// Supported platforms.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Platform {
    Windows,
    MacOS,
    Linux,
    Android,
    IOS,
}

impl fmt::Display for Platform {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

impl Platform {
    /// Return a human-readable name for this platform.
    pub fn as_str(&self) -> &'static str {
        match self {
            Platform::Windows => "Windows",
            Platform::MacOS => "macOS",
            Platform::Linux => "Linux",
            Platform::Android => "Android",
            Platform::IOS => "iOS",
        }
    }
}

/// Detect the platform at compile time.
///
/// On desktop targets this inspects `cfg!(target_os)`. On mobile targets it
/// checks for `target_os = "android"` and `target_os = "ios"`.
///
/// Produces a compile-time error if built for an unsupported target OS.
pub fn current_platform() -> Platform {
    cfg_if_platform()
}

#[cfg(target_os = "windows")]
const fn cfg_if_platform() -> Platform {
    Platform::Windows
}

#[cfg(target_os = "macos")]
const fn cfg_if_platform() -> Platform {
    Platform::MacOS
}

#[cfg(target_os = "linux")]
const fn cfg_if_platform() -> Platform {
    Platform::Linux
}

#[cfg(target_os = "android")]
const fn cfg_if_platform() -> Platform {
    Platform::Android
}

#[cfg(target_os = "ios")]
const fn cfg_if_platform() -> Platform {
    Platform::IOS
}

#[cfg(not(any(
    target_os = "windows",
    target_os = "macos",
    target_os = "linux",
    target_os = "android",
    target_os = "ios",
)))]
const fn cfg_if_platform() -> Platform {
    compile_error!("unsupported target OS for rdesk")
}

/// Return a static string naming the current platform.
///
/// Equivalent to `current_platform().as_str()`.
pub fn platform_name() -> &'static str {
    current_platform().as_str()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn platform_is_known() {
        let p = current_platform();
        let name = platform_name();
        assert!(!name.is_empty());
        assert_eq!(p.as_str(), name);
    }

    #[test]
    fn display_matches_as_str() {
        let p = Platform::MacOS;
        assert_eq!(format!("{}", p), p.as_str());
    }
}
