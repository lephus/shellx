//! The one `SettingsService` every window shares (an entity kept in a `Global`): the current
//! `Settings`, read from `settings.json` once at start. A change applies at once and notifies
//! the observers; the file gets it 300 ms after the last change to that key, on the
//! background executor, key by key (`settings_store`). `startup::orderly_quit` writes what
//! still waits. A failed write is one log line naming the error's kind (no path, no value);
//! the change then lives in memory until ShellX quits. Nothing here panics or blocks the UI
//! on the file.

use std::collections::{BTreeMap, HashMap};
use std::io;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::time::Duration;

use gpui::{App, AppContext as _, Context, Entity, Global, Task};
use serde_json::Value;
use shellx_model::settings::{Key, Settings};

use crate::settings_store::SettingsStore;
use crate::startup;

/// How long a key waits after its last change before it is written: a slider being dragged
/// writes once, when it stops.
const WRITE_DELAY: Duration = Duration::from_millis(300);

pub struct SettingsService {
    settings: Settings,
    writes: Arc<PendingWrites>,
    /// The timer of each key that waits for its write; a new change to the key drops
    /// (cancels) it and starts another.
    timers: HashMap<Key, Task<()>>,
}

struct SharedSettings(Entity<SettingsService>);

impl Global for SharedSettings {}

impl SettingsService {
    /// Loads `settings.json`, keeps the service in a `Global` and has `orderly_quit` write
    /// what still waits. Called before the first window opens.
    pub fn init(cx: &mut App) {
        let store = SettingsStore::at_native_dir();
        let settings = store.load();
        let writes = Arc::new(PendingWrites::new(store));
        startup::flush_on_quit({
            let writes = writes.clone();
            move || writes.flush()
        });
        let service = cx.new(|_| SettingsService {
            settings,
            writes,
            timers: HashMap::new(),
        });
        cx.set_global(SharedSettings(service));
    }

    #[allow(dead_code)] // first called by the Settings view (A5)
    pub fn entity(cx: &App) -> Entity<SettingsService> {
        cx.global::<SharedSettings>().0.clone()
    }

    pub fn settings(&self) -> &Settings {
        &self.settings
    }

    /// Applies `value` (clamped; one of the wrong type changes nothing), notifies the
    /// observers, and writes the key 300 ms after its last change. A value equal to the
    /// default removes the key from the file.
    #[allow(dead_code)] // first called by the Settings view (A5)
    pub fn set(&mut self, key: Key, value: Value, cx: &mut Context<Self>) {
        if self.settings.set_from_value(key, &value) {
            self.changed(key, cx);
        }
    }

    /// The key back to its default, which removes it from the file; written like `set`.
    #[allow(dead_code)] // first called by the Settings view (A5)
    pub fn reset(&mut self, key: Key, cx: &mut Context<Self>) {
        self.settings.reset(key);
        self.changed(key, cx);
    }

    /// Every key back to its default, removed from the file in one write, at once. Keys this
    /// version does not know, and `shell`, stay.
    #[allow(dead_code)] // first called by Reset All Settings (F2)
    pub fn reset_all(&mut self, cx: &mut Context<Self>) {
        self.settings = Settings::default();
        self.timers.clear();
        for key in Key::ALL {
            self.writes.wait(key.path(), None);
        }
        let writes = self.writes.clone();
        cx.background_spawn(async move { writes.flush() }).detach();
        cx.notify();
    }

    fn changed(&mut self, key: Key, cx: &mut Context<Self>) {
        self.writes.wait(key.path(), self.settings.to_value(key));
        let writes = self.writes.clone();
        let delay = cx.background_executor().timer(WRITE_DELAY);
        let timer = cx.background_spawn(async move {
            delay.await;
            writes.write(key.path());
        });
        self.timers.insert(key, timer);
        cx.notify();
    }
}

/// The current settings, for any view: `current(cx).font_size`.
#[allow(dead_code)] // first read by the Settings view (A5) and the terminal (R1)
pub fn current(cx: &App) -> &Settings {
    cx.global::<SharedSettings>().0.read(cx).settings()
}

/// The values that wait for their write, shared by the service's timers and `orderly_quit`.
struct PendingWrites {
    store: SettingsStore,
    /// Key path to value (`None` removes the key). Held only for a moment, never during a
    /// write, so a change on the UI thread does not wait for the disk.
    waiting: Mutex<BTreeMap<&'static str, Option<Value>>>,
    /// Held from taking a value to writing it, so a later value is always written later.
    writing: Mutex<()>,
}

impl PendingWrites {
    fn new(store: SettingsStore) -> Self {
        PendingWrites {
            store,
            waiting: Mutex::new(BTreeMap::new()),
            writing: Mutex::new(()),
        }
    }

    fn wait(&self, path: &'static str, value: Option<Value>) {
        lock(&self.waiting).insert(path, value);
    }

    /// Writes the value waiting at `path`, if one still waits.
    fn write(&self, path: &'static str) {
        let _writing = lock(&self.writing);
        let Some(value) = lock(&self.waiting).remove(path) else {
            return;
        };
        log_failure(self.store.write(path, value));
    }

    /// Writes every waiting value in one write (on quit, and for Reset All).
    fn flush(&self) {
        let _writing = lock(&self.writing);
        let waiting = std::mem::take(&mut *lock(&self.waiting));
        if waiting.is_empty() {
            return;
        }
        log_failure(self.store.write_many(waiting.into_iter().collect()));
    }
}

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

/// One line with the error's kind only: its text could name the folder (the Windows user).
fn log_failure(result: io::Result<()>) {
    if let Err(error) = result {
        log::warn!(
            "shellx: settings.json could not be written ({:?}); the change lasts until ShellX quits",
            error.kind()
        );
    }
}

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
