//! P2P connectivity primitives.
//!
//! Provides STUN address discovery, NAT type detection, and UDP hole punching.

pub mod hole_punch;
pub mod nat_detect;
pub mod stun;

pub use hole_punch::punch_hole;
pub use nat_detect::{detect_nat_type, NatType};
pub use stun::discover_external_addr;
