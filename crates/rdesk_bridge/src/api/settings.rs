//! Settings API exposed to Flutter.

use anyhow::Result;

use rdesk_common::config::AppConfig;

/// Serializable settings snapshot used by the Flutter settings screen.
pub struct SettingsData {
    pub signaling_server: String,
    pub relay_server: String,
    pub has_permanent_password: bool,
}

pub fn load_settings() -> Result<SettingsData> {
    let config = AppConfig::load()?;
    Ok(SettingsData {
        signaling_server: config.signaling_server,
        relay_server: config.relay_server,
        has_permanent_password: config.permanent_password.is_some(),
    })
}

pub fn save_settings(signaling_server: String, relay_server: String) -> Result<()> {
    let mut config = AppConfig::load()?;
    config.signaling_server = signaling_server;
    config.relay_server = relay_server;
    config.save()?;
    Ok(())
}
