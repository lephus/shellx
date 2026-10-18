# Native desktop ledger

Working ledger for the ShellX native desktop project (fork of cmux). Later tasks append to it.

## Baseline environment

Recorded 2026-10-18 (Wave 0, Task 1).

### Tools

| Item | Value |
| --- | --- |
| macOS | 26.5.2 (arm64) |
| Xcode | 26.2 (build 17C52) |
| Metal toolchain | 17C7003j (installed with `xcodebuild -downloadComponent MetalToolchain`) |
| Zig | 0.16.0, official aarch64-macos tarball in `~/.local/zig-0.16.0` (PATH export added to `~/.zprofile`); fork requires `minimum_zig_version = 0.16.0`, `ghostty_zig_version_is_compatible 0.16.0 0.16.0` accepts it |
| Rust | rustc/cargo 1.95.0 (`~/.cargo/bin`); setup.sh also pulled the 1.88.0 toolchain via rustup |
| Python | 3.10.11 (system python3) |
| Go | not installed; Debug builds use a stub WireGuard engine (fine for dev) |

### Fork

- Clone: `~/Documents/myProjects/shellx-pro` from https://github.com/lephus/shellx-pro, remote `upstream` = https://github.com/manaflow-ai/cmux.git
- Commit: `d0b2cd7eeb` ci: keep unrelated deployment statuses advisory (#21478)
- Submodules: ghostty `cb1ef7091cdef0b581ee2cbd83742b653253523e`, homebrew-cmux `a5f372ecfa5ee3903af6e1faba0eda096b4f5746`, vendor/bonsplit `d67d1b114fd20edba7a19f76cc39e35bde43c2d8`

### GhosttyKit

- Source: prebuilt download (no local Zig build), fetched by `scripts/ensure-ghosttykit.sh` during `./scripts/setup.sh` and verified against the pinned sha256 in `scripts/ghosttykit-checksums.txt`.
- Cache key: `cb1ef7091cdef0b581ee2cbd83742b653253523e-crashsubdir-cmux-crash-sentry-off-noi18n-v2`
- Path: `~/.cache/cmux/ghosttykit/cb1ef7091cdef0b581ee2cbd83742b653253523e-crashsubdir-cmux-crash-sentry-off-noi18n-v2/GhosttyKit.xcframework` (symlinked into the checkout)
- Pinned sha256 of the archive: `413515af9e3739068f91bae98bc33fa1d89d4ea20b35d0fa96b317379bb17ae2`
- Zig is therefore only needed if the ghostty submodule moves to a commit with no prebuilt entry.

### Build

- `CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag shellx-w0 --build-only` succeeded (exit 0, about 35 min on a cold DerivedData). Logs: `/tmp/shellx-w0-setup.log`, `/tmp/shellx-w0-build.log`, `/tmp/cmux-reload-shellx-w0.log`.
- `--build-only` removes its temporary build artifact and leaves no launchable `cmux DEV shellx-w0.app`. Tasks that need to run the tagged app must run `./scripts/reload.sh --tag shellx-w0` without `--build-only` (this launches the app; never touch a running `com.cmuxterm.app`). Not done in this task.
- Dev web/API origin for the tag: http://localhost:3777 (not started).

### Python tests (`tests/*.py`)

- Runner: plain stdlib `unittest`; there is no pytest anywhere (0 of the test files import pytest). Tests are executed as scripts or `python3 -m unittest` (see `.github/workflows/*.yml`), and `scripts/verify-local.py` runs them as `python3 tests/test_x.py` and parses the unittest summary. `tests/test-execution.toml` maps each test file to a CI lane.
- Project test command: `python3 scripts/verify-local.py` (changed files only) or `python3 scripts/verify-local.py --all` (full static recipe). No venv is needed, so `~/.venvs/shellx-pro` was not created.

### Baseline test results (upstream state, nothing of ours applied)

- `python3 scripts/verify-local.py`: passed (1/1 affected check, feature-flags; nothing changed).
- `python3 scripts/verify-local.py --all`: **16/16 checks passed** (includes project-tests 16 tests, test-wiring-sync 18, wire-app-sources 13, ui-lab 4, ui-fuzzer 22; all 0 failures, 0 skipped).
- `./scripts/test-unit.sh test` (xcodebuild scheme `cmux-unit`): compile took about 55 min, then the run was **stopped by me at the 60 min budget**, so there is no final summary line (exit was a kill, not a test result). Before the stop: 215 test cases started, 214 passed, 0 failed; the one in flight was `AppDelegateShortcutRoutingTests testTextBoxPendingAttachmentUploadIsStrippedWhenPreservedForRemount`. Known failures: none observed. The full unit suite is far larger than 215 cases and was not completed. Log: `/tmp/shellx-w0-unit.log`. A rerun will be fast on compile (warm DerivedData) but needs a time budget for the test phase itself. The unit run launches a `cmux DEV` test host, not `com.cmuxterm.app`.

## Decisions

(none yet)

## Spike results

(none yet)
