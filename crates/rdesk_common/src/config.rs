//! Application configuration for rdesk.
//!
//! [`AppConfig`] stores all persistent settings such as signaling/relay server
//! addresses, the device identifier, and an optional permanent password hash.
//! Configuration is serialised as JSON and stored in a platform-specific config
//! directory (e.g. `~/.config/rdesk/` on Linux, `~/Library/Application Support/rdesk/`
//! on macOS, `%APPDATA%\rdesk\` on Windows).

use anyhow::{Context, Result};
use directories::ProjectDirs;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

/// Name used by the `directories` crate to resolve platform paths.
const APP_QUALIFIER: &str = "com";
const APP_ORGANIZATION: &str = "rdesk";
const APP_NAME: &str = "rdesk";

/// Configuration file name.
const CONFIG_FILE_NAME: &str = "config.json";

/// Application configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    /// Address of the signaling (rendezvous) server.
    #[serde(default = "default_signaling_server")]
    pub signaling_server: String,

    /// Address of the relay server.
    #[serde(default = "default_relay_server")]
    pub relay_server: String,

    /// Unique device identifier (9-digit numeric string).
    pub device_id: String,

    /// Optional permanent password stored as an Argon2 hash.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub permanent_password: Option<String>,
}

fn default_signaling_server() -> String {
    "qisw.top".to_string()
}

fn default_relay_server() -> String {
    "qisw.top".to_string()
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            signaling_server: default_signaling_server(),
            relay_server: default_relay_server(),
            device_id: String::new(),
            permanent_password: None,
        }
    }
}

impl AppConfig {
    /// Return the platform-specific configuration directory, creating it if it
    /// does not exist.
    pub fn config_dir() -> Result<PathBuf> {
        let dirs = ProjectDirs::from(APP_QUALIFIER, APP_ORGANIZATION, APP_NAME)
            .context("failed to determine config directory")?;
        let config_dir = dirs.config_dir().to_path_buf();
        if !config_dir.exists() {
            fs::create_dir_all(&config_dir).with_context(|| {
                format!("failed to create config dir: {}", config_dir.display())
            })?;
        }
        Ok(config_dir)
    }

    /// Full path to the configuration file.
    pub fn config_path() -> Result<PathBuf> {
        Ok(Self::config_dir()?.join(CONFIG_FILE_NAME))
    }

    /// Load the configuration from disk.
    ///
    /// If the configuration file does not exist, a new default configuration is
    /// created with a freshly generated device ID, saved to disk, and returned.
    pub fn load() -> Result<Self> {
        let path = Self::config_path()?;

        if path.exists() {
            let data = fs::read_to_string(&path)
                .with_context(|| format!("failed to read config file: {}", path.display()))?;
            let config: Self = serde_json::from_str(&data)
                .with_context(|| format!("failed to parse config file: {}", path.display()))?;
            Ok(config)
        } else {
            let mut config = Self::default();
            config.device_id = crate::device_id::generate_device_id();
            config.save()?;
            Ok(config)
        }
    }

    /// Persist the current configuration to disk.
    pub fn save(&self) -> Result<()> {
        let path = Self::config_path()?;
        let data = serde_json::to_string_pretty(self).context("failed to serialise config")?;
        fs::write(&path, data)
            .with_context(|| format!("failed to write config file: {}", path.display()))?;
        Ok(())
    }
}
