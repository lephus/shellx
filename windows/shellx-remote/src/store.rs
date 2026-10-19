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
//!
//! Several sessions (one per Mac) use the same state dir from their own
//! threads: every read-modify-write of the files this module owns (slot map,
//! plain identity creation, plain daemon pins) holds one process-wide lock,
//! and each write goes through a temp file whose name is unique in the
//! process, so no writer loses another's entry and the identity is created
//! once.

use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, MutexGuard};

use anyhow::{Context, anyhow};
use base64::Engine;
use cmux_remote::crypto::{StaticIdentity, public_key_fingerprint};
use serde::{Deserialize, Serialize};

const SLOTS_FILE: &str = "shellx-slots.json";

/// Held around every read-modify-write of this module's state files.
static STATE_LOCK: Mutex<()> = Mutex::new(());

/// Makes each temp file name unique within the process.
static TMP_SEQ: AtomicU64 = AtomicU64::new(0);

fn state_lock() -> MutexGuard<'static, ()> {
    STATE_LOCK.lock().unwrap_or_else(|error| error.into_inner())
}

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

/// Write `bytes` to `path` through a temporary sibling (unique name) and a
/// rename. Unix: the file is created `0600`.
fn write_private(path: &Path, bytes: &[u8]) -> anyhow::Result<()> {
    let seq = TMP_SEQ.fetch_add(1, Ordering::Relaxed);
    let tmp = path.with_extension(format!("tmp{}-{seq}", std::process::id()));
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
    let written = file.write_all(bytes).and_then(|()| file.sync_all());
    drop(file);
    let result = written.map_err(anyhow::Error::from).and_then(|()| {
        fs::rename(&tmp, path).with_context(|| format!("could not replace {}", path.display()))
    });
    if result.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    result
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
    let _guard = state_lock();
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
    // Read-only: no identity is created, no lock taken, no runtime built.
    // The slot map is written only after the daemon key was pinned, so a
    // fingerprint in it means a completed enrollment.
    read_json::<SlotMap>(&state_dir.join(SLOTS_FILE)).is_ok_and(|map| {
        map.slots
            .values()
            .any(|fingerprint| fingerprint == daemon_fingerprint)
    })
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
        // Single-flight: read-or-create under the lock, so two sessions
        // opening a fresh dir at once get the same identity.
        let _guard = state_lock();
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
        let _guard = state_lock();
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
    fn concurrent_opens_create_one_identity() {
        // Two sessions starting at once on a fresh state dir must end up
        // with the same client identity (single-flight creation).
        for round in 0..20 {
            let dir = scratch(&format!("race-{round}"));
            let barrier = std::sync::Arc::new(std::sync::Barrier::new(4));
            let threads: Vec<_> = (0..4)
                .map(|_| {
                    let (dir, barrier) = (dir.clone(), barrier.clone());
                    std::thread::spawn(move || {
                        barrier.wait();
                        PlainStore::open(&dir).unwrap().identity.public_key()
                    })
                })
                .collect();
            let keys: Vec<_> = threads.into_iter().map(|t| t.join().unwrap()).collect();
            assert!(keys.iter().all(|k| *k == keys[0]), "round {round}");
            let again = PlainStore::open(&dir).unwrap();
            assert_eq!(again.identity.public_key(), keys[0]);
            fs::remove_dir_all(&dir).unwrap();
        }
    }

    #[test]
    fn concurrent_pins_and_slots_lose_nothing() {
        let dir = scratch("race-pins");
        let store = std::sync::Arc::new(PlainStore::open(&dir).unwrap());
        let barrier = std::sync::Arc::new(std::sync::Barrier::new(8));
        let threads: Vec<_> = (0..8)
            .map(|i| {
                let (dir, store, barrier) = (dir.clone(), store.clone(), barrier.clone());
                std::thread::spawn(move || {
                    let key = StaticIdentity::generate().unwrap().public_key();
                    barrier.wait();
                    store.pin(&format!("Mac {i}"), key).unwrap();
                    remember_slot(&dir, &format!("slot-{i}"), &public_key_fingerprint(&key))
                        .unwrap();
                    key
                })
            })
            .collect();
        let keys: Vec<_> = threads.into_iter().map(|t| t.join().unwrap()).collect();
        for (i, key) in keys.iter().enumerate() {
            let fingerprint = public_key_fingerprint(key);
            assert_eq!(
                store.daemon_key(&fingerprint).unwrap(),
                Some(*key),
                "pin {i}"
            );
            assert_eq!(
                slot_fingerprint(&dir, &format!("slot-{i}")).unwrap(),
                Some(fingerprint),
                "slot {i}"
            );
        }
        // no temp file is left behind
        let names: Vec<_> = fs::read_dir(&dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        assert!(names.iter().all(|n| !n.contains("tmp")), "{names:?}");
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

    #[test]
    fn is_enrolled_has_no_side_effects() {
        let dir = scratch("readonly");
        fs::create_dir_all(&dir).unwrap();
        assert!(!is_enrolled(&dir, "x"));
        // No identity key, lock or state file appears in an existing dir.
        assert_eq!(fs::read_dir(&dir).unwrap().count(), 0);
        fs::remove_dir_all(&dir).unwrap();
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
