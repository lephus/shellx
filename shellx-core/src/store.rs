//! Owner-only state store for everything secret that shellx-core keeps
//! (`session.json`, `device.key`, `machine.json`, `tickets/*`).
//!
//! Unix guarantees:
//! * `root` and `root/tickets` are directories owned by `geteuid()` with no
//!   `0o077` bit; they are created `0700`. A symlink, a non-directory, a wrong
//!   owner or loose permissions is refused with `state_dir_insecure`.
//! * Directories are opened once with `O_DIRECTORY|O_NOFOLLOW` and every later
//!   operation goes through that fd (`openat`/`renameat`/`unlinkat`), so
//!   swapping a path component afterwards cannot redirect I/O. The directory
//!   fd is re-checked (`fstat`) on every operation.
//! * Files are opened `O_NOFOLLOW`; ownership, type and mode are checked on the
//!   opened fd (`fstat`), not on the path. Loose files give `state_file_insecure`.
//! * Writes go to an unpredictable temp name (`name.tmp.<128-bit random hex>`)
//!   created `O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC` mode `0600`, then `fchmod 0600`
//!   (umask-proof), written, `fsync`ed, `renameat`ed over the target inside the
//!   same directory, and the directory is `fsync`ed. Failed writes remove the temp.
//! * Reads return `Zeroizing` buffers (allocated once, never grown). Errors and
//!   `Debug` carry paths and error kinds only, never file bytes.
//! * File names must match `^[a-z0-9][a-z0-9._-]{0,63}$`, optionally prefixed by
//!   exactly `tickets/`; this rules out traversal, hidden files and separators.
//!
//! Known gap (post-sprint security item, see master plan "after the sprint"):
//! on non-Unix targets (the Windows client) the same API uses plain create and
//! rename under the per-user `%LOCALAPPDATA%` directory with NO ACL hardening,
//! no symlink/reparse-point checks and no ownership checks. Keychain/DPAPI and
//! ACLs are the upgrade. `fsync` on macOS is not `F_FULLFSYNC`.

use crate::envelope::CoreError;
use std::fmt;
use std::path::{Path, PathBuf};
use zeroize::Zeroizing;

/// Upper bound for a secret file (tokens, keys, tickets are tiny).
const MAX_SECRET_BYTES: u64 = 1 << 20;

/// Where a validated name lives.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Place {
    Root,
    Tickets,
}

fn valid_file_part(s: &str) -> bool {
    let b = s.as_bytes();
    if b.is_empty() || b.len() > 64 {
        return false;
    }
    let first = b[0];
    if !(first.is_ascii_lowercase() || first.is_ascii_digit()) {
        return false;
    }
    b.iter()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || matches!(c, b'.' | b'_' | b'-'))
}

/// `name` is a bare file name or `tickets/<file>`.
fn parse_name(name: &str) -> Result<(Place, &str), CoreError> {
    let bad = || CoreError::invalid_params("invalid state file name");
    let (place, file) = match name.strip_prefix("tickets/") {
        Some(rest) => (Place::Tickets, rest),
        None => (Place::Root, name),
    };
    if !valid_file_part(file) || (place == Place::Root && file == "tickets") {
        return Err(bad());
    }
    Ok((place, file))
}

pub struct StateStore {
    root: PathBuf,
    #[cfg(unix)]
    root_fd: std::os::fd::OwnedFd,
    #[cfg(unix)]
    tickets_fd: std::os::fd::OwnedFd,
}

impl fmt::Debug for StateStore {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("StateStore").field("root", &self.root).finish_non_exhaustive()
    }
}

