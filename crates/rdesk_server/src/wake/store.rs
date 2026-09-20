use super::model::*;
use crate::{AppState, UserRecord};
use tokio::io::AsyncWriteExt;

pub async fn update_wake<T>(
    state: &AppState,
    user_id: &str,
    mutation: impl FnOnce(&mut WakeAccountData) -> WakeResult<T>,
) -> WakeResult<T> {
    let _guard = state.user_store_write.lock().await;
    let mut snapshot: Vec<UserRecord> = state.users.iter().map(|e| e.value().clone()).collect();
    let user = snapshot
        .iter_mut()
        .find(|u| u.user_id == user_id)
        .ok_or(WakeError("not_found"))?;
    let value = mutation(&mut user.wake)?;
    user.wake.prune(crate::now_ms());
    let updated = user.clone();
    write_user_snapshot(state, &snapshot)
        .await
        .map_err(|_| WakeError("storage"))?;
    state.users.insert(user_id.into(), updated);
    Ok(value)
}
/// Caller holds user_store_write. Never expose a half-written account database.
pub async fn write_user_snapshot(state: &AppState, users: &[UserRecord]) -> anyhow::Result<()> {
    let path = std::path::Path::new(state.user_store_path.as_str());
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(std::path::Path::new("."));
    tokio::fs::create_dir_all(parent).await?;
    let tmp = parent.join(format!(".users-{}.tmp", uuid::Uuid::new_v4()));
    let result: anyhow::Result<()> = async {
        let mut options = tokio::fs::OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            options.mode(0o600);
        }
        let mut file = options.open(&tmp).await?;
        file.write_all(&serde_json::to_vec(users)?).await?;
        file.sync_all().await?;
        drop(file);
        tokio::fs::rename(&tmp, path).await?;
        Ok(())
    }
    .await;
    if result.is_err() {
        let _ = tokio::fs::remove_file(&tmp).await;
    }
    result
}
