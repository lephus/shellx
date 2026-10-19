//! Persists `Links` at `remote_dir()/links.json`. No secrets inside (invite
//! file paths only). Security review note: on Windows the file is protected by
//! the per-user `%LOCALAPPDATA%` ACL; no extra ACL is applied. Writes are
//! atomic (temp file with a name unique in the process + rename).
//!
//! Several threads write it (the pairing panel's job, each remote session's
//! `forget_invite`), each through its own `LinksStore`: every load, save and
//! `update` (load-modify-save) holds one process-wide lock, so no writer
//! loses another's record.
//!
//! A corrupt `links.json` is never overwritten in place: `load` renames it to
//! `links.json.bad-<unix seconds>` (logged), and the app starts with no links.
#![cfg_attr(not(windows), allow(dead_code))] // the window (cfg(windows)) uses it

use std::io;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, MutexGuard};
use std::time::{SystemTime, UNIX_EPOCH};

use shellx_model::links::Links;

/// Held around every read-modify-write of a links file in this process.
static LINKS_LOCK: Mutex<()> = Mutex::new(());

/// Makes each temp file name unique within the process.
static TMP_SEQ: AtomicU64 = AtomicU64::new(0);

fn links_lock() -> MutexGuard<'static, ()> {
    LINKS_LOCK.lock().unwrap_or_else(|e| e.into_inner())
}

pub struct LinksStore {
    /// `Err` when the state folder is unknown (e.g. `LOCALAPPDATA` unset):
    /// nothing is read, every save fails with this message.
    path: Result<PathBuf, String>,
}

impl LinksStore {
    pub fn new(path: PathBuf) -> LinksStore {
        LinksStore { path: Ok(path) }
    }

    /// A store that holds nothing and refuses to save (`reason` is the save
    /// error the pairing panel shows).
    pub fn unavailable(reason: impl Into<String>) -> LinksStore {
        LinksStore {
            path: Err(reason.into()),
        }
    }

    /// `remote_dir()/links.json`.
    pub fn default_location() -> io::Result<LinksStore> {
        Ok(LinksStore::new(
            crate::paths::remote_dir()?.join("links.json"),
        ))
    }

    /// `default_location`, or an unavailable store carrying the path error.
    pub fn default_or_unavailable() -> LinksStore {
        LinksStore::default_location().unwrap_or_else(|e| LinksStore::unavailable(e.to_string()))
    }

    #[allow(dead_code)] // tests
    pub fn path(&self) -> Option<&Path> {
        self.path.as_deref().ok()
    }

    /// A missing file is an empty set. A corrupt one is moved aside to
    /// `links.json.bad-<unix>` and an empty set is returned.
    pub fn load(&self) -> io::Result<Links> {
        let _guard = links_lock();
        self.load_locked()
    }

    fn load_locked(&self) -> io::Result<Links> {
        let Ok(path) = &self.path else {
            return Ok(Links::default());
        };
        match std::fs::read(path) {
            Ok(bytes) => match std::str::from_utf8(&bytes)
                .map_err(|e| e.to_string())
                .and_then(|s| Links::load_from_str(s).map_err(|e| e.to_string()))
            {
                Ok(links) => Ok(links),
                Err(e) => {
                    let bad = quarantine(path)?;
                    eprintln!(
                        "shellx: {} is not valid ({e}); moved it to {} and starting with no links",
                        path.display(),
                        bad.display()
                    );
                    Ok(Links::default())
                }
            },
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(Links::default()),
            Err(e) => Err(e),
        }
    }

    /// Load, `change`, save, under the process-wide lock (no other writer
    /// runs in between). Returns what was saved.
    pub fn update(&self, change: impl FnOnce(&mut Links)) -> io::Result<Links> {
        let _guard = links_lock();
        let mut links = self.load_locked()?;
        change(&mut links);
        self.save_locked(&links)?;
        Ok(links)
    }

    pub fn save(&self, links: &Links) -> io::Result<()> {
        let _guard = links_lock();
        self.save_locked(links)
    }

    fn save_locked(&self, links: &Links) -> io::Result<()> {
        let path = self
            .path
            .as_ref()
            .map_err(|reason| io::Error::other(reason.clone()))?;
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let seq = TMP_SEQ.fetch_add(1, Ordering::Relaxed);
        let tmp = path.with_extension(format!("json.tmp{}-{seq}", std::process::id()));
        std::fs::write(&tmp, links.to_string_pretty())?;
        std::fs::rename(&tmp, path).inspect_err(|_| {
            let _ = std::fs::remove_file(&tmp);
        })
    }
}

