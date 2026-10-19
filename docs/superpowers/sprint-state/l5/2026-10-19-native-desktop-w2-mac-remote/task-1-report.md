# L5 Tasks 1+2 report: shellx-core crate and state store

Status: DONE (one note on the security-review step, see Concerns).

Commits (branch shellx/l5-remote):
- fe0bd50abc feat(shellx-core): workspace, K3 C entry point, JSON envelope, config.set
- b840038771 feat(shellx-core): owner-only state store (0700/0600, no symlinks, atomic writes)

## Built
- shellx-core/ own workspace (GPL-3.0-or-later, edition 2024, rust-version 1.91, staticlib+rlib, release panic=unwind, lto=thin). Deps: serde_json, libc, zeroize, getrandom 0.3; dev: tempfile. Cargo.lock committed; `shellx-core/target/` in .gitignore.
- K3 C ABI `shellx_core_call` / `shellx_core_free` (ffi.rs, header include/shellx_core.h): NULL -> invalid_params, non-UTF-8 -> invalid_json, catch_unwind -> panic, never returns NULL, process-wide OnceLock<Core>.
- Core::{new, call, call_json, config}, CoreError, envelope. Dispatch per R1: name not in KNOWN_METHODS -> unknown_method; config.set handled; other known method before config -> not_configured; after config -> unknown_method (single `match` for later arms). config.set stores config only, does not touch state_dir.
- config.set validation: https, or http only for host 127.0.0.1/localhost (rejects userinfo `@`, lookalike hosts such as 127.0.0.1.evil.com); absolute state_dir; platform macos|windows; app_version default "2.0.0".
- shellx-core-cli (SHELLX_CORE_CONFIG honoured), tests/c/smoke.c, scripts/c-smoke.sh (dedupes native libs, drops -lSystem to avoid the ld duplicate warning), scripts/check_deps.py (cargo metadata --locked, all packages incl. dev-deps; SPDX OR/AND; forbidden list; workspace member must be GPL-3.0-or-later).
- store.rs (StateStore open/write_secret/read_secret/remove) with a documented Unix implementation using directory fds + openat/renameat/unlinkat, and a non-Unix fallback (compiles clean for x86_64-pc-windows-msvc `cargo check --lib`, no warnings).

## RED / GREEN
- Task 1 RED: `cargo test -p shellx-core` -> `error[E0432]: unresolved import shellx_core::ffi` / `no Core in the root`. GREEN: tests/ffi.rs 10 passed.
- Task 2 RED: `cargo test -p shellx-core --test store` -> `error[E0432]: unresolved import shellx_core::store`. GREEN: tests/store.rs 15 passed.
- Final gate before each commit: `(cd shellx-core && cargo test -p shellx-core && scripts/c-smoke.sh && python3 scripts/check_deps.py)`: 10 + 15 passed, smoke prints `{"error":{"code":"unknown_method","message":"unknown method: nope"}}`, check_deps prints `ok`, no warnings (the first c-smoke run showed an ld duplicate -lSystem warning and a wrong strncmp length in smoke.c; both fixed before commit 1).

## Security checklist self-review (store.rs)
- O_NOFOLLOW on every final component and dir: dirs opened `O_DIRECTORY|O_NOFOLLOW` after an fstatat(AT_SYMLINK_NOFOLLOW) pre-check; files `openat(... O_NOFOLLOW)`; write also refuses an existing symlink/non-regular target (`state_file_insecure`). Tests: refuses_symlinked_root_tickets_dir_and_file (targets untouched).
- fd-based ownership/mode checks: fstat on the opened dir fds (re-checked on every operation) and on the opened file fd (regular, uid == euid, no 0o077).
- Temp names: `name.tmp.<128-bit getrandom hex>`, `O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC`, mode 0600; temp unlinked on any failure.
- fchmod 0600 after create (umask_zero_still_yields_0600); new dirs fchmod 0700 too.
- rename: renameat within the same dir fd; fsync file (sync_all) then fsync dir fd.
- Zeroizing: read buffer allocated once at st_size (no regrowth copies), capped at 1 MiB, returned as Zeroizing<Vec<u8>>.
- No secret bytes: errors carry op + path + OS error only; custom Debug prints root only (test insecure_error_messages_name_no_contents).
- Name regex `^[a-z0-9][a-z0-9._-]{0,63}$` plus optional exact `tickets/` prefix, bare `tickets` rejected; tests cover traversal, hidden, uppercase, NUL, length 64/65, other prefixes.
- Windows gap documented in the module header (no ACL/reparse/owner checks); F_FULLFSYNC note too.

## Concerns
- The per-task security review normally dispatches a reviewer subagent; I may not dispatch subagents, so this self-review stands in. The controller should arrange the independent review.
- The store keeps open directory fds for its lifetime (a deleted-and-recreated root path is not followed; operations stay on the original dir). Intentional; later tasks should re-open the store if state_dir changes (config.set re-call).
- Non-Unix store is untested at runtime (compile-checked only, msvc target).
- The brief's smoke prefix length was a miscount in my first draft only; no brief contradiction.

# Fix round 1

1. Trailing-slash root bypass: `store::root_path_ok` rejects a root whose last segment is empty, `.` or `..` (checked on the raw string, since `Path` normalizes `/.` and a trailing `/` away). `StateStore::open` applies it (`state_dir_insecure`), then opens the parent and runs `ensure_dir(parent_fd, file_name)` with O_NOFOLLOW instead of `AT_FDCWD` + full path. `config.set` applies the same check (`invalid_params`). Tests: store `refuses_symlinked_root_via_trailing_slash_or_dot` (`/`, `/.`, `//`, `/./`, `/..`, target untouched); ffi `config_rejects_bad_optional_fields...` gained `/tmp/x/`, `/tmp/x/.`, `/tmp/x/..`.
2. check_deps `ok_expr`: case-insensitive operators, all tokens must be consumed, unclosed or stray parens and dangling operators fail, `WITH` only for `LLVM-exception`. 3. Forbidden: exact for openssl/openssl-sys/native-tls; `iroh`, `iroh-*`, `aws-lc`, `aws-lc-*` by prefix. Tests: new `scripts/test_check_deps.py` (3 tests).
4. c-smoke.sh: `cargo rustc` output captured into a variable first (set -e aborts on failure, no masked pipe). Verified with a fake cargo failing `rustc`: script rc=1.
5. `StateStore::open` sweeps `<valid name>.tmp.<32 lowercase hex>` leftovers in root and tickets through the dir fd (fdopendir on a dup, `fstatat` NOFOLLOW, unlinkat only for regular files owned by euid). Test `open_sweeps_only_own_stale_temp_files` (lookalike names, a symlink, a directory and the symlink target survive). Assumes one process owns a state dir.

Command: `(cd shellx-core && cargo test -p shellx-core && python3 scripts/test_check_deps.py && scripts/c-smoke.sh && python3 scripts/check_deps.py)`.
Output: ffi 10 passed, store 17 passed, deps tests OK (3), smoke prints the unknown_method envelope, check_deps `ok`; no warnings; `cargo check --target x86_64-pc-windows-msvc --lib` clean. RED first: ffi test failed on `/tmp/x/` being accepted and the python tests failed before the rewrite.