#[cfg(unix)]
mod imp {
    use super::*;
    use std::ffi::CString;
    use std::fs::File;
    use std::io::{Read, Write};
    use std::os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd};
    use std::os::unix::ffi::OsStrExt;

    /// Only for validated names (no NUL possible); `open` checks the root path itself.
    fn cstr(s: &[u8]) -> CString {
        CString::new(s).unwrap_or_default()
    }

    fn io_err(op: &str, path: &Path) -> CoreError {
        let e = std::io::Error::last_os_error();
        CoreError::new("io", format!("{op} {}: {e}", path.display()))
    }

    fn errno() -> i32 {
        std::io::Error::last_os_error().raw_os_error().unwrap_or(0)
    }

    fn dir_insecure(path: &Path, why: &str) -> CoreError {
        CoreError::new("state_dir_insecure", format!("{}: {why}", path.display()))
    }

    fn file_insecure(path: &Path, why: &str) -> CoreError {
        CoreError::new("state_file_insecure", format!("{}: {why}", path.display()))
    }

    fn fstat(fd: RawFd) -> Option<libc::stat> {
        let mut st: libc::stat = unsafe { std::mem::zeroed() };
        // SAFETY: st is a valid out pointer; fd is a live descriptor.
        (unsafe { libc::fstat(fd, &mut st) } == 0).then_some(st)
    }

    fn euid() -> u32 {
        // SAFETY: no preconditions.
        unsafe { libc::geteuid() }
    }

    /// Owner + mode check on an already opened directory fd.
    fn check_dir_fd(fd: RawFd, path: &Path) -> Result<(), CoreError> {
        let st = fstat(fd).ok_or_else(|| io_err("fstat", path))?;
        if st.st_mode & libc::S_IFMT != libc::S_IFDIR {
            return Err(dir_insecure(path, "not a directory"));
        }
        if st.st_uid != euid() {
            return Err(dir_insecure(path, "not owned by the current user"));
        }
        if st.st_mode & 0o077 != 0 {
            return Err(dir_insecure(path, "group/other permissions set (need 0700)"));
        }
        Ok(())
    }

    /// Ensure `name` under `dirfd` (AT_FDCWD for an absolute `name`) is a secure
    /// directory and return it opened `O_NOFOLLOW`.
    fn ensure_dir(dirfd: RawFd, name: &CString, path: &Path) -> Result<OwnedFd, CoreError> {
        let mut created = false;
        let mut st: libc::stat = unsafe { std::mem::zeroed() };
        // SAFETY: valid C string and out pointer.
        let rc = unsafe { libc::fstatat(dirfd, name.as_ptr(), &mut st, libc::AT_SYMLINK_NOFOLLOW) };
        if rc == 0 {
            if st.st_mode & libc::S_IFMT != libc::S_IFDIR {
                return Err(dir_insecure(path, "is a symlink or not a directory"));
            }
        } else if errno() == libc::ENOENT {
            // SAFETY: valid C string.
            if unsafe { libc::mkdirat(dirfd, name.as_ptr(), 0o700) } == 0 {
                created = true;
            } else if errno() != libc::EEXIST {
                return Err(io_err("mkdir", path));
            }
        } else {
            return Err(io_err("stat", path));
        }
        let flags = libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC;
        // SAFETY: valid C string.
        let fd = unsafe { libc::openat(dirfd, name.as_ptr(), flags) };
        if fd < 0 {
            return Err(match errno() {
                libc::ELOOP | libc::ENOTDIR => dir_insecure(path, "is a symlink or not a directory"),
                _ => io_err("open", path),
            });
        }
        // SAFETY: fd is a fresh descriptor we own.
        let fd = unsafe { OwnedFd::from_raw_fd(fd) };
        if created {
            // mkdir mode is subject to the umask; make it exactly 0700.
            // SAFETY: live fd.
            if unsafe { libc::fchmod(fd.as_raw_fd(), 0o700) } != 0 {
                return Err(io_err("fchmod", path));
            }
        }
        check_dir_fd(fd.as_raw_fd(), path)?;
        Ok(fd)
    }

    fn random_hex() -> Result<String, CoreError> {
        let mut b = [0u8; 16];
        getrandom::fill(&mut b).map_err(|_| CoreError::new("crypto", "random source unavailable"))?;
        Ok(b.iter().map(|x| format!("{x:02x}")).collect())
    }

    impl StateStore {
        pub fn open(root: &Path) -> Result<StateStore, CoreError> {
            if let Some(parent) = root.parent() {
                if !parent.as_os_str().is_empty() {
                    std::fs::create_dir_all(parent)
                        .map_err(|e| CoreError::new("io", format!("mkdir {}: {e}", parent.display())))?;
                }
            }
            let root_c = CString::new(root.as_os_str().as_bytes())
                .map_err(|_| CoreError::invalid_params("state_dir contains a NUL byte"))?;
            let root_fd = ensure_dir(libc::AT_FDCWD, &root_c, root)?;
            let tickets_path = root.join("tickets");
            let tickets_fd = ensure_dir(root_fd.as_raw_fd(), &cstr(b"tickets"), &tickets_path)?;
            Ok(StateStore { root: root.to_path_buf(), root_fd, tickets_fd })
        }

        /// Directory fd + file part for `name`, re-verifying the directory on every call.
        fn locate<'a>(&self, name: &'a str) -> Result<(&OwnedFd, &'a str, PathBuf), CoreError> {
            let (place, file) = parse_name(name)?;
            let (fd, dir) = match place {
                Place::Root => (&self.root_fd, self.root.clone()),
                Place::Tickets => (&self.tickets_fd, self.root.join("tickets")),
            };
            check_dir_fd(fd.as_raw_fd(), &dir)?;
            let path = dir.join(file);
            Ok((fd, file, path))
        }

        pub fn write_secret(&self, name: &str, bytes: &[u8]) -> Result<PathBuf, CoreError> {
            let (dirfd, file, path) = self.locate(name)?;
            let dfd = dirfd.as_raw_fd();
            let final_c = cstr(file.as_bytes());

            // Refuse to replace a symlink or non-regular file (rename would not
            // follow it, but a planted link means the dir is not ours).
            let mut st: libc::stat = unsafe { std::mem::zeroed() };
            // SAFETY: valid C string and out pointer.
            if unsafe { libc::fstatat(dfd, final_c.as_ptr(), &mut st, libc::AT_SYMLINK_NOFOLLOW) } == 0 {
                if st.st_mode & libc::S_IFMT != libc::S_IFREG {
                    return Err(file_insecure(&path, "is a symlink or not a regular file"));
                }
            } else if errno() != libc::ENOENT {
                return Err(io_err("stat", &path));
            }

            let tmp_name = format!("{file}.tmp.{}", random_hex()?);
            let tmp_c = cstr(tmp_name.as_bytes());
            let flags = libc::O_WRONLY | libc::O_CREAT | libc::O_EXCL | libc::O_NOFOLLOW | libc::O_CLOEXEC;
            // SAFETY: valid C string; mode passed as c_uint for the variadic call.
            let fd = unsafe { libc::openat(dfd, tmp_c.as_ptr(), flags, 0o600 as libc::c_uint) };
            if fd < 0 {
                return Err(io_err("create temp", &path));
            }
            // SAFETY: fresh descriptor we own; File closes it.
            let mut f = File::from(unsafe { OwnedFd::from_raw_fd(fd) });
            let cleanup = |tmp_c: &CString| {
                // SAFETY: valid C string.
                unsafe { libc::unlinkat(dfd, tmp_c.as_ptr(), 0) };
            };
            let res = (|| {
                // SAFETY: live fd.
                if unsafe { libc::fchmod(f.as_raw_fd(), 0o600) } != 0 {
                    return Err(io_err("fchmod", &path));
                }
                f.write_all(bytes).map_err(|e| CoreError::new("io", format!("write {}: {e}", path.display())))?;
                f.sync_all().map_err(|e| CoreError::new("io", format!("fsync {}: {e}", path.display())))?;
                // SAFETY: valid C strings; both names are in the same directory.
                if unsafe { libc::renameat(dfd, tmp_c.as_ptr(), dfd, final_c.as_ptr()) } != 0 {
                    return Err(io_err("rename", &path));
                }
                Ok(())
            })();
            drop(f);
            if let Err(e) = res {
                cleanup(&tmp_c);
                return Err(e);
            }
            // SAFETY: live directory fd.
            if unsafe { libc::fsync(dfd) } != 0 {
                return Err(io_err("fsync dir", &path));
            }
            Ok(path)
        }

        pub fn read_secret(&self, name: &str) -> Result<Option<Zeroizing<Vec<u8>>>, CoreError> {
            let (dirfd, file, path) = self.locate(name)?;
            let final_c = cstr(file.as_bytes());
            // O_NONBLOCK so a planted FIFO cannot hang open(); type is checked below.
            let flags = libc::O_RDONLY | libc::O_NOFOLLOW | libc::O_CLOEXEC | libc::O_NONBLOCK;
            // SAFETY: valid C string.
            let fd = unsafe { libc::openat(dirfd.as_raw_fd(), final_c.as_ptr(), flags) };
            if fd < 0 {
                return match errno() {
                    libc::ENOENT => Ok(None),
                    libc::ELOOP => Err(file_insecure(&path, "is a symlink")),
                    _ => Err(io_err("open", &path)),
                };
            }
            // SAFETY: fresh descriptor we own.
            let mut f = File::from(unsafe { OwnedFd::from_raw_fd(fd) });
            let st = fstat(f.as_raw_fd()).ok_or_else(|| io_err("fstat", &path))?;
            if st.st_mode & libc::S_IFMT != libc::S_IFREG {
                return Err(file_insecure(&path, "not a regular file"));
            }
            if st.st_uid != euid() {
                return Err(file_insecure(&path, "not owned by the current user"));
            }
            if st.st_mode & 0o077 != 0 {
                return Err(file_insecure(&path, "group/other permissions set (need 0600)"));
            }
            let size = st.st_size as u64;
            if size > MAX_SECRET_BYTES {
                return Err(CoreError::new("io", format!("{}: file too large", path.display())));
            }
            let mut buf = Zeroizing::new(vec![0u8; size as usize]);
            f.read_exact(&mut buf[..])
                .map_err(|e| CoreError::new("io", format!("read {}: {e}", path.display())))?;
            Ok(Some(buf))
        }

        pub fn remove(&self, name: &str) -> Result<(), CoreError> {
            let (dirfd, file, path) = self.locate(name)?;
            let final_c = cstr(file.as_bytes());
            // unlinkat removes a symlink itself, never its target.
            // SAFETY: valid C string.
            if unsafe { libc::unlinkat(dirfd.as_raw_fd(), final_c.as_ptr(), 0) } != 0 && errno() != libc::ENOENT {
                return Err(io_err("remove", &path));
            }
            // SAFETY: live directory fd.
            if unsafe { libc::fsync(dirfd.as_raw_fd()) } != 0 {
                return Err(io_err("fsync dir", &path));
            }
            Ok(())
        }
    }
}

