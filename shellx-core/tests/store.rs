#![cfg(unix)]
use shellx_core::store::StateStore;
use std::fs;
use std::os::unix::fs::{MetadataExt, PermissionsExt, symlink};
use std::path::Path;
use std::sync::{Mutex, MutexGuard};
use tempfile::{TempDir, tempdir};

// umask is process-wide; serialize every test so the umask test cannot skew others.
static LOCK: Mutex<()> = Mutex::new(());
fn serial() -> MutexGuard<'static, ()> {
    LOCK.lock().unwrap_or_else(|p| p.into_inner())
}

fn mode(p: impl AsRef<Path>) -> u32 {
    fs::metadata(p).unwrap().mode() & 0o7777
}

fn fresh() -> (TempDir, StateStore) {
    let d = tempdir().unwrap();
    let s = StateStore::open(&d.path().join("core")).unwrap();
    (d, s)
}

#[test]
fn creates_root_0700_and_secrets_0600() {
    let _g = serial();
    let d = tempdir().unwrap();
    let s = StateStore::open(&d.path().join("core")).unwrap();
    let p = s.write_secret("session.json", b"{}").unwrap();
    assert_eq!(mode(d.path().join("core")), 0o700);
    assert_eq!(mode(&p), 0o600);
    assert_eq!(mode(d.path().join("core/tickets")), 0o700);
    assert_eq!(p, d.path().join("core/session.json"));
}

#[test]
fn reopen_existing_store_works() {
    let _g = serial();
    let (d, s) = fresh();
    s.write_secret("device.key", &[7u8; 32]).unwrap();
    let s2 = StateStore::open(&d.path().join("core")).unwrap();
    assert_eq!(&s2.read_secret("device.key").unwrap().unwrap()[..], &[7u8; 32]);
}

#[test]
fn refuses_group_readable_root() {
    let _g = serial();
    let (d, _s) = fresh();
    fs::set_permissions(d.path().join("core"), fs::Permissions::from_mode(0o755)).unwrap();
    assert_eq!(StateStore::open(&d.path().join("core")).unwrap_err().code, "state_dir_insecure");
}

#[test]
fn refuses_group_readable_tickets_dir() {
    let _g = serial();
    let (d, _s) = fresh();
    fs::set_permissions(d.path().join("core/tickets"), fs::Permissions::from_mode(0o750)).unwrap();
    assert_eq!(StateStore::open(&d.path().join("core")).unwrap_err().code, "state_dir_insecure");
}

#[test]
fn refuses_root_that_is_a_file() {
    let _g = serial();
    let d = tempdir().unwrap();
    fs::write(d.path().join("core"), b"x").unwrap();
    assert_eq!(StateStore::open(&d.path().join("core")).unwrap_err().code, "state_dir_insecure");
}

#[test]
fn refuses_symlinked_root_tickets_dir_and_file() {
    let _g = serial();
    // root symlink
    let d = tempdir().unwrap();
    let real = d.path().join("real");
    fs::create_dir(&real).unwrap();
    fs::set_permissions(&real, fs::Permissions::from_mode(0o700)).unwrap();
    symlink(&real, d.path().join("core")).unwrap();
    assert_eq!(StateStore::open(&d.path().join("core")).unwrap_err().code, "state_dir_insecure");
    assert_eq!(fs::read_dir(&real).unwrap().count(), 0, "target untouched");

    // tickets symlink
    let d = tempdir().unwrap();
    let root = d.path().join("core");
    fs::create_dir(&root).unwrap();
    fs::set_permissions(&root, fs::Permissions::from_mode(0o700)).unwrap();
    let elsewhere = d.path().join("elsewhere");
    fs::create_dir(&elsewhere).unwrap();
    fs::set_permissions(&elsewhere, fs::Permissions::from_mode(0o700)).unwrap();
    symlink(&elsewhere, root.join("tickets")).unwrap();
    assert_eq!(StateStore::open(&root).unwrap_err().code, "state_dir_insecure");
    assert_eq!(fs::read_dir(&elsewhere).unwrap().count(), 0);

    // file symlink: read and write both refuse, target untouched
    let (d, s) = fresh();
    let target = d.path().join("target.txt");
    fs::write(&target, b"orig").unwrap();
    fs::set_permissions(&target, fs::Permissions::from_mode(0o600)).unwrap();
    symlink(&target, d.path().join("core/session.json")).unwrap();
    assert_eq!(s.read_secret("session.json").unwrap_err().code, "state_file_insecure");
    assert_eq!(s.write_secret("session.json", b"new").unwrap_err().code, "state_file_insecure");
    assert_eq!(fs::read(&target).unwrap(), b"orig");
}

