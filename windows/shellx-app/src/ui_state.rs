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
