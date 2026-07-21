//! Single-instance enforcement.
//!
//! Backed by `tauri-plugin-single-instance`. The plugin guarantees only the
//! first app process runs; subsequent launches are routed here, where we simply
//! focus the existing main window.

use tauri::{AppHandle, Manager, Wry};

/// Construct the single-instance plugin with our second-instance handler.
pub fn plugin() -> tauri::plugin::TauriPlugin<Wry> {
    tauri_plugin_single_instance::init(handler)
}

/// Called in the *second* process: raise the first process's window to front.
fn handler(app: &AppHandle, _args: Vec<String>, _cwd: String) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
    }
}
