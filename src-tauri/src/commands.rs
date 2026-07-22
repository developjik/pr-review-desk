//! Tauri `invoke` commands — the React -> Rust API surface.
//!
//! Each command either reads/writes persisted config or forwards a control
//! command to the daemon via its stdin (see `sidecar::send_command`).

use serde_json::Value;
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_updater::UpdaterExt;

use crate::config_store;
use crate::sidecar;

/// Read the persisted config (or null if unset).
#[tauri::command]
pub async fn get_config(app: AppHandle) -> Result<Value, String> {
    // Use read_resolved_config which re-merges from keychain
    Ok(config_store::read_resolved_config(&app).unwrap_or(Value::Null))
}

/// Persist config and push it to the daemon (initial or hot-reload).
///
/// The UI collects only user-facing fields; the host injects daemon-internal
/// paths (`dbPath`, `logDir`) resolved from the app data directory so the two
/// sides never disagree on where state lives.
#[tauri::command]
pub async fn save_config(app: AppHandle, mut config: Value) -> Result<(), String> {
    inject_internal_paths(&app, &mut config);

    // Extract secrets to keychain, redact the to-disk copy
    let mut redacted = config.clone();
    if let Some(obj) = redacted.as_object_mut() {
        // Store secrets in keychain — only redact if the store succeeded,
        // otherwise keep the plaintext in config so it isn't lost.
        if let Some(pat) = obj.get("githubPat").and_then(|v| v.as_str()) {
            if !pat.is_empty() {
                match crate::secrets::store_github_pat(pat) {
                    Ok(()) => {
                        obj.remove("githubPat");
                        obj.insert("githubPatStored".to_string(), Value::Bool(true));
                        obj.remove("githubPatInsecureFallback");
                    }
                    Err(e) => {
                        log::warn!("Failed to store GitHub PAT to keychain: {e}");
                        obj.insert("githubPatInsecureFallback".to_string(), Value::Bool(true));
                        eprintln!("credential:insecure-fallback secret=github_pat err={e}");
                    }
                }
            }
        }
        if let Some(key) = obj.get("llmApiKey").and_then(|v| v.as_str()) {
            if !key.is_empty() {
                match crate::secrets::store_llm_api_key(key) {
                    Ok(()) => {
                        obj.remove("llmApiKey");
                        obj.insert("llmApiKeyStored".to_string(), Value::Bool(true));
                        obj.remove("llmApiKeyInsecureFallback");
                    }
                    Err(e) => {
                        log::warn!("Failed to store LLM API key to keychain: {e}");
                        obj.insert("llmApiKeyInsecureFallback".to_string(), Value::Bool(true));
                        eprintln!("credential:insecure-fallback secret=llm_api_key err={e}");
                    }
                }
            }
        }
    }

    // Write REDACTED config to disk
    config_store::write_config(&app, &redacted)?;

    // Forward the UN-REDACTED (original) config to daemon
    sidecar::send_command(&app, &config_store::config_command_line(&config)).await;
    Ok(())
}

/// Trigger an immediate poll cycle.
#[tauri::command]
pub async fn poll_now(app: AppHandle) -> Result<(), String> {
    do_poll_now(&app).await;
    Ok(())
}

