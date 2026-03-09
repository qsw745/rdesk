//! Input simulation abstraction.

use anyhow::Result;
use rdesk_common::protos::message::{KeyEvent, MouseEvent, TouchEvent};

/// Trait for injecting input events on the controlled device.
pub trait InputSimulator: Send {
    fn mouse_event(&mut self, event: &MouseEvent) -> Result<()>;
    fn key_event(&mut self, event: &KeyEvent) -> Result<()>;
    fn touch_event(&mut self, event: &TouchEvent) -> Result<()>;
}

/// No-op simulator used until platform backends are implemented.
pub struct NoopInputSimulator;

impl InputSimulator for NoopInputSimulator {
    fn mouse_event(&mut self, _event: &MouseEvent) -> Result<()> {
        Ok(())
    }

    fn key_event(&mut self, _event: &KeyEvent) -> Result<()> {
        Ok(())
    }

    fn touch_event(&mut self, _event: &TouchEvent) -> Result<()> {
        Ok(())
    }
}

pub fn create_input_simulator() -> Result<Box<dyn InputSimulator>> {
    Ok(Box::new(NoopInputSimulator))
}
