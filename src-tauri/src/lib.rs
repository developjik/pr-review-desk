//! PR Review desktop app — Rust host (Tauri 2).
//!
//! The host owns the process lifecycle of a Node sidecar daemon. It spawns the
//! daemon, bridges its stdout JSON-line events to the React frontend, writes
//! commands to its stdin, persists config via `tauri-plugin-store`, provides a
//! system tray with live status color, fires OS notifications on completed
//! reviews, enables launch-at-login, and enforces single-instance.

mod autostart;
mod commands;
mod secrets;
mod config_store;
mod ipc;
mod sidecar;
mod single_instance;
mod tray;

use std::sync::atomic::AtomicBool;
use std::sync::Arc;

use serde::Serialize;
use serde_json::Value;
use tauri::async_runtime::Mutex;
use tauri::{Listener, Manager};
use tauri_plugin_autostart::MacosLauncher;
use tauri_plugin_notification::NotificationExt;

/// Process-wide view of the daemon's lifecycle, mirrored from the wire and
/// surfaced to the tray + the `daemon_status` command.
#[derive(Default)]
pub struct DaemonStatus(pub Arc<Mutex<StatusValue>>);

#[derive(Clone, Default, Serialize)]
pub struct StatusValue {
    /// True once the supervisor has spawned a daemon child that has not exited.
    pub online: bool,
    /// Last `daemon:status.state` received ("idle" before the first status).
    pub state: String,
}

/// Shared by the supervisor + command handlers to write to the live child stdin.
pub struct SidecarStdin(pub Arc<Mutex<Option<tokio::process::ChildStdin>>>);

/// Set when the user requests an intentional shutdown (vs. a crash to restart).
pub struct ShutdownFlag(pub Arc<AtomicBool>);

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // single-instance must be registered before window creation.
        .plugin(single_instance::plugin())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_shell::init())
        // Launch at login (macOS LaunchAgent / Linux .desktop / Windows Registry).
        .plugin(tauri_plugin_autostart::init(
            MacosLauncher::LaunchAgent,
            None,
        ))
        .plugin(tauri_plugin_notification::init())
        .on_window_event(|window, event| {
            // Safe shutdown: intercept window close, send shutdown to the
            // daemon, wait briefly, then exit the app.
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                let app = window.app_handle().clone();
                api.prevent_close();
                tauri::async_runtime::spawn(async move {
                    commands::do_safe_quit(&app).await;
                });
            }
        })
        .setup(|app| {
            // Build state shared across modules.
            let stdin = Arc::new(Mutex::new(None::<tokio::process::ChildStdin>));
            let shutdown = Arc::new(AtomicBool::new(false));
            app.manage(SidecarStdin(stdin));
            app.manage(ShutdownFlag(shutdown));
            app.manage(DaemonStatus::default());
            // One-time migration of plaintext secrets to keychain
            config_store::migrate_secrets_to_keychain(app.handle());

            // System tray (menu + live status color).
            tray::build(app.handle())?;

            // OS notification when a review is published.
            let app_handle = app.handle().clone();
            app.listen("daemon://publish:review", move |event| {
                fire_review_notification(&app_handle, event.payload());
            });

            // Spawn the sidecar supervisor (stdout/stdin bridge + crash restart).
            sidecar::start(app.handle().clone());

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_config,
            commands::save_config,
            commands::poll_now,
            commands::pause_daemon,
            commands::resume_daemon,
            commands::approve_review,
            commands::reject_review,
            commands::list_pending_reviews,
            commands::daemon_status,
            commands::test_github_connection,
            commands::test_llm_connection,
            commands::list_llm_models,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

/// Fire an OS notification when a review has been published.
///
/// Respects the `osNotify` config flag: if the user has disabled notifications,
/// the event is silently ignored.
fn fire_review_notification(app: &tauri::AppHandle, payload: &str) {
    // Check the osNotify setting before firing.
    if let Some(cfg) = config_store::read_config(app) {
        let enabled = cfg
            .get("osNotify")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        if !enabled {
            return;
        }
    }

    let body = match serde_json::from_str::<Value>(payload) {
        Ok(v) => {
            let pr = v.get("prId").and_then(|n| n.as_i64()).unwrap_or(0);
            let posted = v.get("posted").and_then(|n| n.as_i64()).unwrap_or(0);
            format!("PR #{pr}: {posted} comment(s) posted")
        }
        Err(_) => "PR review posted".to_string(),
    };
    let _ = app
        .notification()
        .builder()
        .title("PR Review")
        .body(&body)
        .show();
}
