pub mod model;
mod pairing;
pub mod routes;
pub mod store;
#[cfg(test)]
mod tests;
#[derive(Default)]
pub struct Runtime {
    pub pairings: tokio::sync::Mutex<pairing::PairingRuntime>,
    pub agents: std::sync::Mutex<std::collections::HashMap<String, u64>>,
    pub targets: std::sync::Mutex<std::collections::HashMap<String, u64>>,
}

#[cfg(test)]
mod pairing_tests;
