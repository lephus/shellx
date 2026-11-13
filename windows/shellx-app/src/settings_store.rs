//! `settings.json` in the app's native folder: the settings of the Settings window and the
//! shell choice (`{"shell": …}`, its 1.7.1 shape), sparse (`shellx_model::settings`).
//!
//! Several ShellX processes share the file and each keeps what it read when it started, so a
//! write never saves a whole `Settings`: it reads the file again, changes only the keys it was
//! given and keeps every other key, known or not. The new text goes to a temporary file that
//! is renamed over `settings.json`; in the process, one lock orders the writes.
//!
//! A file that is not a JSON object, or is over `SETTINGS_MAX_BYTES`, reads as no settings.
//! The first write moves it to `settings.json.bad-<unix seconds>` instead of writing over it,
//! with one log line that names only the reason (as `links_store.rs` does). A leading UTF-8
//! BOM is accepted; an empty file holds no settings.

use std::io::{self, Read as _};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, PoisonError};

use serde_json::{Map, Value};
use shellx_model::settings::{Settings, get, put};

/// A larger `settings.json` is not read (the first `shells()` call reads it on the UI thread,
/// review M7).
pub const SETTINGS_MAX_BYTES: u64 = 64 * 1024;

/// Held around every read-modify-write of a settings file in this process.
static WRITE_LOCK: Mutex<()> = Mutex::new(());

/// Makes each temporary file name unique in the process.
static TMP_SEQ: AtomicU64 = AtomicU64::new(0);

pub struct SettingsStore {
    /// `None`: there is no folder to keep it in (`LOCALAPPDATA` unset). Nothing is read and
    /// every write fails.
    path: Option<PathBuf>,
}

/// What a read found.
enum FileState {
    /// No file, or an empty one.
    Missing,
    Object(Map<String, Value>),
    Unreadable(Unreadable),
}

/// Why a file that exists holds no usable settings: all the log says about it.
#[derive(Clone, Copy)]
enum Unreadable {
    NotJson,
    NotAnObject,
    TooLarge,
}

impl SettingsStore {
    pub fn new(path: PathBuf) -> Self {
        SettingsStore { path: Some(path) }
    }

    /// `paths::native_dir()/settings.json`; without that folder, a store that holds nothing.
    pub fn at_native_dir() -> Self {
        match crate::paths::native_dir() {
            Ok(dir) => SettingsStore::new(dir.join("settings.json")),
            Err(_) => SettingsStore { path: None },
        }
    }

    /// Every key of the file read on its own; the defaults when there is no usable file.
    pub fn load(&self) -> Settings {
        Settings::from_json(&self.read_object())
    }

    /// The value at the dotted `path`, as the file holds it.
    pub fn read_raw(&self, path: &str) -> Option<Value> {
        get(&self.read_object(), path).cloned()
    }

    /// Reads the file again, changes only `path` (`None` removes it), writes a temporary file
    /// and renames it.
    pub fn write(&self, path: &str, value: Option<Value>) -> io::Result<()> {
        self.write_many(vec![(path, value)])
    }

    /// `write` for several keys, in one read and one rename (Reset All, a flush on quit).
    pub fn write_many(&self, changes: Vec<(&str, Option<Value>)>) -> io::Result<()> {
        let path = self
            .path
            .as_ref()
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "LOCALAPPDATA is not set"))?;
        let _guard = WRITE_LOCK.lock().unwrap_or_else(PoisonError::into_inner);
        let before = match read_file(path)? {
            FileState::Missing => Map::new(),
            FileState::Object(object) => object,
            FileState::Unreadable(why) => {
                let bad = crate::links_store::quarantine(path)?;
                log::warn!("{}", set_aside_line(why, &bad));
                Map::new()
            }
        };
        let mut object = before.clone();
        for (key, value) in changes {
            put(&mut object, key, value);
        }
        if object == before {
            return Ok(());
        }
        write_replacing(path, &Value::Object(object))
    }

    fn read_object(&self) -> Map<String, Value> {
        match self.path.as_deref().map(read_file) {
            Some(Ok(FileState::Object(object))) => object,
            _ => Map::new(),
        }
    }
}

