//! Desktop capture stub implementation.
//!
//! This provides a minimal capturer that returns a synthetic frame so the
//! workspace can compile and higher layers can be exercised before platform
//! capture backends are wired in.

use anyhow::Result;

use super::{CapturedFrame, DisplayInfo, ScreenCapturer};

const DEFAULT_WIDTH: u32 = 1280;
const DEFAULT_HEIGHT: u32 = 720;

/// Cross-platform placeholder capturer.
pub struct DesktopCapturer {
    display: DisplayInfo,
}

impl DesktopCapturer {
    pub fn new() -> Result<Self> {
        Ok(Self {
            display: DisplayInfo {
                id: 0,
                name: "Primary Display".to_string(),
                x: 0,
                y: 0,
                width: DEFAULT_WIDTH,
                height: DEFAULT_HEIGHT,
                is_primary: true,
            },
        })
    }
}

impl ScreenCapturer for DesktopCapturer {
    fn capture_frame(&mut self) -> Result<CapturedFrame> {
        let mut data = vec![0u8; (self.display.width * self.display.height * 4) as usize];

        // Draw a simple gradient so placeholder frames are visually distinct.
        for y in 0..self.display.height {
            for x in 0..self.display.width {
                let idx = ((y * self.display.width + x) * 4) as usize;
                data[idx] = (x % 255) as u8;
                data[idx + 1] = (y % 255) as u8;
                data[idx + 2] = 32;
                data[idx + 3] = 255;
            }
        }

        Ok(CapturedFrame {
            width: self.display.width,
            height: self.display.height,
            stride: self.display.width * 4,
            data,
            cursor: None,
        })
    }

    fn displays(&self) -> Result<Vec<DisplayInfo>> {
        Ok(vec![self.display.clone()])
    }
}
