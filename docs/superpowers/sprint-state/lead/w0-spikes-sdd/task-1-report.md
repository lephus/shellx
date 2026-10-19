# Task 1 report: Fork workspace and first build

Status: DONE_WITH_CONCERNS

Steps: cloned lephus/shellx-pro recursively to ~/Documents/myProjects/shellx-pro (HEAD d0b2cd7eeb, 3 submodules checked out), added upstream remote; installed Zig 0.16.0 to ~/.local/zig-0.16.0 (PATH in ~/.zprofile), version script accepts it; Metal toolchain downloaded; setup.sh OK (prebuilt GhosttyKit, key cb1ef7091cdef0b581ee2cbd83742b653253523e-crashsubdir-cmux-crash-sentry-off-noi18n-v2, pinned sha256 413515af...7ae2); tagged build-only reload.sh succeeded (exit 0); verify-local.py and --all passed (16/16); test-unit.sh stopped at 60 min (215 started, 214 passed, 0 failed, no summary).

Test runner: stdlib unittest, no pytest, so no venv created.

Commit (shellx repo, local only): a23fac61 docs(ledger): native desktop W0 baseline environment
File: docs/superpowers/ledgers/native-desktop.md. Nothing pushed.

Concerns:
- --build-only deletes its artifact, so no `cmux DEV shellx-w0.app` exists; later tasks must run reload.sh --tag shellx-w0 without --build-only.
- Full unit suite not completed (compile ~55 min cold).
- Logs in /tmp/shellx-w0-*.log.
