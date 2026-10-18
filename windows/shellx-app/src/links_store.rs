//! Persists `Links` at `remote_dir()/links.json`. No secrets inside (invite
//! file paths only). Security review note: on Windows the file is protected by
//! the per-user `%LOCALAPPDATA%` ACL; no extra ACL is applied. Writes are
//! atomic (temp file + rename).
#![allow(dead_code)] // wired by the pairing UI (Task 12b)

use std::io;
use std::path::{Path, PathBuf};

use shellx_model::links::Links;

pub struct LinksStore {
    path: PathBuf,
}

impl LinksStore {
    pub fn new(path: PathBuf) -> LinksStore {
        LinksStore { path }
    }

    /// `remote_dir()/links.json`.
    pub fn default_location() -> io::Result<LinksStore> {
        Ok(LinksStore::new(crate::paths::remote_dir()?.join("links.json")))
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// A missing file is an empty set; a corrupt one is an error (it is not
    /// silently overwritten).
    pub fn load(&self) -> io::Result<Links> {
        match std::fs::read_to_string(&self.path) {
            Ok(s) => Links::load_from_str(&s)
                .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e)),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(Links::default()),
            Err(e) => Err(e),
        }
    }

    pub fn save(&self, links: &Links) -> io::Result<()> {
        if let Some(dir) = self.path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let tmp = self.path.with_extension(format!("json.tmp{}", std::process::id()));
        std::fs::write(&tmp, links.to_string_pretty())?;
        std::fs::rename(&tmp, &self.path).inspect_err(|_| {
            let _ = std::fs::remove_file(&tmp);
        })
    }
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

    #[test]
    fn missing_is_empty_save_load_and_corrupt() {
        let dir = tmp("store");
        let store = LinksStore::new(dir.join("sub").join("links.json"));
        assert_eq!(store.load().unwrap(), Links::default());
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
        store.save(&l).unwrap();
        store.save(&l).unwrap(); // replaces
        assert_eq!(store.load().unwrap(), l);
        assert_eq!(std::fs::read_dir(store.path().parent().unwrap()).unwrap().count(), 1);
        std::fs::write(store.path(), "not json").unwrap();
        assert_eq!(store.load().unwrap_err().kind(), io::ErrorKind::InvalidData);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
