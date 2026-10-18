//! Persistent client identity and enrolled daemons under a caller-owned
//! state dir.
//!
//! Unix uses `cmux-remote`'s own `ClientIdentityStore` unchanged: the state
//! dir is created `0700` through `ensure_secure_directory` (owner, mode and
//! symlink checks), files are `0600` with owner-file locks.
//!
//! Windows: those owner-only checks are Unix-only upstream (they return
//! `Unsupported`), so this crate stores the client identity in a plain JSON
//! store instead. Controller ruling for the sprint: the state dir is the
//! per-user `%LOCALAPPDATA%\ShellX\native\remote\`, whose inherited
//! user-profile ACL already excludes other users. NEEDS SECURITY REVIEW:
//! no explicit owner-only DACL, no reparse-point or link-count checks.
//!
//! Both variants keep a `shellx-slots.json` map from relay slot to daemon
//! fingerprint: every Mac shares the relay route, so the slot (from
//! `pair.poll`) selects which pinned daemon key a reconnect must expect.

use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use anyhow::{Context, anyhow};
use base64::Engine;
use cmux_remote::crypto::{StaticIdentity, public_key_fingerprint};
use serde::{Deserialize, Serialize};

const SLOTS_FILE: &str = "shellx-slots.json";

#[derive(Debug, Default, Serialize, Deserialize)]
struct SlotMap {
    version: u32,
    /// relay slot -> daemon fingerprint
    slots: BTreeMap<String, String>,
}

pub(crate) fn decode_key(encoded: &str) -> anyhow::Result<[u8; 32]> {
    base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(encoded)
        .context("daemon public key is not base64url")?
        .try_into()
        .map_err(|bytes: Vec<u8>| {
            anyhow!("daemon public key is {} bytes, expected 32", bytes.len())
        })
}

fn encode_key(key: &[u8; 32]) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(key)
}

/// Write `bytes` to `path` through a temporary sibling and a rename.
/// Unix: the file is created `0600`.
fn write_private(path: &Path, bytes: &[u8]) -> anyhow::Result<()> {
    let tmp = path.with_extension("tmp");
    let mut options = fs::OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options
        .open(&tmp)
        .with_context(|| format!("could not write {}", tmp.display()))?;
    file.write_all(bytes)?;
    file.sync_all()?;
    drop(file);
    fs::rename(&tmp, path).with_context(|| format!("could not replace {}", path.display()))?;
    Ok(())
}

fn read_json<T: for<'de> Deserialize<'de> + Default>(path: &Path) -> anyhow::Result<T> {
    match fs::read(path) {
        Ok(bytes) => serde_json::from_slice(&bytes)
            .with_context(|| format!("{} is not valid state", path.display())),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(T::default()),
        Err(error) => Err(error).with_context(|| format!("could not read {}", path.display())),
    }
}

fn slot_fingerprint(state_dir: &Path, slot: &str) -> anyhow::Result<Option<String>> {
    let map: SlotMap = read_json(&state_dir.join(SLOTS_FILE))?;
    Ok(map.slots.get(slot).cloned())
}

fn remember_slot(state_dir: &Path, slot: &str, fingerprint: &str) -> anyhow::Result<()> {
    let path = state_dir.join(SLOTS_FILE);
    let mut map: SlotMap = read_json(&path)?;
    map.version = 1;
    map.slots.insert(slot.to_string(), fingerprint.to_string());
    write_private(&path, &serde_json::to_vec_pretty(&map)?)
}

/// The client identity store used by `RemoteClient`.
pub(crate) struct Store {
    state_dir: PathBuf,
    #[cfg(unix)]
    inner: std::sync::Arc<cmux_remote::identity::ClientIdentityStore>,
    #[cfg(not(unix))]
    inner: PlainStore,
}

impl Store {
    pub(crate) fn open(state_dir: &Path) -> anyhow::Result<Self> {
        #[cfg(unix)]
        let inner = cmux_remote::identity::ClientIdentityStore::load_or_create(state_dir)
            .map_err(|error| anyhow!("client identity store: {error}"))?;
        #[cfg(not(unix))]
        let inner = PlainStore::open(state_dir)?;
        Ok(Self {
            state_dir: state_dir.to_path_buf(),
            inner,
        })
    }

