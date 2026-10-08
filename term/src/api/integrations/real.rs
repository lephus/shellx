//! The real file system and terminal behind [`Fs`] and [`Prompt`].

use super::{Fs, Prompt, ReadError};
use std::fs;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};

/// D26: an agent's file over this is left alone.
const MAX_BYTES: u64 = 1 << 20;

pub struct RealFs;

impl Fs for RealFs {
    fn read(&self, p: &Path) -> Result<Option<String>, ReadError> {
        let file = match fs::File::open(p) {
            Ok(f) => f,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(_) => return Err(ReadError::Io),
        };
        let mut buf = Vec::new();
        file.take(MAX_BYTES + 1)
            .read_to_end(&mut buf)
            .map_err(|_| ReadError::Io)?;
        if buf.len() as u64 > MAX_BYTES {
            return Err(ReadError::TooBig);
        }
        String::from_utf8(buf)
            .map(Some)
            .map_err(|_| ReadError::NotText)
    }

    fn exists(&self, p: &Path) -> bool {
        fs::symlink_metadata(p).is_ok()
    }

    fn resolve(&self, p: &Path) -> PathBuf {
        match fs::symlink_metadata(p) {
            // A dangling link still names where the file belongs.
            Ok(m) if m.file_type().is_symlink() => fs::canonicalize(p)
                .or_else(|_| {
                    fs::read_link(p).map(|t| match p.parent() {
                        Some(dir) if t.is_relative() => dir.join(t),
                        _ => t,
                    })
                })
                .unwrap_or_else(|_| p.to_path_buf()),
            _ => p.to_path_buf(),
        }
    }

    fn write_atomic(&mut self, p: &Path, text: &str, like: Option<&Path>) -> io::Result<()> {
        let dir = p.parent().unwrap_or(Path::new("."));
        let name = p
            .file_name()
            .map(|n| n.to_string_lossy())
            .unwrap_or_default();
        let tmp = dir.join(format!(".{name}.shellx-tmp-{}", std::process::id()));
        let result = (|| {
            let mut opts = fs::OpenOptions::new();
            opts.write(true).create_new(true);
            #[cfg(unix)]
            std::os::unix::fs::OpenOptionsExt::mode(&mut opts, 0o600);
            let mut f = opts.open(&tmp)?;
            f.write_all(text.as_bytes())?;
            if let Some(like) = like {
                if let Ok(m) = fs::metadata(like) {
                    f.set_permissions(m.permissions())?;
                }
            }
            f.sync_all()?;
            drop(f);
            fs::rename(&tmp, p)
        })();
        if result.is_err() {
            let _ = fs::remove_file(&tmp);
        }
        result
    }

    fn copy_mode_file(&mut self, from: &Path, to: &Path) -> io::Result<()> {
        let bytes = fs::read(from)?;
        let mut opts = fs::OpenOptions::new();
        // Never over an older copy.
        opts.write(true).create_new(true);
        #[cfg(unix)]
        std::os::unix::fs::OpenOptionsExt::mode(&mut opts, 0o600);
        let mut f = opts.open(to)?;
        let result = f
            .write_all(&bytes)
            .and_then(|()| f.set_permissions(fs::metadata(from)?.permissions()))
            .and_then(|()| f.sync_all());
        if result.is_err() {
            let _ = fs::remove_file(to);
        }
        result
    }

    fn remove(&mut self, p: &Path) -> io::Result<()> {
        if fs::symlink_metadata(p)?.is_dir() {
            fs::remove_dir(p)
        } else {
            fs::remove_file(p)
        }
    }

    fn create_dir_all(&mut self, p: &Path) -> io::Result<()> {
        fs::create_dir_all(p)
    }
}

/// Questions go to the controlling terminal, not to stdout (which may be
/// a pipe): `/dev/tty` (Windows: `CONOUT$`/`CONIN$`).
#[derive(Default)]
pub struct RealPrompt {
    tty: Option<(fs::File, fs::File)>,
    tried: bool,
}

impl RealPrompt {
    fn open(&mut self) -> Option<&mut (fs::File, fs::File)> {
        if !self.tried {
            self.tried = true;
            #[cfg(unix)]
            {
                let open = || {
                    fs::OpenOptions::new()
                        .read(true)
                        .write(true)
                        .open("/dev/tty")
                };
                if let (Ok(r), Ok(w)) = (open(), open()) {
                    self.tty = Some((r, w));
                }
            }
            #[cfg(windows)]
            {
                let r = fs::OpenOptions::new().read(true).write(true).open("CONIN$");
                let w = fs::OpenOptions::new()
                    .read(true)
                    .write(true)
                    .open("CONOUT$");
                if let (Ok(r), Ok(w)) = (r, w) {
                    self.tty = Some((r, w));
                }
            }
        }
        self.tty.as_mut()
    }
}

impl Prompt for RealPrompt {
    fn available(&mut self) -> bool {
        self.open().is_some()
    }

