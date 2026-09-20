pub mod model;
pub mod routes;
pub mod store;
#[cfg(test)]
mod tests;
#[derive(Default)]
pub struct Runtime {
    pub agents: std::sync::Mutex<std::collections::HashMap<String, u64>>,
    pub targets: std::sync::Mutex<std::collections::HashMap<String, u64>>,
}
