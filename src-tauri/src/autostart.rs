#![allow(dead_code)]
//! OS-level autostart at login/boot.
//!
//! Backed by `tauri-plugin-autostart`, which wraps platform-specific mechanisms
//! (LaunchAgent on macOS, Registry on Windows, `.desktop` autostart on Linux).
//! The plugin is registered in `lib.rs::run`; the functions here let the rest
//! of the host enable / disable / query the launch-at-login setting.

use tauri::AppHandle;
use tauri_plugin_autostart::ManagerExt;

/// Enable launch at login. Errors (e.g. permission denied) propagate as strings.
pub fn enable(app: &AppHandle) -> Result<(), String> {
    app.autolaunch()
        .enable()
        .map_err(|e| e.to_string())
}

/// Disable launch at login.
pub fn disable(app: &AppHandle) -> Result<(), String> {
    app.autolaunch()
        .disable()
        .map_err(|e| e.to_string())
}

/// Is launch-at-login currently enabled?
pub fn is_enabled(app: &AppHandle) -> bool {
    app.autolaunch().is_enabled().unwrap_or(false)
}
