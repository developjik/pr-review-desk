//! System tray: menu + live status color.
//!
//! Color reflects daemon state:
//!   idle      -> gray
//!   active    -> green  (polling / reviewing / publishing)
//!   error     -> red
//!   offline   -> dim/transparent ("none")
//! The icon is generated at runtime as a small solid RGBA image so no asset
//! files are required.

use tauri::image::Image;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::{TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Manager};

use crate::commands;

const TRAY_ID: &str = "pr-review-tray";

/// Build the tray icon + menu. Call once from `setup`.
pub fn build(app: &AppHandle) -> tauri::Result<()> {
    let show = MenuItem::with_id(app, "show", "Open settings", true, None::<&str>)?;
    let start = MenuItem::with_id(app, "start", "Start daemon", true, None::<&str>)?;
    let stop = MenuItem::with_id(app, "stop", "Stop daemon", true, None::<&str>)?;
    let poll = MenuItem::with_id(app, "poll", "Poll now", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &start, &stop, &poll, &quit])?;

    let _tray = TrayIconBuilder::with_id(TRAY_ID)
        .icon(solid_icon(TrayColor::Offline))
        .tooltip("PR Review — starting")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "show" => show_window(app),
            "start" => {
                let app = app.clone();
                tauri::async_runtime::spawn(async move {
                    commands::do_resume_daemon(&app).await;
                });
            }
            "stop" => {
                let app = app.clone();
                tauri::async_runtime::spawn(async move {
                    commands::do_pause_daemon(&app).await;
                });
            }
            "poll" => {
                let app = app.clone();
                tauri::async_runtime::spawn(async move {
                    commands::do_poll_now(&app).await;
                });
            }
            "quit" => {
                let app = app.clone();
                tauri::async_runtime::spawn(async move {
                    commands::do_safe_quit(&app).await;
                });
            }
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::DoubleClick { .. } = event {
                show_window(tray.app_handle());
            }
        })
        .build(app)?;

    Ok(())
}

/// Update the tray icon color + tooltip from daemon status.
pub fn set_status(app: &AppHandle, online: bool, state: &str) {
    let Some(tray) = app.tray_by_id(TRAY_ID) else {
        return;
    };
    let (color, label) = appearance(online, state);
    let _ = tray.set_icon(Some(solid_icon(color)));
    let _ = tray.set_tooltip(Some(format!("PR Review — {label}")));
}

fn show_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
    }
}

fn appearance(online: bool, state: &str) -> (TrayColor, &'static str) {
    if !online {
        return (TrayColor::Offline, "offline");
    }
    match state {
        "polling" | "reviewing" | "publishing" => (TrayColor::Green, "active"),
        "error" => (TrayColor::Red, "error"),
        _ => (TrayColor::Gray, "idle"),
    }
}

enum TrayColor {
    Gray,
    Green,
    Red,
    /// Dim/transparent: used when the daemon process is offline ("none").
    Offline,
}

/// 22x22 RGBA. Small enough to keep four buffers resident without concern.
const ICON_SIZE: usize = 22;
const ICON_PIXELS: usize = ICON_SIZE * ICON_SIZE;
const ICON_BYTES: usize = ICON_PIXELS * 4;

/// Build a flat RGBA buffer at compile time (no runtime allocation, no leak).
const fn make_buf(r: u8, g: u8, b: u8, a: u8) -> [u8; ICON_BYTES] {
    let mut buf = [0u8; ICON_BYTES];
    let mut i = 0;
    while i < ICON_PIXELS {
        buf[i * 4] = r;
        buf[i * 4 + 1] = g;
        buf[i * 4 + 2] = b;
        buf[i * 4 + 3] = a;
        i += 1;
    }
    buf
}

static ICON_GRAY: [u8; ICON_BYTES] = make_buf(150, 150, 150, 255);
static ICON_GREEN: [u8; ICON_BYTES] = make_buf(40, 200, 80, 255);
static ICON_RED: [u8; ICON_BYTES] = make_buf(220, 50, 50, 255);
static ICON_OFFLINE: [u8; ICON_BYTES] = make_buf(60, 60, 60, 120);

/// Pick the precomputed RGBA buffer for a color and wrap it in a tray image.
fn solid_icon(color: TrayColor) -> Image<'static> {
    let buf: &'static [u8] = match color {
        TrayColor::Gray => &ICON_GRAY,
        TrayColor::Green => &ICON_GREEN,
        TrayColor::Red => &ICON_RED,
        TrayColor::Offline => &ICON_OFFLINE,
    };
    Image::new(buf, ICON_SIZE as u32, ICON_SIZE as u32)
}
