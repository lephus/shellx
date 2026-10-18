//! Native state directories. Everything lives under one root that the Flutter
//! ShellX never touches (its uninstaller deletes `%APPDATA%\pro.shellx\ShellX`
//! and `%LOCALAPPDATA%\ShellX\{bin,term,restore,cli,mux}`).
// remote_dir is used by the remote panes (Task 13).
#![allow(dead_code)]

use std::ffi::OsString;
use std::io;
use std::path::PathBuf;

/// `%LOCALAPPDATA%\ShellX\native` on Windows, `$HOME/.local/share/shellx-native`
/// elsewhere (tests and development). Not created. On Windows an unset or
/// empty `LOCALAPPDATA` is an error (no guessed fallback such as
/// `C:\Users\Default`); the app then shows it and keeps local terminals.
pub fn native_dir() -> io::Result<PathBuf> {
    native_dir_from(
        cfg!(windows),
        std::env::var_os("LOCALAPPDATA"),
        std::env::var_os("HOME"),
    )
}

fn native_dir_from(
    windows: bool,
    local_app_data: Option<OsString>,
    home: Option<OsString>,
) -> io::Result<PathBuf> {
    if windows {
        let base = local_app_data
            .filter(|v| !v.is_empty())
            .map(PathBuf::from)
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "LOCALAPPDATA is not set"))?;
        Ok(base.join("ShellX").join("native"))
    } else {
        let home = home
            .filter(|v| !v.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(std::env::temp_dir);
        Ok(home.join(".local").join("share").join("shellx-native"))
    }
}

fn ensure(path: PathBuf) -> io::Result<PathBuf> {
    std::fs::create_dir_all(&path)?;
    Ok(path)
}

/// shellx-core `state_dir` (device key, session). Created on demand.
pub fn core_dir() -> io::Result<PathBuf> {
    ensure(native_dir()?.join("core"))
}

/// cmux-remote client identity. Created on demand.
pub fn remote_dir() -> io::Result<PathBuf> {
    ensure(native_dir()?.join("remote"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dirs_are_under_native_and_distinct() {
        let n = native_dir().unwrap();
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

    #[test]
    fn windows_layout_and_missing_local_app_data() {
        let base = if cfg!(windows) {
            r"C:\Users\a\AppData\Local"
        } else {
            "/l"
        };
        let n = native_dir_from(true, Some(base.into()), None).unwrap();
        assert_eq!(n, PathBuf::from(base).join("ShellX").join("native"));
        for missing in [None, Some(OsString::new())] {
            let e = native_dir_from(true, missing, Some("/home/x".into())).unwrap_err();
            assert_eq!(e.kind(), io::ErrorKind::NotFound);
            assert!(e.to_string().contains("LOCALAPPDATA"));
        }
        let n = native_dir_from(false, None, Some("/home/x".into())).unwrap();
        assert_eq!(n, PathBuf::from("/home/x/.local/share/shellx-native"));
    }
}
