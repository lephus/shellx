//! Where the host listens: A5b D5 `mux/endpoint` (7 lines, 0600).

use std::io::Read;
use std::path::{Path, PathBuf};

#[derive(Clone, PartialEq, Eq)]
pub struct MuxEndpoint {
    pub address: String,
    pub secret: [u8; 32],
    pub protocol: i64,
    pub app: String,
}

impl std::fmt::Debug for MuxEndpoint {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("MuxEndpoint")
            .field("address", &self.address)
            .field("secret", &"<redacted>")
            .field("protocol", &self.protocol)
            .field("app", &self.app)
            .finish()
    }
}

pub fn parse(text: &str) -> Option<MuxEndpoint> {
    let mut lines = text.lines();
    if lines.next()? != "v=1" {
        return None;
    }
    let mut kv = std::collections::HashMap::new();
    for l in lines {
        let (k, v) = l.split_once('=')?;
        kv.insert(k, v);
    }
    let hex = kv.get("secret")?;
    if hex.len() != 64 || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    let mut secret = [0u8; 32];
    for (i, s) in secret.iter_mut().enumerate() {
        *s = u8::from_str_radix(&hex[2 * i..2 * i + 2], 16).ok()?;
    }
    Some(MuxEndpoint {
        address: kv.get("address").filter(|a| !a.is_empty())?.to_string(),
        secret,
        protocol: kv.get("protocol")?.parse().ok()?,
        app: kv.get("app").unwrap_or(&"").to_string(),
    })
}

/// D30: `$SHELLX_ENDPOINT` (tests), else the A5b location for this user.
#[allow(clippy::let_and_return)] // one binding per platform
pub fn default_path(get: impl Fn(&str) -> Option<String>) -> Option<PathBuf> {
    if let Some(p) = get("SHELLX_ENDPOINT").filter(|p| !p.is_empty()) {
        return Some(PathBuf::from(p));
    }
    #[cfg(unix)]
    let path = get("HOME").filter(|h| !h.is_empty()).map(|h| {
        PathBuf::from(h).join("Library/Application Support/pro.shellx.desktop/mux/endpoint")
    });
    #[cfg(windows)]
    let path = get("LOCALAPPDATA")
        .filter(|h| !h.is_empty())
        .map(|h| PathBuf::from(h).join("ShellX").join("mux").join("endpoint"));
    path
}

/// The real file is ~200 bytes; anything larger is not an endpoint file.
pub const MAX_FILE: usize = 4096;

/// Why [`read`] found no usable endpoint. Messages never contain the secret.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReadError {
    /// No file (or it cannot be opened): ShellX is not running.
    Missing,
    /// The file exists but anyone other than this user could have written
    /// or read it: refused, never used.
    Unsafe(String),
    /// Not an A5b v1 endpoint file.
    Invalid,
}

impl std::fmt::Display for ReadError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ReadError::Missing => write!(f, "ShellX is not running (no endpoint file)"),
            ReadError::Unsafe(why) => write!(f, "refusing the ShellX endpoint file: {why}"),
            ReadError::Invalid => write!(f, "the ShellX endpoint file is not valid"),
        }
    }
}

/// Reads and parses the endpoint file at `path`. On macOS/Linux the file
/// must be a regular file (not a symbolic link — opened with `O_NOFOLLOW`),
/// owned by the current user, mode 0600; the checks run on the opened file,
/// so it cannot be swapped between check and read.
pub fn read(path: &Path) -> Result<MuxEndpoint, ReadError> {
    let file = open(path)?;
    let mut text = String::new();
    file.take(MAX_FILE as u64 + 1)
        .read_to_string(&mut text)
        .map_err(|_| ReadError::Invalid)?;
    if text.len() > MAX_FILE {
        return Err(ReadError::Invalid);
    }
    parse(&text).ok_or(ReadError::Invalid)
}