    pub(crate) fn identity(&self) -> StaticIdentity {
        #[cfg(unix)]
        return self.inner.identity();
        #[cfg(not(unix))]
        return self.inner.identity.clone();
    }

    /// Pin the daemon key from an invitation and bind it to `slot`.
    pub(crate) async fn pin(
        &self,
        daemon_name: &str,
        daemon_key: [u8; 32],
        route: &str,
        slot: &str,
    ) -> anyhow::Result<()> {
        #[cfg(unix)]
        self.inner
            .pin_daemon(daemon_name.to_string(), daemon_key, vec![route.to_string()])
            .await
            .map_err(|error| anyhow!("could not pin the Mac's key: {error}"))?;
        #[cfg(not(unix))]
        {
            let _ = route;
            self.inner.pin(daemon_name, daemon_key)?;
        }
        remember_slot(&self.state_dir, slot, &public_key_fingerprint(&daemon_key))
    }

    /// The pinned daemon key for `slot`, if this client enrolled there.
    pub(crate) async fn daemon_for_slot(&self, slot: &str) -> anyhow::Result<Option<[u8; 32]>> {
        let Some(fingerprint) = slot_fingerprint(&self.state_dir, slot)? else {
            return Ok(None);
        };
        #[cfg(unix)]
        return self
            .inner
            .daemon_key(&fingerprint)
            .await
            .map_err(|error| anyhow!("client identity store: {error}"));
        #[cfg(not(unix))]
        return self.inner.daemon_key(&fingerprint);
    }
}

/// Whether `state_dir` holds a pinned daemon with this fingerprint. Never
/// creates the state dir.
pub(crate) fn is_enrolled(state_dir: &Path, daemon_fingerprint: &str) -> bool {
    if !state_dir.is_dir() {
        return false;
    }
    #[cfg(unix)]
    {
        let Ok(store) = cmux_remote::identity::ClientIdentityStore::load_or_create(state_dir)
        else {
            return false;
        };
        let Ok(runtime) = tokio::runtime::Builder::new_current_thread().build() else {
            return false;
        };
        runtime
            .block_on(store.daemon_key(daemon_fingerprint))
            .ok()
            .flatten()
            .is_some()
    }
    #[cfg(not(unix))]
    {
        PlainStore::open(state_dir)
            .and_then(|store| store.daemon_key(daemon_fingerprint))
            .ok()
            .flatten()
            .is_some()
    }
}

/// Plain JSON client store for platforms without upstream owner-only file
/// checks (Windows). Compiled everywhere so its tests run on the Mac.
/// NEEDS SECURITY REVIEW (see the module comment).
#[cfg_attr(unix, allow(dead_code))]
pub(crate) struct PlainStore {
    state_dir: PathBuf,
    identity: StaticIdentity,
}

#[derive(Default, Serialize, Deserialize)]
struct PlainIdentity {
    version: u32,
    private_key: String,
}

#[derive(Default, Serialize, Deserialize)]
struct PlainDaemons {
    version: u32,
    /// fingerprint -> (name, public key base64url)
    daemons: BTreeMap<String, PlainDaemon>,
}

#[derive(Clone, Serialize, Deserialize)]
struct PlainDaemon {
    name: String,
    public_key: String,
}

const PLAIN_IDENTITY_FILE: &str = "shellx-client-identity.json";
const PLAIN_DAEMONS_FILE: &str = "shellx-known-daemons.json";

#[cfg_attr(unix, allow(dead_code))]
impl PlainStore {
    pub(crate) fn open(state_dir: &Path) -> anyhow::Result<Self> {
        fs::create_dir_all(state_dir)
            .with_context(|| format!("could not create {}", state_dir.display()))?;
        let path = state_dir.join(PLAIN_IDENTITY_FILE);
        let persisted: PlainIdentity = read_json(&path)?;
        let identity = if persisted.private_key.is_empty() {
            let identity =
                StaticIdentity::generate().map_err(|error| anyhow!("client key: {error}"))?;
            let record = PlainIdentity {
                version: 1,
                private_key: encode_key(identity.private_key()),
            };
            write_private(&path, &serde_json::to_vec_pretty(&record)?)?;
            identity
        } else {
            StaticIdentity::from_private(decode_key(&persisted.private_key)?)
        };
        Ok(Self {
            state_dir: state_dir.to_path_buf(),
            identity,
        })
    }

