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

## Signing (W0 Task 2)

Recorded 2026-10-18. Fork commit `3bb417b7eb` on `main`: `shellx.release.entitlements`, `scripts/shellx/sign-and-notarize.sh`, `tests/test_shellx_entitlements.py` (wired into `tests/test-execution.toml` lane `linux-guard` and the `preflight` group of `ci-guards.yml`).

- Build: `CMUX_GHOSTTYKIT_NO_PREBUILT=1 scripts/shellx/sign-and-notarize.sh --build` → `build-shellx/Build/Products/Release/ShellX.app` (bundle id `pro.shellx.desktop`, display name ShellX, executable still `cmux`, arm64 only). GhosttyKit built locally with Zig (cache `~/.cache/cmux/ghosttykit-local/cb1ef709…-noi18n-v2-dirty-4a469b6a…`; "dirty" only because `ghostty/macos/GhosttyKit.xcframework.prebuilt-bak/` is an untracked backup in the submodule). Releases therefore do not depend on Manaflow's prebuilt artifacts.
- Build workarounds, all in the script with comments: `SWIFT_OPTIMIZATION_LEVEL=-Onone` (Xcode 26.2 `-O` dies in the SIL linker on `ghostty_surface_clear_selection`, declared twice: `@_silgen_name` in CmuxTerminalCore and the GhosttyKit header; **W1 must fix this before an optimized build**); `ENABLE_DEBUG_DYLIB=NO` (otherwise `-Onone` splits out `cmux.debug.dylib` + `__preview.dylib`, which the inside-out signer never signs); `CMUX_WIREGUARD_GO_REQUIRE=0` (no Go; the tunnel extension is not shipped); `PRODUCT_NAME` cannot be overridden project-wide (collides across Swift package products), so the bundle dir is renamed after the build.
- Entitlements: started from `cmux.release.entitlements`, team/app ids changed, network-extension/system-extension dropped. **Also dropped** `com.apple.application-identifier`, `com.apple.developer.team-identifier`, `keychain-access-groups`, `com.apple.developer.web-browser.public-key-credential`: without a Developer ID provisioning profile amfi refuses to spawn the app (`open` → launchd errno 163). Code that loses them: CmuxPhonePush / CmuxIrxTransport / CmuxIrohTransport keychain access groups and CmuxBrowser WebAuthn passkeys. Follow-up: if W2 device identity needs a shared keychain group, or passkeys in the browser are wanted, create a Developer ID provisioning profile for `pro.shellx.desktop` (and request the web-browser public-key-credential capability from Apple), embed it, and restore the keys.
- Signing: `scripts/sign-cmux-bundle.sh` inside-out with "Developer ID Application: Phu Le huu (W4RF3W4VTZ)" (first run needs a one-time keychain "Always Allow"). Every Mach-O in the bundle (13 files: main `cmux`, `Resources/bin` helpers `cmux`, `ghostty`, `cmux-diff-sidecar`…, Sparkle, Sentry, Iroh, `libcmux_command_palette_nucleo_ffi.dylib`, DockTile plugin, Computer Use app) has `TeamIdentifier=W4RF3W4VTZ`.
- Notarization: submission `19690875-473e-4655-94e6-9b2e45ead5db` **Accepted**; stapled; `spctl` → `accepted`, `source=Notarized Developer ID`.
- Bundle id collision: the Flutter desktop app installed at `/Applications/ShellX.app` also uses `pro.shellx.desktop`, and cmux's single-instance guard makes the native build exit when that app is running ("another instance with bundle id pro.shellx.desktop is running … exiting"). The two cannot run side by side; the native app replaces the Flutter one in place (same id, good for updates).
- Launch check: pending (needs the Flutter ShellX quit first).

### Helpers

| Helper | Signed + notarized under W4RF3W4VTZ | Works | W1 |
| --- | --- | --- | --- |
| `cmux Computer Use.app` (`com.cmuxterm.cua`) | yes | **no**: `ComputerUseHelperTrust.swift:19` pins `teamIdentifier = "7WLXT3NR37"` and the requirement includes that team, so ShellX never installs or launches it | exclude; follow-up = rebrand bundle id + team pin or drop Computer Use |
| `CmuxDockTilePlugin.plugin` | yes | pending launch check | keep if launch check passes |

## Decisions

(none yet)

## Spike results

(none yet)
