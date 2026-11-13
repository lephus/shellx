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
            assert!(
                !line.contains(&*dir.path().to_string_lossy()),
                "{line}"
            );
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
        let e = store
            .write("app.language", Some(json!("vi")))
            .unwrap_err();
        assert_eq!(e.kind(), io::ErrorKind::NotFound);
        assert_eq!(e.to_string(), "LOCALAPPDATA is not set");
        assert!(store.write_many(vec![("app.language", None)]).is_err());
    }
}
