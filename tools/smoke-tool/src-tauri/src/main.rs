#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod service;
use serde::Serialize;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use tauri::{Emitter, Manager};

#[derive(Default)]
struct Jobs(Arc<AtomicBool>);
struct BusyGuard(Arc<AtomicBool>);
impl Drop for BusyGuard {
    fn drop(&mut self) {
        self.0.store(false, Ordering::Release);
    }
}

#[derive(Clone, Serialize)]
struct LogLine {
    line: String,
}

#[tauri::command]
async fn bootstrap() -> Result<service::Bootstrap, String> {
    tauri::async_runtime::spawn_blocking(service::bootstrap)
        .await
        .map_err(|e| e.to_string())?
}

#[tauri::command]
async fn inspect_game(game_directory: String) -> Result<service::ClientStatus, String> {
    tauri::async_runtime::spawn_blocking(move || {
        service::inspect_game(&service::bundle_root()?, &game_directory)
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
async fn pick_path(kind: String) -> Result<Vec<String>, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let dialog = rfd::FileDialog::new();
        let paths = match kind.as_str() {
            "game" => dialog
                .set_title("Select your CoD2MP_s.exe")
                .add_filter("CoD2 Multiplayer", &["exe"])
                .pick_file()
                .map(|p| vec![p]),
            "maps" => dialog
                .set_title("Select compiled CoD2 maps")
                .add_filter("CoD2 compiled maps", &["d3dbsp"])
                .pick_files(),
            "output" => dialog
                .set_title("Choose bake output folder")
                .pick_folder()
                .map(|p| vec![p]),
            _ => return Err("Unknown picker".into()),
        };
        Ok(paths
            .unwrap_or_default()
            .into_iter()
            .map(|p| p.to_string_lossy().into_owned())
            .collect())
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
async fn run_job(
    app: tauri::AppHandle,
    jobs: tauri::State<'_, Jobs>,
    request: service::Request,
) -> Result<service::JobResult, String> {
    if jobs
        .0
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        return Err("Another operation is still running.".into());
    }
    let guard = BusyGuard(jobs.0.clone());
    tauri::async_runtime::spawn_blocking(move || {
        let _guard = guard;
        let log = |line: String| {
            let _ = app.emit("job-log", LogLine { line });
        };
        service::execute(&service::bundle_root()?, request, &log)
    })
    .await
    .map_err(|e| e.to_string())?
}

fn main() {
    // A read-only check is also available to build scripts without opening the UI.
    let mode = std::env::args().nth(1);
    if matches!(
        mode.as_deref(),
        Some("--validate-bundle" | "--validate-runtime")
    ) {
        if cfg!(dev) {
            eprintln!("This is a development build and cannot be packaged. Rebuild with the custom-protocol feature.");
            std::process::exit(1);
        }
        let result = service::bundle_root().and_then(|root| {
            if mode.as_deref() == Some("--validate-runtime") {
                service::validate_runtime(&root, &|s| println!("{s}"))
            } else {
                service::validate_bundle(&root, &|s| println!("{s}"))
            }
        });
        if let Err(error) = result {
            eprintln!("{error}");
            std::process::exit(1);
        }
        return;
    }
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _, _| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.unminimize();
                let _ = window.set_focus();
            }
        }))
        .manage(Jobs::default())
        .invoke_handler(tauri::generate_handler![
            bootstrap,
            inspect_game,
            pick_path,
            run_job
        ])
        .on_window_event(|window, event| {
            // Do not interrupt a backup/restore or leave a bake worker orphaned.
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                if window.state::<Jobs>().0.load(Ordering::Acquire) {
                    api.prevent_close();
                    let _ = window.emit(
                        "job-log",
                        LogLine {
                            line: "Wait for the current operation to finish before closing.".into(),
                        },
                    );
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("Unable to start CoD2 Smoke Tool");
}
