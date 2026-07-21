//! Sidecar lifecycle supervisor.
//!
//! Owns a single daemon child at a time. Responsibilities:
//!   - resolve + spawn the daemon (dev: `node tsx daemon/src/main.ts`,
//!     release: bundled `pr-review-daemon-<triple>` sidecar),
//!   - read stdout line-by-line and bridge each line to the frontend,
//!   - drain stderr to the host's stderr (for dev visibility),
//!   - expose the live child stdin to command handlers,
//!   - on unexpected exit: emit `daemon://daemon:error`, back off, restart,
//!   - honor an intentional shutdown flag (no restart).
//!
//! Config delivery: whenever a daemon comes online, the last persisted config
//! is re-sent so a restarted daemon resumes with the user's settings.

use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::Duration;

use tauri::{AppHandle, Emitter, Manager};
use tauri::async_runtime::{self, Mutex};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{Child, ChildStdin, ChildStdout, Command};
use tokio::time::sleep;

use crate::config_store;
use crate::ipc;
use crate::tray;
use crate::{DaemonStatus, ShutdownFlag, SidecarStdin, StatusValue};

/// Start the supervisor task. Idempotent: call once from `setup`.
pub fn start(app: AppHandle) {
    async_runtime::spawn(async move {
        run_supervisor(app).await;
    });
}

/// Write a single JSON-line command to the live daemon's stdin (no-op if down).
pub async fn send_command(app: &AppHandle, line: &str) {
    let Some(state) = app.try_state::<SidecarStdin>() else {
        return;
    };
    let mut guard = state.0.lock().await;
    if let Some(stdin) = guard.as_mut() {
        if let Err(e) = stdin.write_all(format!("{line}\n").as_bytes()).await {
            log::warn!("daemon stdin write failed: {e}");
        }
        let _ = stdin.flush().await;
    }
}