/// Reads at most `SETTINGS_MAX_BYTES` + 1 bytes. An error other than a missing file is
/// returned: nothing is known about the file then, so it is neither used nor written over.
fn read_file(path: &Path) -> io::Result<FileState> {
    let file = match std::fs::File::open(path) {
        Ok(file) => file,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(FileState::Missing),
        Err(e) => return Err(e),
    };
    let mut bytes = Vec::new();
    file.take(SETTINGS_MAX_BYTES + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > SETTINGS_MAX_BYTES {
        return Ok(FileState::Unreadable(Unreadable::TooLarge));
    }
    let text = bytes.strip_prefix(b"\xEF\xBB\xBF").unwrap_or(&bytes);
    if text.iter().all(u8::is_ascii_whitespace) {
        return Ok(FileState::Missing);
    }
    Ok(match serde_json::from_slice(text) {
        Ok(Value::Object(object)) => FileState::Object(object),
        Ok(_) => FileState::Unreadable(Unreadable::NotAnObject),
        Err(_) => FileState::Unreadable(Unreadable::NotJson),
    })
}

/// The log line for a file moved aside: the reason and the new file's name. Nothing the file
/// held, and not the folder (it holds the Windows user name).
fn set_aside_line(why: Unreadable, bad: &Path) -> String {
    let reason = match why {
        Unreadable::NotJson => "is not JSON",
        Unreadable::NotAnObject => "is JSON but not an object",
        Unreadable::TooLarge => "is larger than 64 KiB",
    };
    let name = bad
        .file_name()
        .map_or_else(String::new, |n| n.to_string_lossy().into_owned());
    format!("shellx: settings.json {reason}; moved it to {name} and started from the defaults")
}

/// Writes `object` to a temporary file next to `path`, then renames it over `path`. Creates
/// the folder when it is missing.
fn write_replacing(path: &Path, object: &Value) -> io::Result<()> {
    let text = serde_json::to_string_pretty(object).map_err(io::Error::other)?;
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let seq = TMP_SEQ.fetch_add(1, Ordering::Relaxed);
    let tmp = path.with_extension(format!("json.tmp{}-{seq}", std::process::id()));
    std::fs::write(&tmp, text)
        .and_then(|()| std::fs::rename(&tmp, path))
        .inspect_err(|_| {
            let _ = std::fs::remove_file(&tmp);
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use shellx_model::settings::LanguageChoice;
    use std::path::Path;

    fn json_at(path: &Path) -> Value {
        serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
    }

    /// The folder's file names, sorted.
    fn names(dir: &Path) -> Vec<String> {
        let mut names: Vec<String> = std::fs::read_dir(dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        names.sort();
        names
    }

    /// The one `settings.json.bad-<unix seconds>` in `dir`.
    fn the_bad_file(dir: &Path) -> String {
        let bad: Vec<String> = names(dir)
            .into_iter()
            .filter(|n| n.starts_with("settings.json.bad-"))
            .collect();
        assert_eq!(bad.len(), 1, "{:?}", names(dir));
        let seconds = &bad[0]["settings.json.bad-".len()..];
        assert!(seconds.parse::<u64>().is_ok(), "{}", bad[0]);
        bad[0].clone()
    }

    #[test]
    fn unknown_keys_and_shell_survive_a_write() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("settings.json");
        std::fs::write(
            &path,
            r#"{"shell":{"kind":"known","shell":"pwsh"},"future":{"x":1}}"#,
        )
        .unwrap();
        let store = SettingsStore::new(path.clone());
        store.write("app.language", Some(json!("vi"))).unwrap();
        assert_eq!(
            json_at(&path),
            json!({
                "shell": {"kind": "known", "shell": "pwsh"},
                "future": {"x": 1},
                "app": {"language": "vi"}
            })
        );
        assert_eq!(store.load().language, LanguageChoice::Vi);
        assert_eq!(
            store.read_raw("shell"),
            Some(json!({"kind": "known", "shell": "pwsh"}))
        );
        assert_eq!(store.read_raw("future.x"), Some(json!(1)));
        // removing the key prunes the "app" it leaves empty and keeps the rest
        store.write("app.language", None).unwrap();
        assert_eq!(
            json_at(&path),
            json!({"shell": {"kind": "known", "shell": "pwsh"}, "future": {"x": 1}})
        );
        // several keys at once (Reset All): the unknown keys still stay
        store
            .write_many(vec![
                ("terminalConfig.font-size", Some(json!(15))),
                ("app.appearance", None),
            ])
            .unwrap();
        assert_eq!(json_at(&path)["terminalConfig"], json!({"font-size": 15}));
        assert_eq!(json_at(&path)["future"], json!({"x": 1}));
        // the temporary file was renamed over settings.json: nothing else is left
        assert_eq!(names(dir.path()), ["settings.json"]);
    }

    #[test]
    fn a_stale_process_writes_only_the_key_it_changed() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("settings.json");
        let store_a = SettingsStore::new(path.clone());
        let store_b = SettingsStore::new(path.clone());
        // B read the file before A changed it
        let stale = store_b.load();
        assert_eq!(stale.font_size, 13.0);
        store_a
            .write("terminalConfig.font-size", Some(json!(15)))
            .unwrap();
        store_b
            .write("terminalConfig.theme.dark", Some(json!("Dracula")))
            .unwrap();
        assert_eq!(
            json_at(&path),
            json!({"terminalConfig": {"font-size": 15, "theme": {"dark": "Dracula"}}})
        );
        let now = SettingsStore::new(path).load();
        assert_eq!(now.font_size, 15.0);
        assert_eq!(now.theme_dark, "Dracula");
    }

    #[test]
    fn an_unreadable_file_is_set_aside_not_overwritten() {
        let mut over_the_bound = br#"{"app":{"language":"vi"}}"#.to_vec();
        over_the_bound.resize(SETTINGS_MAX_BYTES as usize + 1, b' ');
        let bad: [&[u8]; 5] = [
            b"not json",
            b"[1, 2]",
            br#""a string""#,
            b"\xff\xfe{\"app\":1}",
            &over_the_bound,
        ];
        for old in bad {
            let dir = tempfile::tempdir().unwrap();
            let path = dir.path().join("settings.json");
            std::fs::write(&path, old).unwrap();
            let store = SettingsStore::new(path.clone());
            assert_eq!(store.load(), Settings::default());
            assert_eq!(store.read_raw("app.language"), None);
            // reading never moves it
            assert_eq!(names(dir.path()), ["settings.json"]);

            store.write("app.language", Some(json!("en"))).unwrap();
            let bad_name = the_bad_file(dir.path());
            assert_eq!(std::fs::read(dir.path().join(&bad_name)).unwrap(), old);
            assert_eq!(json_at(&path), json!({"app": {"language": "en"}}));
            assert_eq!(names(dir.path()).len(), 2);
        }
        // a second bad file in the same second gets a name of its own
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("settings.json");
        let store = SettingsStore::new(path.clone());
        std::fs::write(&path, "{").unwrap();
        store.write("app.language", Some(json!("en"))).unwrap();
        std::fs::write(&path, "}").unwrap();
        store.write("app.language", Some(json!("vi"))).unwrap();
        assert_eq!(names(dir.path()).len(), 3, "{:?}", names(dir.path()));
        assert_eq!(store.load().language, LanguageChoice::Vi);
    }

    #[test]
    fn a_bom_and_an_empty_file_load_as_defaults_or_values() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("settings.json");
        let store = SettingsStore::new(path.clone());
        std::fs::write(
            &path,
            "\u{feff}{\"app\":{\"language\":\"vi\"},\"shell\":{\"kind\":\"auto\"}}",
        )
        .unwrap();
        assert_eq!(store.load().language, LanguageChoice::Vi);
        assert_eq!(store.read_raw("shell"), Some(json!({"kind": "auto"})));
        // a write keeps the values and leaves no BOM and no bad file
        store.write("app.appearance", Some(json!("light"))).unwrap();
        assert!(std::fs::read_to_string(&path).unwrap().starts_with('{'));
        assert_eq!(
            json_at(&path),
            json!({"app": {"language": "vi", "appearance": "light"}, "shell": {"kind": "auto"}})
        );
        assert_eq!(names(dir.path()), ["settings.json"]);

        for empty in ["", "  \r\n", "\u{feff}"] {
            std::fs::write(&path, empty).unwrap();
            assert_eq!(store.load(), Settings::default(), "{empty:?}");
            assert_eq!(store.read_raw("shell"), None, "{empty:?}");
            // an empty file holds nothing to keep: it is written over, not set aside
            store.write("app.appearance", Some(json!("light"))).unwrap();
            assert_eq!(json_at(&path), json!({"app": {"appearance": "light"}}));
            assert_eq!(names(dir.path()), ["settings.json"], "{empty:?}");
        }
    }

    #[test]
    fn the_log_line_for_a_bad_file_holds_none_of_its_text() {
        let secrets = ["phu@example.com", "ghp_s3cr3tT0ken", "Phú Lê"];
        let mut too_large =
            r#"{"account":"phu@example.com","token":"ghp_s3cr3tT0ken","name":"Phú Lê"}"#
                .to_string();
        too_large.push_str(&" ".repeat(SETTINGS_MAX_BYTES as usize));
        let bad = [
            r#"{"account":"phu@example.com","token":"ghp_s3cr3tT0ken","name":"Phú Lê""#.to_string(),
            r#"["phu@example.com","ghp_s3cr3tT0ken","Phú Lê"]"#.to_string(),
            too_large,
        ];
        let mut lines = Vec::new();
        for text in bad {
            let dir = tempfile::tempdir().unwrap();
            let path = dir.path().join("settings.json");
            std::fs::write(&path, &text).unwrap();
            let FileState::Unreadable(why) = read_file(&path).unwrap() else {
                panic!("{text:.40} should be unreadable");
            };
            let line = set_aside_line(why, &dir.path().join("settings.json.bad-1700000000"));
            for secret in secrets {
                assert!(!line.contains(secret), "{line}");
            }
            assert!(!line.contains('@') && !line.contains("Phú"), "{line}");
            // the folder (it holds the Windows user name) is not in it either
            assert!(!line.contains(&*dir.path().to_string_lossy()), "{line}");
            assert!(line.contains("settings.json.bad-1700000000"), "{line}");
            lines.push(line);
        }
        // each reason has its own words
        lines.dedup();
        assert_eq!(lines.len(), 3, "{lines:?}");
    }

    #[test]
    fn a_store_without_a_folder_loads_defaults_and_fails_writes_quietly() {
        let store = SettingsStore { path: None };
        assert_eq!(store.load(), Settings::default());
        assert_eq!(store.read_raw("shell"), None);
        let e = store.write("app.language", Some(json!("vi"))).unwrap_err();
        assert_eq!(e.kind(), io::ErrorKind::NotFound);
        assert_eq!(e.to_string(), "LOCALAPPDATA is not set");
        assert!(store.write_many(vec![("app.language", None)]).is_err());
    }
}