    fn pin(&self, name: &str, key: [u8; 32]) -> anyhow::Result<()> {
        let path = self.state_dir.join(PLAIN_DAEMONS_FILE);
        let mut daemons: PlainDaemons = read_json(&path)?;
        daemons.version = 1;
        let fingerprint = public_key_fingerprint(&key);
        if let Some(existing) = daemons.daemons.get(&fingerprint)
            && decode_key(&existing.public_key)? != key
        {
            anyhow::bail!("known daemon fingerprint collision");
        }
        daemons.daemons.insert(
            fingerprint,
            PlainDaemon {
                name: name.to_string(),
                public_key: encode_key(&key),
            },
        );
        write_private(&path, &serde_json::to_vec_pretty(&daemons)?)
    }

    fn daemon_key(&self, fingerprint: &str) -> anyhow::Result<Option<[u8; 32]>> {
        let daemons: PlainDaemons = read_json(&self.state_dir.join(PLAIN_DAEMONS_FILE))?;
        daemons
            .daemons
            .get(fingerprint)
            .map(|daemon| decode_key(&daemon.public_key))
            .transpose()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "shellx-remote-store-{name}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn plain_store_keeps_identity_and_pins() {
        let dir = scratch("plain");
        let first = PlainStore::open(&dir).unwrap();
        let again = PlainStore::open(&dir).unwrap();
        assert_eq!(first.identity.public_key(), again.identity.public_key());
        let daemon = StaticIdentity::generate().unwrap().public_key();
        let fingerprint = public_key_fingerprint(&daemon);
        assert_eq!(first.daemon_key(&fingerprint).unwrap(), None);
        first.pin("Mac", daemon).unwrap();
        assert_eq!(again.daemon_key(&fingerprint).unwrap(), Some(daemon));
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn slot_map_selects_the_pinned_daemon() {
        let dir = scratch("slots");
        let store = Store::open(&dir).unwrap();
        let daemon = StaticIdentity::generate().unwrap().public_key();
        let fingerprint = public_key_fingerprint(&daemon);
        let runtime = tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap();
        assert!(!is_enrolled(&dir, &fingerprint));
        assert_eq!(
            runtime.block_on(store.daemon_for_slot("slot-a")).unwrap(),
            None
        );
        runtime
            .block_on(store.pin("Mac", daemon, "relay+ws://127.0.0.1:1", "slot-a"))
            .unwrap();
        assert_eq!(
            runtime.block_on(store.daemon_for_slot("slot-a")).unwrap(),
            Some(daemon)
        );
        assert_eq!(
            runtime.block_on(store.daemon_for_slot("slot-b")).unwrap(),
            None
        );
        assert!(is_enrolled(&dir, &fingerprint));
        assert!(!is_enrolled(&dir, "not-a-fingerprint"));
        drop(store);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn is_enrolled_never_creates_the_dir() {
        let dir = scratch("missing");
        assert!(!is_enrolled(&dir, "x"));
        assert!(!dir.exists());
    }

    #[cfg(unix)]
    #[test]
    fn unix_state_files_are_owner_only() {
        use std::os::unix::fs::PermissionsExt;
        let dir = scratch("modes");
        let store = Store::open(&dir).unwrap();
        let daemon = StaticIdentity::generate().unwrap().public_key();
        let runtime = tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap();
        runtime
            .block_on(store.pin("Mac", daemon, "relay+ws://127.0.0.1:1", "s"))
            .unwrap();
        let mode = |path: &Path| fs::metadata(path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode(&dir), 0o700);
        assert_eq!(mode(&dir.join(SLOTS_FILE)), 0o600);
        drop(store);
        fs::remove_dir_all(&dir).unwrap();
    }
}
