//! Config persistence + wire framing.
//!
//! `tauri-plugin-store` holds the config under a single `"config"` key in
//! `config.json`. The same JSON value is framed into a `config` command line
//! when forwarding to the daemon stdin.

use serde_json::Value;
use tauri::AppHandle;
use tauri_plugin_store::StoreExt;

const STORE_FILE: &str = "config.json";
const CONFIG_KEY: &str = "config";

/// Read the persisted config, if any.
pub fn read_config(app: &AppHandle) -> Option<Value> {
    let store = app.store(STORE_FILE).ok()?;
    store.get(CONFIG_KEY)
}

/// Persist the config and flush to disk.
pub fn write_config(app: &AppHandle, config: &Value) -> Result<(), String> {
    let store = app.store(STORE_FILE).map_err(|e| e.to_string())?;
    store.set(CONFIG_KEY, config.clone());
    store.save().map_err(|e| e.to_string())?;
    Ok(())
}

/// Frame a config value as a JSON-line `config` command for the daemon stdin.
pub fn config_command_line(config: &Value) -> String {
    let envelope = serde_json::json!({
        "type": "command",
        "cmd": "config",
        "config": config,
    });
    serde_json::to_string(&envelope).unwrap_or_else(|_| "{}".to_string())
}

/// Read config and re-merge secrets from the OS keychain.
///
/// If the config still has plaintext secrets (pre-migration or migration-failed),
/// they are used as-is. Only secrets NOT present in the config are loaded from
/// keychain.
pub fn read_resolved_config(app: &AppHandle) -> Option<Value> {
    let config = read_config(app)?;
    let mut resolved = config;

    let has_gh_pat = resolved
        .get("githubPat")
        .and_then(|v| v.as_str())
        .map(|s| !s.is_empty())
        .unwrap_or(false);

    if !has_gh_pat {
        match crate::secrets::load_github_pat() {
            Ok(pat) => {
                if let Some(obj) = resolved.as_object_mut() {
                    obj.insert("githubPat".to_string(), serde_json::Value::String(pat));
                }
            }
            Err(e) => {
                log::warn!("Failed to load GitHub PAT from keychain: {e}");
                // Continue without the secret — non-secret fields are still valid.
            }
        }
    }

    let has_llm_key = resolved
        .get("llmApiKey")
        .and_then(|v| v.as_str())
        .map(|s| !s.is_empty())
        .unwrap_or(false);

    if !has_llm_key {
        match crate::secrets::load_llm_api_key() {
            Ok(key) => {
                if let Some(obj) = resolved.as_object_mut() {
                    obj.insert("llmApiKey".to_string(), serde_json::Value::String(key));
                }
            }
            Err(e) => {
                log::warn!("Failed to load LLM API key from keychain: {e}");
                // Continue without the secret — non-secret fields are still valid.
            }
        }
    }

    Some(resolved)
}

/// Migrate plaintext secrets from config.json to OS keychain (one-time, idempotent).
/// Order: read plaintext -> store in keychain -> remove from config.json LAST.
pub fn migrate_secrets_to_keychain(app: &AppHandle) {
    let Some(config) = read_config(app) else { return };
    let Some(obj) = config.as_object() else { return };

    let mut needs_rewrite = false;
    let mut redacted = obj.clone();

    // Migrate GitHub PAT
    if let Some(pat) = obj.get("githubPat").and_then(|v| v.as_str()) {
        if !pat.is_empty() {
            match crate::secrets::store_github_pat(pat) {
                Ok(()) => {
                    redacted.remove("githubPat");
                    redacted.insert("githubPatStored".to_string(), serde_json::Value::Bool(true));
                    needs_rewrite = true;
                    log::info!("Migrated GitHub PAT to keychain");
                }
                Err(e) => log::warn!("Failed to migrate GitHub PAT to keychain: {e}"),
            }
        }
    }

    // Migrate LLM API key
    if let Some(key) = obj.get("llmApiKey").and_then(|v| v.as_str()) {
        if !key.is_empty() {
            match crate::secrets::store_llm_api_key(key) {
                Ok(()) => {
                    redacted.remove("llmApiKey");
                    redacted.insert("llmApiKeyStored".to_string(), serde_json::Value::Bool(true));
                    needs_rewrite = true;
                    log::info!("Migrated LLM API key to keychain");
                }
                Err(e) => log::warn!("Failed to migrate LLM API key to keychain: {e}"),
            }
        }
    }

    // Rewrite config WITHOUT secrets LAST (crash-safe: if killed between store and rewrite,
    // next launch re-reads plaintext, re-stores idempotently, re-removes)
    if needs_rewrite {
        let _ = write_config(app, &serde_json::Value::Object(redacted));
    }
}