/// Send `shutdown` and flip the flag so the supervisor does not restart.
pub async fn request_shutdown(app: &AppHandle) {
    if let Some(flag) = app.try_state::<ShutdownFlag>() {
        flag.0.store(true, Ordering::SeqCst);
    }
    send_command(app, r#"{"type":"command","cmd":"shutdown"}"#).await;
}

async fn run_supervisor(app: AppHandle) {
    eprintln!("[supervisor] started");
    let stdin: Arc<Mutex<Option<ChildStdin>>> = app
        .state::<SidecarStdin>()
        .0
        .clone();
    let shutdown = app.state::<ShutdownFlag>().0.clone();

    let mut backoff = Duration::from_secs(1);
    loop {
        if shutdown.load(Ordering::SeqCst) {
            break;
        }

        let child = match spawn_daemon(&app).await {
            Ok(child) => {
                backoff = Duration::from_secs(1);
                child
            }
            Err(e) => {
                log::error!("failed to spawn daemon: {e}");
                let _ = app.emit(
                    "daemon://daemon:error",
                    serde_json::json!({ "code": "spawn_failed", "err": format!("{e}") }),
                );
                set_status(&app, false, "error").await;
                sleep(backoff).await;
                backoff = (backoff * 2).min(Duration::from_secs(60));
                continue;
            }
        };

        eprintln!("[supervisor] child spawned; entering supervise_child");
        supervise_child(&app, child, &stdin).await;
        eprintln!("[supervisor] supervise_child returned (daemon exited); backoff={:?}", backoff);

        if shutdown.load(Ordering::SeqCst) {
            break;
        }

        // Unexpected exit — notify + backoff before restart.
        log::warn!("daemon crashed/exited; scheduling restart in {:?}", backoff);
        let _ = app.emit(
            "daemon://daemon:error",
            serde_json::json!({ "code": "daemon_crashed", "err": "daemon exited; restarting" }),
        );
        set_status(&app, false, "offline").await;
        sleep(backoff).await;
        backoff = (backoff * 2).min(Duration::from_secs(60));
    }

    log::info!("sidecar supervisor stopped");
    *stdin.lock().await = None;
}

/// Drive one child until it exits: publish its stdin, bridge stdout, drain
/// stderr, then reap the exit status.
async fn supervise_child(
    app: &AppHandle,
    mut child: Child,
    stdin: &Arc<Mutex<Option<ChildStdin>>>,
) {
    let stdout: ChildStdout = child.stdout.take().expect("piped stdout");
    let stderr = child.stderr.take();
    let child_stdin: ChildStdin = child.stdin.take().expect("piped stdin");

    *stdin.lock().await = Some(child_stdin);

    set_status(app, true, "idle").await;

    // Re-deliver persisted config so a freshly-spawned daemon resumes state.
    // B1 FIX: use read_resolved_config to re-merge secrets from keychain
    if let Some(cfg) = config_store::read_resolved_config(app) {
        send_command(app, &config_store::config_command_line(&cfg)).await;
    } else {
        // Keychain failure or no config — emit secret_unavailable, do NOT send
        let _ = app.emit("daemon://daemon:error", serde_json::json!({
            "type": "event",
            "event": "daemon:error",
            "code": "secret_unavailable",
            "message": "Failed to load secrets from keychain"
        }));
    }

    // stdout -> frontend bridge (line-buffered).
    let app_r = app.clone();
    let reader = async_runtime::spawn(async move {
        let mut lines = BufReader::new(stdout).lines();
        loop {
            match lines.next_line().await {
                Ok(Some(line)) => ipc::bridge_line(&app_r, &line).await,
                Ok(None) => break,
                Err(e) => {
                    log::warn!("daemon stdout read error: {e}");
                    break;
                }
            }
        }
    });

    // stderr -> host stderr (dev visibility; never the event channel).
    if let Some(stderr) = stderr {
        async_runtime::spawn(async move {
            let mut lines = BufReader::new(stderr).lines();
            while let Ok(Some(line)) = lines.next_line().await {
                eprintln!("[daemon] {line}");
            }
        });
    }

    let status = child.wait().await;
    eprintln!("[supervisor] child.wait() returned: {:?}", status);

    // Detach our stdin reference; the child is gone.
    *stdin.lock().await = None;

    // Let the reader drain final buffered output before we restart.
    let _ = reader.await;
}

async fn spawn_daemon(app: &AppHandle) -> std::io::Result<Child> {
    let (program, args) = resolve_command(app);
    log::info!("spawning daemon: {program} {}", args.join(" "));
    let mut cmd = Command::new(program);
    cmd.args(args);
    cmd.stdin(std::process::Stdio::piped());
    cmd.stdout(std::process::Stdio::piped());
    cmd.stderr(std::process::Stdio::piped());
    cmd.spawn()
}

/// Resolve the daemon launch command, in priority order:
///   1. `PR_DAEMON_BIN` env override (dev convenience),
///   2. dev: `node <root>/node_modules/tsx/dist/cli.mjs <root>/daemon/src/main.ts`
///      (root derived from `CARGO_MANIFEST_DIR` at compile time),
///   3. release: bundled sidecar binary next to the resources.
fn resolve_command(app: &AppHandle) -> (String, Vec<String>) {
    if let Ok(bin) = std::env::var("PR_DAEMON_BIN") {
        if !bin.is_empty() {
            return (bin, vec![]);
        }
    }

    if cfg!(debug_assertions) {
        if let Some(root) = dev_project_root() {
            let node = std::env::var("NODE").unwrap_or_else(|_| "node".to_string());
            let tsx = root.join("node_modules/tsx/dist/cli.mjs");
            let main = root.join("daemon/src/main.ts");
            if tsx.exists() && main.exists() {
                return (
                    node,
                    vec![
                        tsx.to_string_lossy().into_owned(),
                        main.to_string_lossy().into_owned(),
                    ],
                );
            }
        }
    }

    if let Ok(path) = bundled_binary(app) {
        return (path.to_string_lossy().into_owned(), vec![]);
    }

    ("pr-review-daemon".to_string(), vec![])
}

/// Project root in dev = parent of this crate's `Cargo.toml` dir.
fn dev_project_root() -> Option<std::path::PathBuf> {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .map(std::path::Path::to_path_buf)
}

fn bundled_binary(_app: &AppHandle) -> std::io::Result<std::path::PathBuf> {
    // Tauri's `externalBin` bundles the sidecar next to the main executable
    // (e.g. `Contents/MacOS/` on macOS) with the target triple stripped from the
    // file name. Resolve relative to the current executable so the release
    // binary finds it regardless of install location.
    let exe = std::env::current_exe()?;
    let dir = exe
        .parent()
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::Other, "no executable parent dir"))?;
    let mut name = "pr-review-daemon".to_string();
    if cfg!(windows) {
        name.push_str(".exe");
    }
    Ok(dir.join(name))
}

/// Update the shared status + tray color.
pub(crate) async fn set_status(app: &AppHandle, online: bool, state: &str) {
    if let Some(s) = app.try_state::<DaemonStatus>() {
        let mut guard = s.0.lock().await;
        guard.online = online;
        guard.state = state.to_string();
    }
    tray::set_status(app, online, state);
}

/// Read a snapshot of the current status (for the `daemon_status` command).
pub(crate) async fn snapshot_status(app: &AppHandle) -> StatusValue {
    match app.try_state::<DaemonStatus>() {
        Some(s) => s.0.lock().await.clone(),
        None => StatusValue::default(),
    }
}
