//! Process-local bridge session registry.

use std::collections::HashMap;
use std::sync::{Arc, OnceLock, RwLock};

use anyhow::Result;

use rdesk_core::RemoteClient;

type SessionRegistry = RwLock<HashMap<String, Arc<RemoteClient>>>;

fn registry() -> &'static SessionRegistry {
    static REGISTRY: OnceLock<SessionRegistry> = OnceLock::new();
    REGISTRY.get_or_init(|| RwLock::new(HashMap::new()))
}

pub fn register_client(client: RemoteClient) -> Result<String> {
    let session_id = client.session().id().to_string();
    let mut sessions = registry()
        .write()
        .map_err(|_| anyhow::anyhow!("session registry lock poisoned"))?;
    sessions.insert(session_id.clone(), Arc::new(client));
    Ok(session_id)
}

pub fn get_client(session_id: &str) -> Result<Arc<RemoteClient>> {
    let sessions = registry()
        .read()
        .map_err(|_| anyhow::anyhow!("session registry lock poisoned"))?;
    sessions
        .get(session_id)
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("unknown session id: {session_id}"))
}

pub fn remove_client(session_id: &str) -> Result<Option<Arc<RemoteClient>>> {
    let mut sessions = registry()
        .write()
        .map_err(|_| anyhow::anyhow!("session registry lock poisoned"))?;
    Ok(sessions.remove(session_id))
}