#[cfg(not(unix))]
mod imp {
    use super::*;
    use std::io::Write;

    fn io(op: &str, path: &Path, e: std::io::Error) -> CoreError {
        CoreError::new("io", format!("{op} {}: {e}", path.display()))
    }

    fn rand_hex() -> Result<String, CoreError> {
        let mut b = [0u8; 16];
        getrandom::fill(&mut b).map_err(|_| CoreError::new("crypto", "random source unavailable"))?;
        Ok(b.iter().map(|x| format!("{x:02x}")).collect())
    }

    impl StateStore {
        /// No ACL hardening here: see the module header (post-sprint item).
        pub fn open(root: &Path) -> Result<StateStore, CoreError> {
            let tickets = root.join("tickets");
            std::fs::create_dir_all(&tickets).map_err(|e| io("mkdir", &tickets, e))?;
            Ok(StateStore { root: root.to_path_buf() })
        }

        fn path_for(&self, name: &str) -> Result<PathBuf, CoreError> {
            let (place, file) = parse_name(name)?;
            Ok(match place {
                Place::Root => self.root.join(file),
                Place::Tickets => self.root.join("tickets").join(file),
            })
        }

        pub fn write_secret(&self, name: &str, bytes: &[u8]) -> Result<PathBuf, CoreError> {
            let path = self.path_for(name)?;
            let tmp = path.with_file_name(format!(
                "{}.tmp.{}",
                path.file_name().and_then(|n| n.to_str()).unwrap_or("x"),
                rand_hex()?
            ));
            let res = (|| {
                let mut f = std::fs::OpenOptions::new()
                    .write(true)
                    .create_new(true)
                    .open(&tmp)
                    .map_err(|e| io("create temp", &path, e))?;
                f.write_all(bytes).map_err(|e| io("write", &path, e))?;
                f.sync_all().map_err(|e| io("fsync", &path, e))?;
                drop(f);
                std::fs::rename(&tmp, &path).map_err(|e| io("rename", &path, e))
            })();
            if let Err(e) = res {
                let _ = std::fs::remove_file(&tmp);
                return Err(e);
            }
            Ok(path)
        }

        pub fn read_secret(&self, name: &str) -> Result<Option<Zeroizing<Vec<u8>>>, CoreError> {
            let path = self.path_for(name)?;
            match std::fs::read(&path) {
                Ok(v) if v.len() as u64 > MAX_SECRET_BYTES => {
                    Err(CoreError::new("io", format!("{}: file too large", path.display())))
                }
                Ok(v) => Ok(Some(Zeroizing::new(v))),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
                Err(e) => Err(io("read", &path, e)),
            }
        }

        pub fn remove(&self, name: &str) -> Result<(), CoreError> {
            let path = self.path_for(name)?;
            match std::fs::remove_file(&path) {
                Ok(()) => Ok(()),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
                Err(e) => Err(io("remove", &path, e)),
            }
        }
    }
}
