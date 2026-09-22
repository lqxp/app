//! SHA-256 of the running executable, shown in About so a build can be checked
//! against the published fingerprint.
use tauri::{
    plugin::{Builder, TauriPlugin},
    Runtime,
};

#[tauri::command]
async fn fingerprint() -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(|| {
        use sha2::{Digest, Sha256};
        let path = std::env::current_exe().map_err(|e| e.to_string())?;
        let mut file = std::fs::File::open(path).map_err(|e| e.to_string())?;
        let mut hasher = Sha256::new();
        std::io::copy(&mut file, &mut hasher).map_err(|e| e.to_string())?;
        Ok(format!("{:x}", hasher.finalize()))
    })
    .await
    .map_err(|e| e.to_string())?
}

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("integrity")
        .invoke_handler(tauri::generate_handler![fingerprint])
        .build()
}
