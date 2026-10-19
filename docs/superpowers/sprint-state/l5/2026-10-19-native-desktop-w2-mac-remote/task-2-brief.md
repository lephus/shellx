### Task 2: Owner-only state store (security review)

**Files:**
- Create: `shellx-core/src/store.rs`, `shellx-core/tests/store.rs`

**Interfaces:**
- Produces: `pub struct StateStore`; `StateStore::open(root: &Path) -> Result<StateStore, CoreError>` — creates `root` and `root/tickets` with mode `0700` if missing; refuses (code `state_dir_insecure`) a root or `tickets` that is a symlink, not a directory, not owned by `geteuid()`, or has any `0o077` bit. `fn write_secret(&self, name: &str, bytes: &[u8]) -> Result<PathBuf, CoreError>`; `fn read_secret(&self, name: &str) -> Result<Option<Zeroizing<Vec<u8>>>, CoreError>`; `fn remove(&self, name: &str) -> Result<(), CoreError>`. `name` is either a bare file name or `tickets/<file>`; file part matches `^[a-z0-9][a-z0-9._-]{0,63}$` (else `invalid_params`).
- Files the core keeps (later tasks): `session.json` `{token, user_id, device_id}`, `device.key` (raw 32-byte X25519 secret), `machine.json` `{machine_id, slot}`, `tickets/*`.
- Write = open temp `name.tmp.<rand>` with `O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC`, mode `0600` (then `fchmod 0600` regardless of umask), write, `fsync`, `rename` over the target, `fsync` the dir. Read = `open(O_NOFOLLOW)` then `fstat`: owner == euid and no `0o077` bit, else `state_file_insecure`.
- Non-Unix (`cfg(not(unix))`, Windows client of L6): same API, plain create/rename under the per-user `%LOCALAPPDATA%` dir, no ACL hardening — documented in the module header as a post-sprint security item (master "after the sprint").

- [ ] **Step 1: Write the failing tests** (`#[cfg(unix)]`)

```rust
#[test] fn creates_root_0700_and_secrets_0600() {
    let d = tempdir(); let s = StateStore::open(&d.path().join("core")).unwrap();
    let p = s.write_secret("session.json", b"{}").unwrap();
    assert_eq!(mode(d.path().join("core")), 0o700); assert_eq!(mode(&p), 0o600);
    assert_eq!(mode(d.path().join("core/tickets")), 0o700);
}
#[test] fn refuses_group_readable_root() { /* chmod 0755 → open → state_dir_insecure */ }
#[test] fn refuses_symlinked_root_tickets_dir_and_file() { /* each → *_insecure, target untouched */ }
#[test] fn refuses_bad_names() { for n in ["", "../x", "a/b", "tickets/../x", "tickets/a/b", "UPPER", ".hidden"] { assert_eq!(s.write_secret(n, b"x").unwrap_err().code, "invalid_params") } }
#[test] fn write_replaces_atomically_and_leaves_no_temp() { /* write twice; content = second; dir listing has no *.tmp.* */ }
#[test] fn refuses_group_readable_secret_file() { /* chmod 0644 → read → state_file_insecure */ }
#[test] fn umask_zero_still_yields_0600() { /* serial test: libc::umask(0); write; restore */ }
#[test] fn insecure_error_messages_name_no_contents() { /* message contains the path, never file bytes */ }
```

- [ ] **Step 2: Run** `(cd shellx-core && cargo test -p shellx-core --test store)` — Expected: FAIL.
- [ ] **Step 3: Implement** `store.rs` with `libc` (`open`, `fstat`, `fchmod`, `geteuid`); check the directory with `symlink_metadata` before use and re-check through the opened fd (`fstat` on `open(dir, O_DIRECTORY|O_NOFOLLOW)`) to narrow TOCTOU.
- [ ] **Step 4: Run** the store tests and the full suite — Expected: PASS.
- [ ] **Step 5: Security review** — reviewer checklist: O_NOFOLLOW on every final component and dir; fd-based ownership/mode checks; temp names unpredictable and created with O_EXCL; `fchmod` after create; rename within the same dir; fsync file and dir; `Zeroizing` for read buffers; no secret bytes in errors or `Debug`; name regex blocks traversal; Windows gap documented. Fix findings.
- [ ] **Step 6: Commit** `git commit -m "feat(shellx-core): owner-only state store (0700/0600, no symlinks, atomic writes)"`

