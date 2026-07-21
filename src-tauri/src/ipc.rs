//! stdout JSON-line bridge: every daemon event is re-emitted to the frontend.
//!
//! Two channels per event:
//!   - `daemon://<bare-event>` — typed channel (e.g. `daemon://log`,
//!     `daemon://status`, `daemon://poll:found`), and
//!   - `daemon://event`     — generic channel carrying every event.
//! The payload is the parsed JSON object verbatim, so the React side can read
//! any field without a Rust redefinition.

use serde_json::Value;
use tauri::{AppHandle, Emitter};

use crate::sidecar;

/// Parse one stdout line and forward it to the frontend. Updates daemon status.
///
/// Async because it may update shared state behind an async mutex.
pub async fn bridge_line(app: &AppHandle, line: &str) {
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return;
    }

    let value: Value = match serde_json::from_str(trimmed) {
        Ok(v) => v,
        Err(e) => {
            log::warn!("daemon stdout non-JSON: {e}: {trimmed}");
            return;
        }
    };

    let event = value
        .get("event")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");

    // Mirror lifecycle state into shared state + tray color.
    match event {
        "daemon:ready" => {
            // ready implies an online, idle daemon.
            sidecar::set_status(app, true, "idle").await;
        }
        "daemon:status" => {
            let state = value
                .get("state")
                .and_then(|v| v.as_str())
                .unwrap_or("idle");
            sidecar::set_status(app, true, state).await;
        }
        "daemon:error" => {
            if value
                .get("code")
                .and_then(|v| v.as_str())
                .map(|c| c == "fatal")
                .unwrap_or(false)
            {
                sidecar::set_status(app, false, "error").await;
            }
        }
        _ => {}
    }

    // Forward to React.
    //
    // Typed channel: strip the redundant `daemon:` prefix so `daemon:log` →
    // `daemon://log`, `daemon:status` → `daemon://status`, while non-`daemon:`
    // events pass through unchanged (`poll:found` → `daemon://poll:found`).
    let bare = event.strip_prefix("daemon:").unwrap_or(event);
    let typed = format!("daemon://{bare}");
    let _ = app.emit(&typed, value.clone());
    let _ = app.emit("daemon://event", value);
}