/// Pause the daemon (cancels scheduled polls).
#[tauri::command]
pub async fn pause_daemon(app: AppHandle) -> Result<(), String> {
    sidecar::send_command(&app, r#"{"type":"command","cmd":"pause"}"#).await;
    Ok(())
}

/// Resume the daemon.
#[tauri::command]
pub async fn resume_daemon(app: AppHandle) -> Result<(), String> {
    sidecar::send_command(&app, r#"{"type":"command","cmd":"resume"}"#).await;
    Ok(())
}

/// Approve a pending review (optionally with selected finding ids).
#[tauri::command]
pub async fn approve_review(app: AppHandle, review_id: i64, finding_ids: Option<Vec<String>>, edits: Option<Value>) -> Result<(), String> {
    let line = serde_json::json!({
        "type": "command",
        "cmd": "approve:review",
        "reviewId": review_id,
        "findingIds": finding_ids,
        "edits": edits,
    }).to_string();
    sidecar::send_command(&app, &line).await;
    Ok(())
}

/// Reject a pending review.
#[tauri::command]
pub async fn reject_review(app: AppHandle, review_id: i64) -> Result<(), String> {
    let line = serde_json::json!({
        "type": "command",
        "cmd": "reject:review",
        "reviewId": review_id,
    }).to_string();
    sidecar::send_command(&app, &line).await;
    Ok(())
}

/// Request a snapshot of all pending reviews.
#[tauri::command]
pub async fn list_pending_reviews(app: AppHandle) -> Result<(), String> {
    let line = serde_json::json!({
        "type": "command",
        "cmd": "pending:list",
    }).to_string();
    sidecar::send_command(&app, &line).await;
    Ok(())
}

/// Snapshot of daemon lifecycle (online + last state string).
#[tauri::command]
pub async fn daemon_status(app: AppHandle) -> Result<Value, String> {
    let snap = sidecar::snapshot_status(&app).await;
    Ok(serde_json::json!({ "online": snap.online, "state": snap.state }))
}

// ---- auto-update (G003: tauri-plugin-updater, Rust-driven) ------------------

/// Check for an available app update via tauri-plugin-updater.
///
/// Returns a status string: `"up-to-date"` or `"update-available: <version>"`.
/// Status check only — it does NOT download or install. The UI asks the user to
/// confirm, then calls [`install_update`].
#[tauri::command]
pub async fn check_for_updates(app: AppHandle) -> Result<String, String> {
    let updater = app.updater().map_err(|e| format!("Updater error: {e}"))?;
    match updater.check().await {
        Ok(Some(update)) => Ok(format!("update-available: {}", update.version)),
        Ok(None) => Ok("up-to-date".to_string()),
        Err(e) => Err(format!("Failed to check for updates: {e}")),
    }
}

/// Download + install the latest update (if any), then restart the app.
///
/// Performs a fresh check, so calling this without a prior [`check_for_updates`]
/// is safe — it errors with "No update available" when there is nothing to install.
#[tauri::command]
pub async fn install_update(app: AppHandle) -> Result<(), String> {
    let updater = app.updater().map_err(|e| format!("Updater error: {e}"))?;
    let update = updater
        .check()
        .await
        .map_err(|e| format!("Failed to check for updates: {e}"))?
        .ok_or_else(|| "No update available".to_string())?;
    update
        .download_and_install(|_len, _total| {}, || {})
        .await
        .map_err(|e| format!("Failed to install update: {e}"))?;
    app.restart()
}

// ---- shared implementation (also used by the tray menu) ----------------------

/// Send `poll:now` to the daemon. Public so the tray menu can reuse it.
pub async fn do_poll_now(app: &AppHandle) {
    sidecar::send_command(app, r#"{"type":"command","cmd":"poll:now"}"#).await;
}

/// Pause the daemon (tray "Stop Daemon").
pub async fn do_pause_daemon(app: &AppHandle) {
    sidecar::send_command(app, r#"{"type":"command","cmd":"pause"}"#).await;
}

/// Resume the daemon (tray "Start Daemon").
pub async fn do_resume_daemon(app: &AppHandle) {
    sidecar::send_command(app, r#"{"type":"command","cmd":"resume"}"#).await;
}

/// Safe quit: ask the daemon to shut down, wait up to 3 s, then exit the app.
pub async fn do_safe_quit(app: &AppHandle) {
    sidecar::request_shutdown(app).await;
    // Give the supervisor a moment to observe the clean exit.
    tokio::time::sleep(std::time::Duration::from_millis(500)).await;
    app.exit(0);
}

/// Tray "Check for Updates…" entry point: runs the check (reusing the
/// [`check_for_updates`] command) and emits `daemon://update:status` with the
/// result so the frontend can surface it. Errors are folded into the payload as
/// `"error: …"` so the tray click never surfaces a raw panic to the user.
pub async fn do_check_for_updates(app: &AppHandle) {
    let status = check_for_updates(app.clone())
        .await
        .unwrap_or_else(|e| format!("error: {e}"));
    let _ = app.emit("daemon://update:status", status);
}

/// Test GitHub PAT by calling GET /user. Returns the login username on success.
#[tauri::command]
pub async fn test_github_connection(pat: String) -> Result<String, String> {
    let resp = reqwest::Client::new()
        .get("https://api.github.com/user")
        .header("Authorization", format!("Bearer {pat}"))
        .header("User-Agent", "pr-review")
        .send()
        .await
        .map_err(|e| format!("Network error: {e}"))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        return Err(format!("GitHub API {status}: {body}"));
    }

    let json: Value = resp
        .json()
        .await
        .map_err(|e| format!("Parse error: {e}"))?;

    json.get("login")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| "Missing 'login' in response".to_string())
}

/// Test LLM API by sending a minimal chat completion request.
#[tauri::command]
pub async fn test_llm_connection(
    base_url: String,
    api_key: String,
    model: String,
) -> Result<String, String> {
    let url = format!("{}/chat/completions", base_url.trim_end_matches('/'));
    let body = serde_json::json!({
        "model": model,
        "messages": [{"role": "user", "content": "ping"}],
        "max_tokens": 1
    });

    let resp = reqwest::Client::new()
        .post(&url)
        .header("Authorization", format!("Bearer {api_key}"))
        .header("Content-Type", "application/json")
        .json(&body)
        .send()
        .await
        .map_err(|e| format!("Network error: {e}"))?;

    let status = resp.status();
    if status.is_success() {
        Ok("LLM connection OK".to_string())
    } else {
        let text = resp.text().await.unwrap_or_default();
        Err(format!("LLM API {status}: {text}"))
    }
}
/// List available LLM models from the provider's /models endpoint.
#[tauri::command]
pub async fn list_llm_models(
    base_url: String,
    api_key: String,
) -> Result<Vec<String>, String> {
    let url = format!("{}/models", base_url.trim_end_matches('/'));
    let resp = reqwest::Client::new()
        .get(&url)
        .header("Authorization", format!("Bearer {api_key}"))
        .send()
        .await
        .map_err(|e| format!("Network error: {e}"))?;

    let status = resp.status();
    if !status.is_success() {
        let text = resp.text().await.unwrap_or_default();
        return Err(format!("LLM API {status}: {text}"));
    }

    let json: Value = resp
        .json()
        .await
        .map_err(|e| format!("Parse error: {e}"))?;

    let models = json
        .get("data")
        .and_then(|d| d.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|m| m.get("id").and_then(|v| v.as_str()).map(|s| s.to_string()))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    Ok(models)
}

/// Resolve `dbPath` and `logDir` from the Tauri app data directory and inject
/// them into the config object (which may lack them when arriving from the UI).
fn inject_internal_paths(app: &AppHandle, config: &mut Value) {
    let data_dir = app
        .path()
        .app_data_dir()
        .unwrap_or_else(|_| std::path::PathBuf::from("."));

    let obj = config.as_object_mut().expect("config must be a JSON object");
    if !obj.contains_key("dbPath") {
        let db_path = data_dir.join("pr-review.db");
        obj.insert(
            "dbPath".to_string(),
            Value::String(db_path.to_string_lossy().into()),
        );
    }
    if !obj.contains_key("logDir") {
        let log_dir = data_dir.join("logs");
        obj.insert(
            "logDir".to_string(),
            Value::String(log_dir.to_string_lossy().into()),
        );
    }
}
