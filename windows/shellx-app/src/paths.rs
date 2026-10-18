//! Native state directories. Everything lives under one root that the Flutter
//! ShellX never touches (its uninstaller deletes `%APPDATA%\pro.shellx\ShellX`
//! and `%LOCALAPPDATA%\ShellX\{bin,term,restore,cli,mux}`).
#![allow(dead_code)] // used by the sign-in wiring (Task 10b)

use std::io;
use std::path::PathBuf;

/// `%LOCALAPPDATA%\ShellX\native` on Windows, `$HOME/.local/share/shellx-native`
/// elsewhere (tests and development). Not created.
pub fn native_dir() -> PathBuf {
    if cfg!(windows) {
        let base = std::env::var_os("LOCALAPPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(r"C:\Users\Default\AppData\Local"));
        base.join("ShellX").join("native")
    } else {
        let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
        home.join(".local").join("share").join("shellx-native")
    }
}

fn ensure(path: PathBuf) -> io::Result<PathBuf> {
    std::fs::create_dir_all(&path)?;
    Ok(path)
}

/// shellx-core `state_dir` (device key, session). Created on demand.
pub fn core_dir() -> io::Result<PathBuf> {
    ensure(native_dir().join("core"))
}

/// cmux-remote client identity. Created on demand.
pub fn remote_dir() -> io::Result<PathBuf> {
    ensure(native_dir().join("remote"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dirs_are_under_native_and_distinct() {
        let n = native_dir();
        assert!(n.is_absolute());
        let s = n.to_string_lossy().to_lowercase();
        for forbidden in ["pro.shellx", "roaming"] {
            assert!(!s.contains(forbidden), "{s}");
        }
        for sub in ["bin", "term", "restore", "cli", "mux"] {
            assert_ne!(n.file_name().unwrap().to_string_lossy(), sub);
        }
        // does not create anything: only checks the layout
        assert_eq!(n.join("core").parent(), Some(n.as_path()));
        assert_ne!(n.join("core"), n.join("remote"));
    }
}