#[cfg(unix)]
fn open(path: &Path) -> Result<std::fs::File, ReadError> {
    use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
    let file = std::fs::OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
        .open(path);
    let file = match file {
        Ok(f) => f,
        Err(e) if e.raw_os_error() == Some(libc::ELOOP) => {
            return Err(ReadError::Unsafe(format!(
                "{} is a symbolic link",
                path.display()
            )))
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Err(ReadError::Missing),
        Err(e) => {
            return Err(ReadError::Unsafe(format!(
                "{} cannot be opened ({})",
                path.display(),
                e.kind()
            )))
        }
    };
    let meta = file.metadata().map_err(|_| ReadError::Invalid)?;
    if !meta.file_type().is_file() {
        return Err(ReadError::Unsafe(format!(
            "{} is not a regular file",
            path.display()
        )));
    }
    // SAFETY: geteuid has no preconditions and cannot fail.
    let me = unsafe { libc::geteuid() };
    if meta.uid() != me {
        return Err(ReadError::Unsafe(format!(
            "{} is owned by another user (uid {})",
            path.display(),
            meta.uid()
        )));
    }
    if meta.mode() & 0o777 != 0o600 {
        return Err(ReadError::Unsafe(format!(
            "{} has mode {:04o}; it must be 0600",
            path.display(),
            meta.mode() & 0o777
        )));
    }
    Ok(file)
}

/// Windows: `%LOCALAPPDATA%` is per-user and the host writes the file
/// there; no owner/mode check (ACLs are A5b's job).
#[cfg(windows)]
fn open(path: &Path) -> Result<std::fs::File, ReadError> {
    std::fs::File::open(path).map_err(|_| ReadError::Missing)
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEXT: &str = "v=1\naddress=/tmp/x.sock\nsecret=abababababababababababababababababababababababababababababababab\npid=42\ninstance=ffffffffffffffffffffffffffffffff\nprotocol=1\napp=1.7.0\n";

    #[test]
    fn parses_the_a5b_file() {
        let e = parse(TEXT).unwrap();
        assert_eq!(e.address, "/tmp/x.sock");
        assert_eq!(e.secret, [0xab; 32]);
        assert_eq!(e.protocol, 1);
        assert_eq!(e.app, "1.7.0");
        assert!(!format!("{e:?}").contains("abab"));
    }

    #[test]
    fn refuses_other_versions_and_missing_keys() {
        assert!(parse(&TEXT.replace("v=1", "v=2")).is_none());
        assert!(parse(&TEXT.replace("secret=ab", "secret=zz")).is_none());
        assert!(parse(&TEXT.replace("secret=ab", "secret=é")).is_none());
        assert!(parse("v=1\naddress=/x\n").is_none());
        assert!(parse("").is_none());
    }

    #[cfg(unix)]
    #[test]
    fn default_path_follows_home() {
        let p = default_path(|k| (k == "HOME").then(|| "/Users/me".to_string())).unwrap();
        assert_eq!(
            p,
            std::path::PathBuf::from(
                "/Users/me/Library/Application Support/pro.shellx.desktop/mux/endpoint"
            )
        );
        let o = default_path(|k| match k {
            "SHELLX_ENDPOINT" => Some("/tmp/ep".into()),
            _ => None,
        })
        .unwrap();
        assert_eq!(o, std::path::PathBuf::from("/tmp/ep"));
    }

    #[cfg(unix)]
    mod read_file {
        use super::super::*;
        use super::TEXT;
        use std::os::unix::fs::PermissionsExt;
        use std::path::PathBuf;

        fn dir(name: &str) -> PathBuf {
            let d =
                std::env::temp_dir().join(format!("shellx-endpoint-{}-{name}", std::process::id()));
            let _ = std::fs::remove_dir_all(&d);
            std::fs::create_dir_all(&d).unwrap();
            d
        }

        fn write(path: &std::path::Path, text: &str, mode: u32) {
            std::fs::write(path, text).unwrap();
            std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode)).unwrap();
        }

        #[test]
        fn reads_an_owner_only_file() {
            let d = dir("ok");
            let p = d.join("endpoint");
            write(&p, TEXT, 0o600);
            assert_eq!(read(&p).unwrap().secret, [0xab; 32]);
            std::fs::remove_dir_all(&d).unwrap();
        }

        #[test]
        fn a_missing_file_means_not_running() {
            let d = dir("missing");
            assert_eq!(read(&d.join("endpoint")), Err(ReadError::Missing));
            std::fs::remove_dir_all(&d).unwrap();
        }

        #[test]
        fn refuses_group_or_world_access_without_printing_the_secret() {
            let d = dir("mode");
            let p = d.join("endpoint");
            for mode in [0o644, 0o640, 0o604, 0o660, 0o700] {
                write(&p, TEXT, mode);
                let e = read(&p).unwrap_err();
                assert!(matches!(e, ReadError::Unsafe(_)), "{mode:o}: {e:?}");
                assert!(e.to_string().contains("0600"), "{e}");
                assert!(!e.to_string().contains("abab"), "{e}");
                assert!(!format!("{e:?}").contains("abab"));
            }
            std::fs::remove_dir_all(&d).unwrap();
        }

        #[test]
        fn refuses_a_symlink_even_to_a_good_file() {
            let d = dir("link");
            let real = d.join("real");
            write(&real, TEXT, 0o600);
            let link = d.join("endpoint");
            std::os::unix::fs::symlink(&real, &link).unwrap();
            let e = read(&link).unwrap_err();
            assert!(matches!(e, ReadError::Unsafe(_)), "{e:?}");
            assert!(e.to_string().contains("symbolic link"), "{e}");
            std::fs::remove_dir_all(&d).unwrap();
        }

        #[test]
        fn refuses_a_directory_a_huge_file_and_garbage() {
            let d = dir("odd");
            let sub = d.join("endpoint");
            std::fs::create_dir(&sub).unwrap();
            std::fs::set_permissions(&sub, std::fs::Permissions::from_mode(0o600)).unwrap();
            assert!(matches!(read(&sub), Err(ReadError::Unsafe(_))));
            std::fs::set_permissions(&sub, std::fs::Permissions::from_mode(0o700)).unwrap();
            std::fs::remove_dir(&sub).unwrap();
            let p = d.join("endpoint");
            write(&p, &"x".repeat(MAX_FILE + 1), 0o600);
            assert_eq!(read(&p), Err(ReadError::Invalid));
            write(&p, "v=1\ngarbage", 0o600);
            assert_eq!(read(&p), Err(ReadError::Invalid));
            std::fs::remove_dir_all(&d).unwrap();
        }
    }
}