#[test]
fn refuses_bad_names() {
    let _g = serial();
    let (_d, s) = fresh();
    for n in [
        "", "../x", "a/b", "tickets/../x", "tickets/a/b", "UPPER", ".hidden", "tickets", "tickets/", "/abs",
        "a b", "-lead", "x\0y", "tickets/.x", &"a".repeat(65), "other/x",
    ] {
        assert_eq!(s.write_secret(n, b"x").unwrap_err().code, "invalid_params", "{n:?}");
        assert_eq!(s.read_secret(n).unwrap_err().code, "invalid_params", "{n:?}");
        assert_eq!(s.remove(n).unwrap_err().code, "invalid_params", "{n:?}");
    }
    assert!(s.write_secret(&"a".repeat(64), b"x").is_ok());
}

#[test]
fn tickets_subdir_round_trip_and_remove() {
    let _g = serial();
    let (d, s) = fresh();
    let p = s.write_secret("tickets/register.ticket", b"tk").unwrap();
    assert_eq!(p, d.path().join("core/tickets/register.ticket"));
    assert_eq!(mode(&p), 0o600);
    assert_eq!(&s.read_secret("tickets/register.ticket").unwrap().unwrap()[..], b"tk");
    s.remove("tickets/register.ticket").unwrap();
    assert!(s.read_secret("tickets/register.ticket").unwrap().is_none());
    s.remove("tickets/register.ticket").unwrap(); // idempotent
}

#[test]
fn write_replaces_atomically_and_leaves_no_temp() {
    let _g = serial();
    let (d, s) = fresh();
    s.write_secret("session.json", b"first").unwrap();
    s.write_secret("session.json", b"second").unwrap();
    assert_eq!(&s.read_secret("session.json").unwrap().unwrap()[..], b"second");
    for e in fs::read_dir(d.path().join("core")).unwrap() {
        let n = e.unwrap().file_name().into_string().unwrap();
        assert!(!n.contains(".tmp."), "{n}");
    }
}

#[test]
fn read_missing_is_none() {
    let _g = serial();
    let (_d, s) = fresh();
    assert!(s.read_secret("session.json").unwrap().is_none());
}

#[test]
fn refuses_group_readable_secret_file() {
    let _g = serial();
    let (d, s) = fresh();
    let p = s.write_secret("session.json", b"TOPSECRET").unwrap();
    fs::set_permissions(&p, fs::Permissions::from_mode(0o644)).unwrap();
    assert_eq!(s.read_secret("session.json").unwrap_err().code, "state_file_insecure");
    drop(d);
}

#[test]
fn refuses_non_regular_file() {
    let _g = serial();
    let (d, s) = fresh();
    fs::create_dir(d.path().join("core/session.json")).unwrap();
    assert_eq!(s.read_secret("session.json").unwrap_err().code, "state_file_insecure");
}

#[test]
fn umask_zero_still_yields_0600() {
    let _g = serial();
    let old = unsafe { libc::umask(0) };
    let d = tempdir().unwrap();
    let r = StateStore::open(&d.path().join("core")).and_then(|s| s.write_secret("device.key", b"k").map(|p| (s, p)));
    unsafe { libc::umask(old) };
    let (_s, p) = r.unwrap();
    assert_eq!(mode(&p), 0o600);
    assert_eq!(mode(d.path().join("core")), 0o700);
    assert_eq!(mode(d.path().join("core/tickets")), 0o700);
}

#[test]
fn insecure_error_messages_name_no_contents() {
    let _g = serial();
    let (d, s) = fresh();
    let p = s.write_secret("session.json", b"TOPSECRET-BYTES").unwrap();
    fs::set_permissions(&p, fs::Permissions::from_mode(0o644)).unwrap();
    let e = s.read_secret("session.json").unwrap_err();
    assert!(e.message.contains("session.json"), "{}", e.message);
    assert!(!e.message.contains("TOPSECRET") && !format!("{e:?}").contains("TOPSECRET"));
    assert!(!format!("{s:?}").contains("TOPSECRET"));
    drop(d);
}

#[test]
fn secret_read_buffer_is_zeroizing() {
    let _g = serial();
    let (_d, s) = fresh();
    s.write_secret("device.key", &[1u8; 32]).unwrap();
    let z: zeroize::Zeroizing<Vec<u8>> = s.read_secret("device.key").unwrap().unwrap();
    assert_eq!(z.len(), 32);
}
