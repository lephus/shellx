//! `ui-state.json` in the app's native folder: where the Settings window was and which section
//! it showed, so it opens there again (spec §5.3). Window state only, never a setting: it is
//! not in `settings.json`, and a missing or unreadable file is simply the first start
//! (Settings centred, on Account).

use std::io;
use std::path::{Path, PathBuf};

use serde_json::{Map, Value, json};

const FILE_NAME: &str = "ui-state.json";
const FRAME: &str = "settingsFrame";
const SECTION: &str = "settingsSection";

#[derive(Clone, Debug, Default, PartialEq)]
pub struct UiState {
    /// The Settings window's frame when it last closed: x, y, width, height in logical
    /// pixels (the restore frame when it was maximized).
    pub settings_frame: Option<(f32, f32, f32, f32)>,
    /// The id of the section Settings showed last (`Section::id`).
    pub settings_section: Option<String>,
}

fn path() -> io::Result<PathBuf> {
    crate::paths::native_dir().map(|dir| dir.join(FILE_NAME))
}

/// The stored state; the default when there is no file or it cannot be read.
pub fn load() -> UiState {
    path().map(|path| load_from(&path)).unwrap_or_default()
}

/// Writes `state` over the file. A failure is one log line naming the error's kind (no path):
/// the window then just opens at its default place next time.
pub fn save(state: &UiState) {
    let saved = path().and_then(|path| save_to(&path, state));
    if let Err(error) = saved {
        log::warn!("shellx: ui-state.json was not written ({:?})", error.kind());
    }
}

fn load_from(path: &Path) -> UiState {
    let Some(root) = std::fs::read_to_string(path)
        .ok()
        .and_then(|text| serde_json::from_str::<Value>(&text).ok())
    else {
        return UiState::default();
    };
    UiState {
        settings_frame: root.get(FRAME).and_then(frame),
        settings_section: root
            .get(SECTION)
            .and_then(Value::as_str)
            .map(str::to_string),
    }
}

/// `[x, y, width, height]` with a positive size.
fn frame(value: &Value) -> Option<(f32, f32, f32, f32)> {
    let numbers: Vec<f32> = value
        .as_array()?
        .iter()
        .map(|n| n.as_f64().map(|n| n as f32).filter(|n| n.is_finite()))
        .collect::<Option<_>>()?;
    match numbers[..] {
        [x, y, width, height] if width > 0.0 && height > 0.0 => Some((x, y, width, height)),
        _ => None,
    }
}

fn save_to(path: &Path, state: &UiState) -> io::Result<()> {
    let mut root = Map::new();
    if let Some((x, y, width, height)) = state.settings_frame {
        root.insert(FRAME.into(), json!([x, y, width, height]));
    }
    if let Some(section) = &state.settings_section {
        root.insert(SECTION.into(), json!(section));
    }
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    // A whole new file renamed over the old one: a crash never leaves half of it.
    let tmp = path.with_extension(format!("json.tmp{}", std::process::id()));
    std::fs::write(&tmp, Value::Object(root).to_string())?;
    std::fs::rename(&tmp, path).inspect_err(|_| {
        let _ = std::fs::remove_file(&tmp);
    })
}

#[cfg(test)]
mod tests {
    use super::{UiState, load_from, save_to};

    #[test]
    fn an_unreadable_ui_state_is_the_default() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("ui-state.json");
        assert_eq!(load_from(&path), UiState::default(), "no file");
        for text in [
            "",
            "not json",
            "[1, 2]",
            "\"settings\"",
            "{\"settingsFrame\": \"wide\", \"settingsSection\": 7}",
            "{\"settingsFrame\": [1, 2, 3]}",
            "{\"settingsFrame\": [0, 0, -980, 680]}",
        ] {
            std::fs::write(&path, text).unwrap();
            assert_eq!(load_from(&path), UiState::default(), "{text}");
        }
        // A folder where the file should be.
        let folder = dir.path().join("folder");
        std::fs::create_dir(&folder).unwrap();
        assert_eq!(load_from(&folder), UiState::default());
    }

    #[test]
    fn the_frame_and_section_round_trip() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("sub").join("ui-state.json");
        let state = UiState {
            settings_frame: Some((120.0, -40.5, 980.0, 680.0)),
            settings_section: Some("terminal".to_string()),
        };
        save_to(&path, &state).unwrap();
        assert_eq!(load_from(&path), state);
        // One part on its own.
        let section_only = UiState {
            settings_frame: None,
            settings_section: Some("about".to_string()),
        };
        save_to(&path, &section_only).unwrap();
        assert_eq!(load_from(&path), section_only);
        save_to(&path, &UiState::default()).unwrap();
        assert_eq!(load_from(&path), UiState::default());
    }
}
