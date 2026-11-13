#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn json_at(path: &std::path::Path) -> Value {
        serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
    }

    #[test]
    fn a_waiting_key_writes_its_latest_value_once() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("settings.json");
        let writes = PendingWrites::new(SettingsStore::new(path.clone()));
        writes.wait("terminalConfig.font-size", Some(json!(14)));
        writes.wait("terminalConfig.font-size", Some(json!(15)));
        writes.wait("app.language", Some(json!("vi")));
        writes.write("terminalConfig.font-size");
        // only that key: the other one still waits for its own timer
        assert_eq!(json_at(&path), json!({"terminalConfig": {"font-size": 15}}));
        // written once: a later timer for the key finds nothing to write
        std::fs::write(&path, "{}").unwrap();
        writes.write("terminalConfig.font-size");
        assert_eq!(json_at(&path), json!({}));
        writes.write("app.language");
        assert_eq!(json_at(&path), json!({"app": {"language": "vi"}}));
    }

    #[test]
    fn flush_writes_every_waiting_key_on_quit() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("settings.json");
        std::fs::write(&path, r#"{"future":1,"app":{"appearance":"light"}}"#).unwrap();
        let writes = PendingWrites::new(SettingsStore::new(path.clone()));
        writes.wait("terminalConfig.font-size", Some(json!(15)));
        writes.wait("app.appearance", None);
        writes.flush();
        assert_eq!(
            json_at(&path),
            json!({"future": 1, "terminalConfig": {"font-size": 15}})
        );
        // the timers that fire after the flush write nothing
        std::fs::write(&path, "{}").unwrap();
        writes.write("terminalConfig.font-size");
        writes.flush();
        assert_eq!(json_at(&path), json!({}));
    }

    #[test]
    fn a_failed_write_is_dropped_without_a_panic() {
        // the folder cannot be made (a file has its name): the value lives in memory only
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("native");
        std::fs::write(&file, "").unwrap();
        let writes = PendingWrites::new(SettingsStore::new(file.join("settings.json")));
        writes.wait("app.language", Some(json!("vi")));
        writes.write("app.language");
        writes.wait("app.language", Some(json!("en")));
        writes.flush();
        assert!(writes.waiting.lock().unwrap().is_empty());
    }
}