/// Renames `path` to `<name>.bad-<unix>` (`-<n>` added if that exists).
fn quarantine(path: &Path) -> io::Result<PathBuf> {
    let unix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs());
    let name = path
        .file_name()
        .map_or_else(|| "links.json".into(), |n| n.to_string_lossy().into_owned());
    let mut bad = path.with_file_name(format!("{name}.bad-{unix}"));
    let mut n = 1;
    while bad.exists() {
        bad = path.with_file_name(format!("{name}.bad-{unix}-{n}"));
        n += 1;
    }
    std::fs::rename(path, &bad)?;
    Ok(bad)
}

#[cfg(test)]
mod tests {
    use super::*;
    use shellx_model::links::RemoteLink;

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("shellx-links-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        d
    }

    fn sample() -> Links {
        let mut l = Links::default();
        l.upsert(RemoteLink {
            machine_id: "m1".into(),
            machine_name: "Mac".into(),
            relay_route: "r".into(),
            relay_slot: "s".into(),
            invite_path: None,
            daemon_fingerprint: "f".into(),
            enrolled: true,
        });
        l
    }

    #[test]
    fn missing_is_empty_save_load() {
        let dir = tmp("store");
        let store = LinksStore::new(dir.join("sub").join("links.json"));
        assert_eq!(store.load().unwrap(), Links::default());
        let l = sample();
        store.save(&l).unwrap();
        store.save(&l).unwrap(); // replaces
        assert_eq!(store.load().unwrap(), l);
        let parent = store.path().unwrap().parent().unwrap();
        assert_eq!(std::fs::read_dir(parent).unwrap().count(), 1);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn corrupt_file_is_moved_aside_and_starts_fresh() {
        let dir = tmp("corrupt");
        std::fs::create_dir_all(&dir).unwrap();
        let store = LinksStore::new(dir.join("links.json"));
        std::fs::write(dir.join("links.json"), "not json").unwrap();
        assert_eq!(store.load().unwrap(), Links::default());
        assert!(!dir.join("links.json").exists());
        let bad: Vec<_> = std::fs::read_dir(&dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        assert_eq!(bad.len(), 1, "{bad:?}");
        assert!(bad[0].starts_with("links.json.bad-"), "{bad:?}");
        assert_eq!(
            std::fs::read_to_string(dir.join(&bad[0])).unwrap(),
            "not json"
        );
        // a second corrupt file in the same second gets its own name
        std::fs::write(dir.join("links.json"), "{").unwrap();
        assert_eq!(store.load().unwrap(), Links::default());
        assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 2);
        // and saving works again
        store.save(&sample()).unwrap();
        assert_eq!(store.load().unwrap(), sample());
        let _ = std::fs::remove_dir_all(&dir);
    }

    fn link(machine: &str) -> RemoteLink {
        RemoteLink {
            machine_id: machine.into(),
            machine_name: format!("Mac {machine}"),
            relay_route: "r".into(),
            relay_slot: format!("slot-{machine}"),
            invite_path: None,
            daemon_fingerprint: "f".into(),
            enrolled: false,
        }
    }

    #[test]
    fn concurrent_updates_through_separate_stores_lose_nothing() {
        // PairingService and every session's forget_invite write links.json
        // from their own threads, each with its own LinksStore.
        const N: usize = 16;
        for round in 0..5 {
            let dir = tmp(&format!("race-{round}"));
            let path = dir.join("links.json");
            let barrier = std::sync::Arc::new(std::sync::Barrier::new(N));
            let threads: Vec<_> = (0..N)
                .map(|i| {
                    let (path, barrier) = (path.clone(), barrier.clone());
                    std::thread::spawn(move || {
                        let store = LinksStore::new(path);
                        barrier.wait();
                        store
                            .update(|links| links.upsert(link(&format!("m{i}"))))
                            .unwrap();
                    })
                })
                .collect();
            for t in threads {
                t.join().unwrap();
            }
            let text = std::fs::read_to_string(&path).unwrap();
            let links = Links::load_from_str(&text).expect("valid links.json");
            for i in 0..N {
                assert!(
                    links.get(&format!("m{i}")).is_some(),
                    "round {round}: m{i} lost"
                );
            }
            // no temp file is left behind
            assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 1);
            let _ = std::fs::remove_dir_all(&dir);
        }
    }

    #[test]
    fn update_returns_the_saved_links() {
        let dir = tmp("update");
        let store = LinksStore::new(dir.join("links.json"));
        let saved = store.update(|l| l.upsert(link("a"))).unwrap();
        assert!(saved.get("a").is_some());
        assert_eq!(store.load().unwrap(), saved);
        let e = LinksStore::unavailable("no dir")
            .update(|l| l.upsert(link("a")))
            .unwrap_err();
        assert_eq!(e.to_string(), "no dir");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn unavailable_store_is_empty_and_refuses_saves() {
        let store = LinksStore::unavailable("LOCALAPPDATA is not set");
        assert!(store.path().is_none());
        assert_eq!(store.load().unwrap(), Links::default());
        let e = store.save(&sample()).unwrap_err();
        assert_eq!(e.to_string(), "LOCALAPPDATA is not set");
    }
}