    fn ask(&mut self, question: &str) -> Option<String> {
        let (r, w) = self.open()?;
        w.write_all(question.as_bytes()).ok()?;
        w.flush().ok()?;
        let mut line = Vec::new();
        let mut byte = [0u8; 1];
        // One line, at most a few bytes of it matter.
        while line.len() < 256 {
            match r.read(&mut byte) {
                Ok(1) if byte[0] == b'\n' => return Some(String::from_utf8_lossy(&line).into()),
                Ok(1) => line.push(byte[0]),
                _ => break,
            }
        }
        (!line.is_empty()).then(|| String::from_utf8_lossy(&line).into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("shellx-realfs-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn reads_absent_big_and_binary_files() {
        let d = dir("read");
        let fs_ = RealFs;
        assert_eq!(fs_.read(&d.join("none")), Ok(None));
        fs::write(d.join("ok"), "héllo").unwrap();
        assert_eq!(fs_.read(&d.join("ok")), Ok(Some("héllo".into())));
        fs::write(d.join("big"), vec![b'a'; (MAX_BYTES + 1) as usize]).unwrap();
        assert_eq!(fs_.read(&d.join("big")), Err(ReadError::TooBig));
        fs::write(d.join("bin"), [0xff, 0xfe]).unwrap();
        assert_eq!(fs_.read(&d.join("bin")), Err(ReadError::NotText));
        assert_eq!(fs_.read(&d), Err(ReadError::Io));
        fs::write(d.join("edge"), vec![b'a'; MAX_BYTES as usize]).unwrap();
        assert!(fs_.read(&d.join("edge")).unwrap().is_some());
        let _ = fs::remove_dir_all(&d);
    }

    #[cfg(unix)]
    #[test]
    fn write_atomic_keeps_the_mode_and_leaves_no_temp_file() {
        use std::os::unix::fs::PermissionsExt;
        let d = dir("atomic");
        let p = d.join("settings.json");
        fs::write(&p, "old").unwrap();
        fs::set_permissions(&p, fs::Permissions::from_mode(0o640)).unwrap();
        RealFs.write_atomic(&p, "new", Some(&p)).unwrap();
        assert_eq!(fs::read_to_string(&p).unwrap(), "new");
        assert_eq!(
            fs::metadata(&p).unwrap().permissions().mode() & 0o777,
            0o640
        );
        let names: Vec<_> = fs::read_dir(&d)
            .unwrap()
            .map(|e| e.unwrap().file_name())
            .collect();
        assert_eq!(names.len(), 1, "{names:?}");
        // A new file is private.
        let q = d.join("new.json");
        RealFs.write_atomic(&q, "x", None).unwrap();
        assert_eq!(
            fs::metadata(&q).unwrap().permissions().mode() & 0o777,
            0o600
        );
        let _ = fs::remove_dir_all(&d);
    }

    #[cfg(unix)]
    #[test]
    fn a_symlink_resolves_and_the_link_survives_a_write_to_its_target() {
        let d = dir("link");
        let target = d.join("real.json");
        let link = d.join("link.json");
        fs::write(&target, "old").unwrap();
        std::os::unix::fs::symlink(&target, &link).unwrap();
        let resolved = RealFs.resolve(&link);
        assert_eq!(resolved, fs::canonicalize(&target).unwrap());
        RealFs
            .write_atomic(&resolved, "new", Some(&resolved))
            .unwrap();
        assert!(fs::symlink_metadata(&link)
            .unwrap()
            .file_type()
            .is_symlink());
        assert_eq!(fs::read_to_string(&link).unwrap(), "new");
        assert_eq!(RealFs.resolve(&target), target);
        let _ = fs::remove_dir_all(&d);
    }

    #[cfg(unix)]
    #[test]
    fn the_backup_has_the_mode_and_is_never_overwritten() {
        use std::os::unix::fs::PermissionsExt;
        let d = dir("bak");
        let p = d.join("a.json");
        let bak = d.join("a.json.shellx-bak");
        fs::write(&p, "one").unwrap();
        fs::set_permissions(&p, fs::Permissions::from_mode(0o600)).unwrap();
        RealFs.copy_mode_file(&p, &bak).unwrap();
        assert_eq!(fs::read_to_string(&bak).unwrap(), "one");
        assert_eq!(
            fs::metadata(&bak).unwrap().permissions().mode() & 0o777,
            0o600
        );
        fs::write(&p, "two").unwrap();
        assert!(RealFs.copy_mode_file(&p, &bak).is_err());
        assert_eq!(fs::read_to_string(&bak).unwrap(), "one");
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn remove_takes_a_file_or_an_empty_folder_only() {
        let d = dir("remove");
        let sub = d.join("sub");
        fs::create_dir_all(&sub).unwrap();
        fs::write(sub.join("f"), "x").unwrap();
        assert!(RealFs.remove(&sub).is_err(), "not empty");
        RealFs.remove(&sub.join("f")).unwrap();
        RealFs.remove(&sub).unwrap();
        assert!(!sub.exists());
        let _ = fs::remove_dir_all(&d);
    }
}
