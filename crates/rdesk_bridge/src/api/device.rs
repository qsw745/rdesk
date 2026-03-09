//! Device and environment API exposed to Flutter.

use anyhow::Result;

use rdesk_common::{config::AppConfig, platform_name};

/// Basic local device information for the Flutter home screen.
pub struct DeviceInfoData {
    pub device_id: String,
    pub platform: String,
    pub signaling_server: String,
    pub relay_server: String,
}

pub fn get_device_info() -> Result<DeviceInfoData> {
    let config = AppConfig::load()?;
    Ok(DeviceInfoData {
        device_id: config.device_id,
        platform: platform_name().to_string(),
        signaling_server: config.signaling_server,
        relay_server: config.relay_server,
    })
}
