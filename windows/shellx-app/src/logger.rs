//! The log file `shellx.log` in the logs folder (spec §4.7, Ruling 12).

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
