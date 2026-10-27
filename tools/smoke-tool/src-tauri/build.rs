fn main() {
    if std::env::var("PROFILE").as_deref() == Ok("release") && tauri_build::is_dev() {
        panic!("Portable releases must embed the interface. Use tauri build or cargo build --release --features custom-protocol.");
    }
    tauri_build::build()
}
