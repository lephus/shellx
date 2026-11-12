//! The log file `shellx.log` in the logs folder (spec §4.7, Ruling 12): the `log` crate's
//! records from ShellX, GPUI and the core, level Info and above, each line redacted
//! (`log_file::format_record`), identical consecutive records folded into a count line, the
//! file rotated before a write would take it past 1 MiB, three files kept. Only the GUI
//! process installs it. Nothing here unwraps or panics: a log that cannot be written is
//! skipped quietly.

use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, MutexGuard, TryLockError};
use std::time::{SystemTime, UNIX_EPOCH};

use shellx_model::log_file::{self, LOG_FILE_MAX_BYTES, LOG_FILES_KEPT, LineDedup};

const FILE_NAME: &str = "shellx.log";

/// The open log: its folder, the current file (None when it cannot be opened), the bytes
/// in it, and the repeat folding.
pub(crate) struct LogState {
    dir: PathBuf,
    file: Option<File>,
    size: u64,
    dedup: LineDedup,
}

impl LogState {
    /// Creates the folder if needed and opens `shellx.log` for appending. Never fails: a
    /// file that cannot be opened leaves `file` empty and every write is skipped.
    pub(crate) fn open(dir: &Path) -> LogState {
        let _ = std::fs::create_dir_all(dir);
        let mut state = LogState {
            dir: dir.to_path_buf(),
            file: None,
            size: 0,
            dedup: LineDedup::default(),
        };
        state.reopen();
        state
    }

    /// `shellx.log` for 0, `shellx.log.<n>` otherwise.
    fn path(&self, n: usize) -> PathBuf {
        if n == 0 {
            self.dir.join(FILE_NAME)
        } else {
            self.dir.join(format!("{FILE_NAME}.{n}"))
        }
    }

    fn reopen(&mut self) {
        self.file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(self.path(0))
            .ok();
        self.size = self
            .file
            .as_ref()
            .and_then(|f| f.metadata().ok())
            .map_or(0, |m| m.len());
    }

    /// Close, remove `.2`, rename `.1` to `.2` and the current file to `.1`, reopen. Every
    /// error is ignored: rotation is best effort and never stops a write (another ShellX
    /// may hold the file).
    fn rotate(&mut self) {
        self.file = None;
        let _ = std::fs::remove_file(self.path(LOG_FILES_KEPT - 1));
        for n in (1..LOG_FILES_KEPT).rev() {
            let _ = std::fs::rename(self.path(n - 1), self.path(n));
        }
        self.reopen();
    }

    /// One `write_all` of `text`, rotating first when it would pass the size limit.
    fn write_text(&mut self, text: &str) {
        if text.is_empty() {
            return;
        }
        let len = text.len() as u64;
        if self.size > 0 && self.size.saturating_add(len) > LOG_FILE_MAX_BYTES {
            self.rotate();
        }
        if let Some(file) = self.file.as_mut()
            && file.write_all(text.as_bytes()).is_ok()
        {
            self.size = self.size.saturating_add(len);
        }
    }
}

/// The logger's write path: format and redact the record, fold repeats, write.
pub(crate) fn write_record(
    state: &mut LogState,
    timestamp: &str,
    level: &str,
    target: &str,
    message: &str,
) {
    let key = format!("{level}\u{1f}{target}\u{1f}{message}");
    let line = log_file::format_record(timestamp, level, target, message);
    let text: String = state.dedup.push(&key, line, timestamp).concat();
    state.write_text(&text);
}

struct Logger {
    state: Mutex<Option<LogState>>,
}

static LOGGER: Logger = Logger {
    state: Mutex::new(None),
};

/// The state even when a panic poisoned the lock (nothing here leaves it half-written).
fn lock(state: &Mutex<Option<LogState>>) -> MutexGuard<'_, Option<LogState>> {
    match state.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}

fn now_timestamp() -> String {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| u64::try_from(d.as_millis()).unwrap_or(u64::MAX));
    log_file::utc_timestamp(millis)
}

impl log::Log for Logger {
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        metadata.level() <= log::Level::Info
    }

    fn log(&self, record: &log::Record) {
        if !self.enabled(record.metadata()) {
            return;
        }
        // Formatted before the lock: a Display impl that logs or panics cannot deadlock it.
        let message = record.args().to_string();
        let timestamp = now_timestamp();
        if let Some(state) = lock(&self.state).as_mut() {
            write_record(
                state,
                &timestamp,
                record.level().as_str(),
                record.target(),
                &message,
            );
        }
    }

    fn flush(&self) {
        if let Some(file) = lock(&self.state).as_mut().and_then(|s| s.file.as_mut()) {
            let _ = file.flush();
        }
    }
}

