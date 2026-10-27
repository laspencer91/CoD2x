use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
#[cfg(windows)]
use std::os::windows::process::CommandExt;
use std::{
    collections::BTreeMap,
    fs,
    io::{BufRead, BufReader, Read},
    path::{Component, Path, PathBuf},
    process::{Command, Stdio},
};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Request {
    pub action: Action,
    #[serde(default)]
    pub game_directory: String,
    #[serde(default)]
    pub map: String,
    #[serde(default)]
    pub inputs: Vec<String>,
    #[serde(default)]
    pub output: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Action {
    Check,
    Install,
    Verify,
    Uninstall,
    QuickTest,
    TrySmoke,
    Bake,
    ValidateBundle,
    OpenOutput,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JobResult {
    pub message: String,
    pub outputs: Vec<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Candidate {
    pub path: String,
    pub source: String,
    pub steam: bool,
    pub installed: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Bootstrap {
    pub bundle_root: String,
    pub candidates: Vec<Candidate>,
    pub suggested_output: String,
    pub remembered_game: String,
    pub baker_available: bool,
}

fn hidden(command: &mut Command) -> &mut Command {
    #[cfg(windows)]
    command.creation_flags(0x08000000);
    command
}

pub fn bundle_root() -> Result<PathBuf, String> {
    let executable = std::env::current_exe().map_err(|e| e.to_string())?;
    let beside_exe = executable.parent().ok_or("Missing executable directory")?;
    if beside_exe.join("Smoke-Test.ps1").is_file() && beside_exe.join("manifest.json").is_file() {
        return Ok(beside_exe.to_path_buf());
    }
    // Source-checkout fallback is development-only. Release builds are relocatable.
    #[cfg(debug_assertions)]
    {
        let source = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../smoke/prebuilt");
        if source.join("manifest.json").is_file() {
            return source.canonicalize().map_err(|e| e.to_string());
        }
    }
    Err("Keep CoD2SmokeTool.exe beside Smoke-Test.ps1, manifest.json and the runtime/tools folders from the ZIP.".into())
}

fn registry_value(key: &str, name: &str) -> Option<String> {
    let system = PathBuf::from(std::env::var_os("SystemRoot")?);
    let output =
        hidden(Command::new(system.join("System32/reg.exe")).args(["query", key, "/v", name]))
            .output()
            .ok()?;
    if !output.status.success() {
        return None;
    }
    String::from_utf8_lossy(&output.stdout)
        .lines()
        .find_map(|line| {
            line.split_once("REG_SZ")
                .map(|(_, value)| value.trim().to_owned())
        })
}

// Valve's quoted VDF values; handle escaped Windows paths without assuming library numbers.
fn quoted_values(text: &str) -> Vec<String> {
    let mut values = Vec::new();
    let mut chars = text.chars();
    while let Some(c) = chars.next() {
        if c != '"' {
            continue;
        }
        let mut value = String::new();
        while let Some(c) = chars.next() {
            match c {
                '"' => break,
                '\\' => {
                    if let Some(next) = chars.next() {
                        value.push(next);
                    }
                }
                _ => value.push(c),
            }
        }
        values.push(value);
    }
    values
}

fn is_steam(path: &Path) -> bool {
    path.components().any(|part| {
        part.as_os_str()
            .to_string_lossy()
            .eq_ignore_ascii_case("steamapps")
    })
}

pub fn bootstrap() -> Result<Bootstrap, String> {
    let root = bundle_root()?;
    let remembered_game = fs::read(root.join("test-installation.json"))
        .ok()
        .and_then(|b| serde_json::from_slice::<serde_json::Value>(&b).ok())
        .and_then(|v| v["gameDirectory"].as_str().map(str::to_owned))
        .unwrap_or_default();
    let mut candidates = Vec::new();
    let mut add = |path: PathBuf, source: &str| {
        if path.join("CoD2MP_s.exe").is_file()
            && !candidates
                .iter()
                .any(|c: &Candidate| c.path.eq_ignore_ascii_case(&path.to_string_lossy()))
        {
            candidates.push(Candidate {
                installed: path.join("cod2-smoke-test-install.json").is_file(),
                steam: is_steam(&path),
                path: path.to_string_lossy().into_owned(),
                source: source.into(),
            });
        }
    };
    if !remembered_game.is_empty() {
        add(PathBuf::from(&remembered_game), "Previous selection");
    }
    for path in [
        r"C:\Games\CoD2-Smoke-Test",
        r"C:\Games\Call of Duty 2",
        r"D:\Games\CoD2-Smoke-Test",
        r"D:\Games\Call of Duty 2",
    ] {
        add(PathBuf::from(path), "Game folder");
    }
    for key in [
        r"HKLM\SOFTWARE\Activision\Call of Duty 2",
        r"HKLM\SOFTWARE\WOW6432Node\Activision\Call of Duty 2",
    ] {
        if let Some(path) = registry_value(key, "InstallPath") {
            add(PathBuf::from(path), "CoD2 registry");
        }
    }
    let mut libraries = vec![
        PathBuf::from(r"C:\Program Files (x86)\Steam"),
        PathBuf::from(r"C:\Games\Steam"),
    ];
    if let Some(path) = registry_value(r"HKCU\Software\Valve\Steam", "SteamPath") {
        libraries.insert(0, PathBuf::from(path));
    }
    for steam in libraries.clone() {
        if let Ok(text) = fs::read_to_string(steam.join("steamapps/libraryfolders.vdf")) {
            let values = quoted_values(&text);
            for pair in values.windows(2) {
                if pair[0] == "path" {
                    libraries.push(PathBuf::from(&pair[1]));
                }
            }
        }
    }
    for library in libraries {
        if let Ok(text) = fs::read_to_string(library.join("steamapps/appmanifest_2630.acf")) {
            let values = quoted_values(&text);
            if let Some(pair) = values.windows(2).find(|pair| pair[0] == "installdir") {
                let relative = Path::new(&pair[1]);
                if relative
                    .components()
                    .all(|c| matches!(c, Component::Normal(_)))
                {
                    add(
                        library.join("steamapps/common").join(relative),
                        "Steam library",
                    );
                }
            }
        }
    }
    let local = std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    Ok(Bootstrap {
        baker_available: authoring_available(&root),
        bundle_root: root.to_string_lossy().into_owned(),
        candidates,
        suggested_output: local
            .join("CoD2SmokeTool/bakes")
            .to_string_lossy()
            .into_owned(),
        remembered_game,
    })
}

#[derive(Deserialize)]
struct Manifest {
    files: BTreeMap<String, FileEntry>,
}
#[derive(Deserialize)]
struct FileEntry {
    bytes: u64,
    sha256: String,
}

const RUNTIME_REQUIRED: &[&str] = &[
    "Smoke-Test.ps1",
    "provenance/bridge-build.json",
    "runtime/mss32.dll",
    "runtime/mapkit-smoke/mapkit_smoke.dll",
    "runtime/mapkit-smoke/noise128.rgba",
    "runtime/mapkit-smoke/smoke.shaders",
    "runtime/mapkit_smoke_test/mapkit_smoke_stock.iwd",
    "runtime/mapkit_smoke_test/smoke_look_wide.cfg",
];
const AUTHORING_REQUIRED: &[&str] = &[
    "tools/smoke-bake/bake.py",
    "tools/smoke-bake/python/python.exe",
    "tools/smoke-bake/bin/cod2smoke-bake.exe",
];

fn authoring_available(root: &Path) -> bool {
    AUTHORING_REQUIRED
        .iter()
        .all(|name| root.join(name).is_file())
}

#[derive(Clone, Copy, PartialEq)]
enum ValidationScope {
    Runtime,
    Authoring,
    Complete,
}

pub fn validate_bundle(root: &Path, log: &(dyn Fn(String) + Sync)) -> Result<(), String> {
    validate_files(root, ValidationScope::Complete, log)
}

pub fn validate_runtime(root: &Path, log: &(dyn Fn(String) + Sync)) -> Result<(), String> {
    validate_files(root, ValidationScope::Runtime, log)
}

fn validate_files(
    root: &Path,
    scope: ValidationScope,
    log: &(dyn Fn(String) + Sync),
) -> Result<(), String> {
    let manifest: Manifest =
        serde_json::from_slice(&fs::read(root.join("manifest.json")).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
    let required = RUNTIME_REQUIRED.iter().chain(
        AUTHORING_REQUIRED
            .iter()
            .filter(|_| scope == ValidationScope::Authoring),
    );
    for &required in required {
        if !manifest.files.contains_key(required) {
            return Err(format!("Incomplete portable bundle: {required}"));
        }
    }
    let mut checked = 0;
    for (name, entry) in &manifest.files {
        let path = Path::new(name);
        if name.contains('\\')
            || !path.components().all(|c| matches!(c, Component::Normal(_)))
            || path.as_os_str().is_empty()
        {
            return Err(format!("Invalid bundle path: {name}"));
        }
        if scope == ValidationScope::Runtime
            && !name.starts_with("runtime/")
            && !matches!(
                name.as_str(),
                "Smoke-Test.ps1" | "provenance/bridge-build.json" | "CoD2SmokeTool.exe"
            )
        {
            continue;
        }
        let mut target = root.to_path_buf();
        for part in path.components() {
            target.push(part);
            let metadata = fs::symlink_metadata(&target).map_err(|e| format!("{name}: {e}"))?;
            #[cfg(windows)]
            {
                use std::os::windows::fs::MetadataExt;
                if metadata.file_attributes() & 0x400 != 0 {
                    return Err(format!("Linked bundle path: {name}"));
                }
            }
            if metadata.file_type().is_symlink() {
                return Err(format!("Linked bundle path: {name}"));
            }
        }
        let data = fs::read(&target).map_err(|e| format!("{name}: {e}"))?;
        if data.len() as u64 != entry.bytes
            || format!("{:x}", Sha256::digest(&data)) != entry.sha256
        {
            return Err(format!(
                "Missing or changed bundle file: {name}. Extract a fresh ZIP."
            ));
        }
        checked += 1;
    }
    log(format!(
        "Bundle validated: {} files match their SHA256 hashes.",
        checked
    ));
    Ok(())
}

fn absolute_path(value: &str) -> Result<PathBuf, String> {
    let path = PathBuf::from(value);
    if value.trim().is_empty() || !path.is_absolute() {
        return Err("Choose an absolute file or folder path.".into());
    }
    Ok(path)
}

fn pump(pipe: impl Read, log: &(dyn Fn(String) + Sync)) {
    // A non-UTF8 Windows path must not stop draining the process log.
    for bytes in BufReader::new(pipe).split(b'\n').map_while(Result::ok) {
        log(String::from_utf8_lossy(&bytes)
            .trim_end_matches('\r')
            .to_owned());
    }
}

fn run(command: &mut Command, log: &(dyn Fn(String) + Sync)) -> Result<(), String> {
    let mut child = hidden(command)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| e.to_string())?;
    let stdout = child.stdout.take().ok_or("Missing process stdout")?;
    let stderr = child.stderr.take().ok_or("Missing process stderr")?;
    // Drain both pipes concurrently so verbose errors cannot deadlock a job.
    std::thread::scope(|scope| {
        scope.spawn(|| pump(stdout, log));
        scope.spawn(|| pump(stderr, log));
        let status = child.wait().map_err(|e| e.to_string())?;
        if status.success() {
            Ok(())
        } else {
            Err(format!(
                "Operation failed (exit {}). See the activity log.",
                status.code().unwrap_or(-1)
            ))
        }
    })
}

fn installer(
    root: &Path,
    action: &str,
    game: &Path,
    map: &str,
    check_only: bool,
    log: &(dyn Fn(String) + Sync),
) -> Result<(), String> {
    let system = std::env::var_os("SystemRoot")
        .map(PathBuf::from)
        .ok_or("SystemRoot is unavailable")?;
    let mut command = Command::new(system.join("System32/WindowsPowerShell/v1.0/powershell.exe"));
    command
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
        ])
        .arg(root.join("Smoke-Test.ps1"))
        .args(["-Action", action, "-GameDirectory"])
        .arg(game)
        .current_dir(root);
    if action == "Launch" || action == "Try" {
        command.args(["-Map", map]);
    }
    if check_only {
        command.arg("-CheckOnly");
    }
    run(&mut command, log)
}

fn valid_map(name: &str) -> bool {
    name.starts_with("mp_")
        && (4..=31).contains(&name.len())
        && name
            .bytes()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_')
}

pub fn execute(
    root: &Path,
    request: Request,
    log: &(dyn Fn(String) + Sync),
) -> Result<JobResult, String> {
    let mut outputs = Vec::new();
    let message = match request.action {
        Action::OpenOutput => {
            let path = absolute_path(&request.output)?;
            if !path.is_dir() {
                return Err("The output folder does not exist yet.".into());
            }
            // Shell-open only a directory, never a command supplied by the frontend.
            let system = std::env::var_os("SystemRoot")
                .map(PathBuf::from)
                .ok_or("SystemRoot is unavailable")?;
            Command::new(system.join("explorer.exe"))
                .arg(path)
                .spawn()
                .map_err(|e| e.to_string())?;
            "Opened output folder."
        }
        Action::ValidateBundle => {
            validate_bundle(root, log)?;
            "Bundle integrity checks passed."
        }
        Action::Bake => {
            if request.inputs.is_empty() {
                return Err("Select at least one compiled .d3dbsp map.".into());
            }
            let output = absolute_path(&request.output)?;
            let mut inputs = Vec::new();
            let mut names = Vec::new();
            for value in &request.inputs {
                let source = absolute_path(value)?
                    .canonicalize()
                    .map_err(|e| e.to_string())?;
                let name = source
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .ok_or("Invalid map filename")?;
                if !valid_map(name)
                    || source
                        .extension()
                        .and_then(|s| s.to_str())
                        .is_none_or(|s| !s.eq_ignore_ascii_case("d3dbsp"))
                {
                    return Err(
                        "Choose compiled mp_*.d3dbsp files, not Radiant .map sources.".into(),
                    );
                }
                if names.contains(&name.to_owned()) {
                    return Err(format!(
                        "Duplicate map name: {name}. Bake different versions separately."
                    ));
                }
                names.push(name.to_owned());
                outputs.push(
                    output
                        .join(name)
                        .join(format!("mapkit_smoke_{name}.iwd"))
                        .to_string_lossy()
                        .into_owned(),
                );
                inputs.push(source);
            }
            log("Checking bundled tools before baking...".into());
            validate_files(root, ValidationScope::Authoring, log)?;
            let baker = root.join("tools/smoke-bake");
            let mut command = Command::new(baker.join("python/python.exe"));
            command
                .arg("-B")
                .arg("-u")
                .args(["-X", "utf8"])
                .arg(baker.join("bake.py"))
                .args(&inputs)
                .arg("--output")
                .arg(&output)
                .current_dir(&baker);
            run(&mut command, log)?;
            for path in &outputs {
                if !Path::new(path).is_file() {
                    return Err(format!("Baker did not produce {path}"));
                }
            }
            "Baking finished. Copy the occupancy IWDs into the active game/server mod folder."
        }
        action => {
            let game = absolute_path(&request.game_directory)?;
            if !game.join("CoD2MP_s.exe").is_file() {
                return Err("Choose the folder containing CoD2MP_s.exe.".into());
            }
            validate_runtime(root, log)?;
            match action {
                Action::TrySmoke => {
                    if !valid_map(&request.map) {
                        return Err("Enter a map name such as mp_toujane.".into());
                    }
                    log(
                        "Checking compatibility, preserving original files and preparing smoke..."
                            .into(),
                    );
                    installer(root, "Try", &game, &request.map, false, log)?;
                    "Smoke launched. Join a team and throw a smoke grenade. Restore original files returns your previous client."
                }
                Action::Check => {
                    installer(root, "Install", &game, "", true, log)?;
                    "Compatibility checks passed. No game files were changed."
                }
                Action::Install => {
                    installer(root, "Install", &game, "", false, log)?;
                    "Smoke installed and verified. Original files are backed up."
                }
                Action::Verify => {
                    installer(root, "Verify", &game, "", false, log)?;
                    "Installed runtime and renderer verified."
                }
                Action::Uninstall => {
                    installer(root, "Uninstall", &game, "", false, log)?;
                    "Original files restored. Backups and unrelated files are retained."
                }
                Action::QuickTest => {
                    if !valid_map(&request.map) {
                        return Err("Enter a map name such as mp_toujane.".into());
                    }
                    installer(root, "Verify", &game, "", false, log)?;
                    log(format!(
                        "Launching local DX9 smoke test on {}...",
                        request.map
                    ));
                    installer(root, "Launch", &game, &request.map, false, log)?;
                    "Test launched. Join a team and throw a smoke. Visual behavior and FPS still need an in-game check."
                }
                _ => unreachable!(),
            }
        }
    };
    log(message.into());
    Ok(JobResult {
        message: message.into(),
        outputs,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    #[ignore = "requires an assembled bundle and a local compiled map"]
    fn real_bundle_bake() {
        let root = PathBuf::from(
            std::env::var_os("COD2_SMOKE_TOOL_TEST_BUNDLE")
                .expect("Set COD2_SMOKE_TOOL_TEST_BUNDLE"),
        );
        let source =
            std::env::var("COD2_SMOKE_TOOL_TEST_MAP").expect("Set COD2_SMOKE_TOOL_TEST_MAP");
        let output =
            std::env::temp_dir().join(format!("cod2 smoke tool bake {}", std::process::id()));
        assert!(!output.exists(), "Use a fresh test output directory");
        let result = execute(
            &root,
            Request {
                action: Action::Bake,
                game_directory: String::new(),
                map: String::new(),
                inputs: vec![source],
                output: output.to_string_lossy().into_owned(),
            },
            &|line| println!("{line}"),
        );
        let result = result.expect("Real bundle bake failed");
        assert_eq!(result.outputs.len(), 1);
        fs::remove_dir_all(output).unwrap();
    }
    #[test]
    fn valve_library_paths_and_install_dir() {
        assert_eq!(
            quoted_values(r#""path" "D:\\Steam Library" "installdir" "Call of Duty 2""#),
            ["path", r"D:\Steam Library", "installdir", "Call of Duty 2"]
        );
    }
    #[test]
    fn rejects_unsafe_map_names_and_relative_paths() {
        assert!(valid_map("mp_toujane"));
        for name in [
            "mp_",
            "mp_../../test",
            "mp_x +quit",
            "MP_test",
            "mp_foo;quit",
        ] {
            assert!(!valid_map(name));
        }
        assert!(absolute_path("").is_err());
        assert!(absolute_path("relative/output").is_err());
    }
    #[test]
    fn non_utf8_log_line_does_not_hide_later_errors() {
        let lines = std::sync::Mutex::new(Vec::new());
        pump(&b"path: \xe9\r\nnext error\n"[..], &|line| {
            lines.lock().unwrap().push(line)
        });
        let lines = lines.into_inner().unwrap();
        assert_eq!(lines.len(), 2);
        assert_eq!(lines[1], "next error");
    }
    #[test]
    fn bundle_rejects_tampering_and_parent_paths() {
        let root = std::env::temp_dir().join(format!(
            "cod2-smoke-bundle-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir(&root).unwrap();
        let mut files = serde_json::Map::new();
        for &name in RUNTIME_REQUIRED.iter().chain(AUTHORING_REQUIRED.iter()) {
            let path = root.join(name);
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(path, b"fixture only; never executed").unwrap();
            files.insert(name.into(), serde_json::json!({"bytes":b"fixture only; never executed".len(),"sha256":format!("{:x}", Sha256::digest(b"fixture only; never executed"))}));
        }
        let write_manifest = |files: &serde_json::Map<String, serde_json::Value>| {
            fs::write(
                root.join("manifest.json"),
                serde_json::to_vec(&serde_json::json!({"files":files})).unwrap(),
            )
            .unwrap();
        };
        write_manifest(&files);
        assert!(validate_bundle(&root, &|_| {}).is_ok());
        assert!(authoring_available(&root));
        for &name in AUTHORING_REQUIRED {
            fs::remove_file(root.join(name)).unwrap();
        }
        // A missing/omitted authoring tool cannot block Try, Check, Install or Restore.
        assert!(validate_runtime(&root, &|_| {}).is_ok());
        assert!(!authoring_available(&root));
        assert!(validate_bundle(&root, &|_| {}).is_err());
        for &name in AUTHORING_REQUIRED {
            files.remove(name);
        }
        write_manifest(&files);
        assert!(validate_bundle(&root, &|_| {}).is_ok());
        assert!(validate_files(&root, ValidationScope::Authoring, &|_| {})
            .unwrap_err()
            .contains("tools/smoke-bake/bake.py"));
        fs::write(root.join("runtime/mss32.dll"), b"modified").unwrap();
        assert!(validate_bundle(&root, &|_| {})
            .unwrap_err()
            .contains("changed bundle file"));
        files.insert(
            "../escape".into(),
            serde_json::json!({"bytes":0,"sha256":""}),
        );
        write_manifest(&files);
        assert!(validate_bundle(&root, &|_| {})
            .unwrap_err()
            .contains("Invalid bundle path"));
        fs::remove_dir_all(root).unwrap();
    }
}