/// Opens `<dir>\shellx.log` and makes it the `log` crate's logger at level Info. False (no
/// log) when the file cannot be opened or a logger is already set.
pub fn install(dir: &Path) -> bool {
    let state = LogState::open(dir);
    if state.file.is_none() {
        return false;
    }
    *lock(&LOGGER.state) = Some(state);
    if log::set_logger(&LOGGER).is_err() {
        return false;
    }
    log::set_max_level(log::LevelFilter::Info);
    true
}

/// One line from the panic hook: written only when the lock is free (the panic may have
/// happened while this thread held it), so the hook never blocks or deadlocks here.
#[allow(dead_code)] // the panic hook (B4) is its caller
pub fn try_append(line: &str) {
    let timestamp = now_timestamp();
    let mut guard = match LOGGER.state.try_lock() {
        Ok(guard) => guard,
        Err(TryLockError::Poisoned(poisoned)) => poisoned.into_inner(),
        Err(TryLockError::WouldBlock) => return,
    };
    if let Some(state) = guard.as_mut() {
        write_record(state, &timestamp, "ERROR", "shellx", line);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const T43: &str = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE"; // 43 chars, base64url

    fn read(dir: &std::path::Path, name: &str) -> String {
        std::fs::read_to_string(dir.join(name)).unwrap()
    }

    #[test]
    fn every_record_is_redacted_before_it_is_written() {
        let tmp = tempfile::tempdir().unwrap();
        let mut state = LogState::open(tmp.path());
        write_record(
            &mut state,
            "T",
            "WARN",
            "shellx_desktop::account",
            &format!("sign-in failed for a@b.co with {T43}"),
        );
        write_record(&mut state, "T", "INFO", "shellx", "the code 123456 was sent");
        write_record(
            &mut state,
            "T",
            "ERROR",
            "gpui",
            &format!("first line\nBearer {T43}\nmail a@b.co, code 654321"),
        );
        drop(state);
        let text = read(tmp.path(), "shellx.log");
        for secret in ["a@b.co", T43, "123456", "654321"] {
            assert!(!text.contains(secret), "{secret} in {text}");
        }
        assert!(text.contains("T WARN shellx_desktop::account: sign-in failed for <email>"));
        assert_eq!(text.lines().count(), 5, "{text}");
    }

    #[test]
    fn the_logger_rotates_at_one_mebibyte_and_keeps_three_files() {
        let tmp = tempfile::tempdir().unwrap();
        let mut state = LogState::open(tmp.path());
        let filler = "filler words ".repeat(75); // about 1000 bytes per record
        let mut written = 0u64;
        let mut i = 0u32;
        while written < 3 * 1_048_576 + 524_288 {
            let message = format!("record {i} {filler}");
            written += message.len() as u64;
            write_record(&mut state, "2026-11-12T08:15:30.123Z", "INFO", "t", &message);
            i += 1;
        }
        drop(state);
        for name in ["shellx.log", "shellx.log.1", "shellx.log.2"] {
            let len = std::fs::metadata(tmp.path().join(name)).unwrap().len();
            assert!(len > 0 && len <= LOG_FILE_MAX_BYTES, "{name}: {len}");
        }
        assert!(!tmp.path().join("shellx.log.3").exists());
        // the newest records are in shellx.log, the one before in .1
        let last = format!("record {} ", i - 1);
        assert!(read(tmp.path(), "shellx.log").contains(&last));
        assert!(!read(tmp.path(), "shellx.log.1").contains(&last));
    }

    #[test]
    fn the_log_works_in_a_folder_with_vietnamese_and_spaces() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("Phú Lê").join("logs");
        let mut state = LogState::open(&dir);
        write_record(&mut state, "T", "INFO", "shellx", "ShellX 1.7.0 starting");
        drop(state);
        assert_eq!(
            read(&dir, "shellx.log"),
            "T INFO shellx: ShellX 1.7.0 starting\n"
        );
    }

    #[test]
    fn an_unwritable_log_never_panics() {
        let tmp = tempfile::tempdir().unwrap();
        std::fs::create_dir(tmp.path().join("shellx.log")).unwrap();
        let mut state = LogState::open(tmp.path());
        for i in 0..3 {
            write_record(&mut state, "T", "INFO", "shellx", &format!("line {i}"));
        }
        assert!(tmp.path().join("shellx.log").is_dir());
        // a folder that cannot be created (its parent is a file) is no log either
        let file = tmp.path().join("plain-file");
        std::fs::write(&file, "x").unwrap();
        let mut state = LogState::open(&file.join("logs"));
        write_record(&mut state, "T", "INFO", "shellx", "line");
        assert!(!install(&file.join("logs")));
    }
}
