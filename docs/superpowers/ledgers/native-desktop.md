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
- Launch check: **passed** 2026-10-18 after the Flutter app was quit: `open -n ShellX.app` → process alive, RSS ~260 MB.

### Helpers

| Helper | Signed + notarized under W4RF3W4VTZ | Works | W1 |
| --- | --- | --- | --- |
| `cmux Computer Use.app` (`com.cmuxterm.cua`) | yes | **no**: `ComputerUseHelperTrust.swift:19` pins `teamIdentifier = "7WLXT3NR37"` and the requirement includes that team, so ShellX never installs or launches it | exclude; follow-up = rebrand bundle id + team pin or drop Computer Use |
| `CmuxDockTilePlugin.plugin` | yes | app launches with it | keep |

## Decisions

### D-W0-1 Remote protocol — FINAL (2026-10-19): (b) cmux-tui-remote

Desk estimate (Task 5 Step 2, read-only on fork `5348097e66`): `spikes/protocol/windows-daemon-port-estimate.md` on fork branch `shellx/w0-spikes` (`486cc55bf8`). Candidate (a)'s live spike (Step 1) has not run yet (needs two tagged dev builds; disk too full).

| Criterion (1-5, 5 = least effort/risk) | (a) mobile RPC | (b) cmux-tui remote |
| --- | --- | --- |
| Windows host effort (incl. its client) | 2 (host 30-40 d + client 10-14 d) | 4 (min 12-19 d, full 20-27 d) |
| Mac host additions | 4 (9-12 d) | 2.5 (17-25 d bridge) |
| Reuse by future iOS/Android | 2 | 4.5 (iOS already links the Rust `cmux-terminal-client` C ABI) |
| Upstream-merge risk | 2 (`Sources/Mobile` 92 commits / 30 d) | 3.5 (`cmux-remote` 22 / 30 d, mostly new files + `cfg` hooks) |
| Sum | 10 | 14.5 |

Totals: (b) minimum 36 d (Windows 15 + Mac 21, clients use `attach-surface` only), full 44.5 d (37-52); (a) 56.5 d (49-66). Recommendation **(b) cmux-tui-remote, ~70 % confidence**.

Key facts: ConPTY already works in `cmux-pty` (`lib.rs:212-240`); protocol core has no Unix code; `cmux-remote` has never compiled for Windows (`cmux-tui/Cargo.toml:55-56` Unix-only dep, unguarded `UnixStream` in `provider/dial.rs:21`); security blockers `secure_directory.rs:33-45`, `secret_file.rs:68-76` (Unsupported off Unix) and no-op `restrict_file` (`identity.rs:2136-2143`, core `platform.rs:1527`) — Windows owner-only ACLs need a security review; `__terminal-host` / `terminal-bytes-v1` is Unix-only but not needed for the minimum; the daemon can be embedded (enroll/approve in-process `daemon.rs:1090-1327`, ticket callback `provider/relay.rs:70-75`) once `remote_runtime.rs` moves from the binary crate into a library. Mac serving = bridge M-B1: embed the Rust daemon + a "virtual PTY" in cmux-tui-core fed by `MobileTerminalByteTee.swift` / `ghostty_surface_set_pty_tee_cb`.

Top risks for (b): the Mac bridge is unproven (terminal size ownership vs `CmuxTerminalSharing`, double parsing must render identically, remote-initiated terminal creation needs a Swift callback); Windows port is security-sensitive and uncompiled (Task 6 CI tells); `cmux-remote` churn (269 commits / 90 d) and Android `ghostty-vt-sys` via Zig/NDK unproven.

User ruling 2026-10-18: Step 1 (mobile-RPC spike) replaced by a spike of the (b) Mac bridge M-B1. That spike ran and D-W0-1 is final: **(b)**. Spec §8.1/§8.3/§8.5/§13/C16 amended.

#### Mac bridge spike (M-B1) — PASS

Fork branch `shellx/w0-bridge` commit `4e1ed7bc41` (worktree `~/Documents/myProjects/shellx-pro-wt-bridge`; never pushed or merged). Write-up `spikes/protocol/mac-bridge-spike.md`, harness `spikes/protocol/mac-bridge/run.sh` + `fake_app.py`, screenshots/logs in `spikes/protocol/mac-bridge/evidence/`.

- Real tagged app `cmux DEV w0-bridge`: a stock `cmux-tui` client, enrolled + approved through `cmux-relay`, attached to the focused libghostty terminal (VT snapshot, Mac grid 94x37), saw its output, and its input reached the app's zsh (`$((6*7))` → 42; Esc, vim arrows, Ctrl-C work).
- Double parse renders identically (colored prompt, red SGR, bold/256/truecolor, vim, top); only diffs: cmux's unfocused-split dimming, snapshot turns palette colors into fixed RGB. Cost: 30.7 MB through, mirror done 0.06 s after the Mac pane, daemon 5.1 CPU-s (~0.17 CPU-s/MB) → project a terminal only while a viewer is attached.
- Sizing: a smaller remote viewer joined the Mac's existing shared sizing via `v2MobileTerminalViewport` (hatch, "46x30 · Fits everyone" chip, viewer badge) with no new sizing code.
- Remote-initiated `tab create terminal` opened a real libghostty tab (`Workspace.newTerminalSurface`) that ran remote commands.
- Stubbed / not done: daemon ran as a sidecar `cmux-tui` over a Unix socket (C ABI/xcframework embed B2 not exercised; sidecar is a proven fallback); durable daemon state (`--state`) fails `workspace.create` with `mutation.indeterminate`, `--ephemeral` works (fine: the app owns persistence, else +1 d); spike projection rule only (first daemon terminal = focused Mac terminal, later ones = new tabs; no workspace/pane/title/cwd mapping); input goes through `ghostty_surface_text_input` which turns `\n` into `\r` → needs a raw PTY-write export in the ghostty fork; the `virtual_pty` Rust unit test was never compiled (disk); not run: Kitty graphics, OSC 8/52, IME preedit, iOS `terminal-bytes-v1`, WAN relay.
- Bugs found and fixed in code but not re-run live (disk guard killed the rebuild): mirror reflowed differently when the viewer was wider than the Mac pane (fix: Mac echoes its real grid after a remote resize); closing a Mac tab left the daemon terminal running (fix: close ends it).
- Hook points: Swift `Sources/TerminalOutputTeeCallback.swift:17`, `Sources/AppDelegate.swift:1695`, `Sources/Mobile/ShellXBridgeSpike.swift` (bind :333, input :407, remote resize :411, grid echo :435/:455); Rust `cmux-tui-core/src/virtual_pty.rs` (new), `surface.rs:2443/2495` (spawn seam), `:2574` (mirror doesn't answer terminal queries), `:2706` (Mac grid applied to mirror).
- Dev gotcha: processes started inside a dev app that read `~/Documents` block silently on a macOS TCC prompt (zsh startup stall, client looks hung); run binaries from `/private/tmp`. Shipped app bundles `cmux-tui`, so unaffected.

Revised estimate: M-B1 **20 d (17-23)**; Mac-host score for (b) 2.5 → 3, sum 15 vs 10. (b) MVP ≈ 35 d, full ≈ 43.5 d; (a) 56.5 d. Main open risk for (b) is now the Windows port (Task 6 CI, security review of owner-only ACLs).

## Spike results

### Relay spike (W0 Task 4) — PASS

Recorded 2026-10-18. Fork branch `shellx/w0-relay` commit `5d688467de` (`spikes/relay/tap_proxy.py`, `run.sh`, `NOTES.md` with the full write-up); built from fork `5348097e66`. Reproduce: `bash spikes/relay/run.sh` (everything under `env -i`, state in `/tmp/shxrelay.*`, secret and tickets deleted at the end).

Topology run for real: `cmux-relay` 127.0.0.1:8787 ← tap proxy 8788 ← `cmux-tui server start --relay …` daemon (register ticket) and a second `cmux-tui remote connect` client (connect ticket), enrolled and approved, marker typed in workspace `shellx-secret-ws`, cwd `/tmp/shellx-secret-dir`. The client really saw the content; 228 opaque frames (31 KB) crossed the relay.

| Grep (raw / after WebSocket unmasking) | Count |
| --- | --- |
| `SHELLX-MARKER-7f3a` | 0 / 0 |
| `shellx-secret-ws` | 0 / 0 |
| `shellx-secret-dir` | 0 / 0 |
| `hostname -s` (also used as the client device name) | 0 / 0 |
| user name, `zsh`, `ws_`/`term_` ids, `/private/tmp` | 0 / 0 |
| positive controls: `"type":"connect"`, the slot id | 0 / 3, 0 / 10 (decoder works) |

Both ends are WebSocket clients, so their frames are masked: a raw grep alone gives false zeros; the tap writes an unmasked copy. No compression negotiated; `relay+ws` = one binary message per frame.

**Plaintext visible to the relay:** HTTP upgrade (`GET /v1/relay`, `Host`, `Authorization: Bearer <ticket>`, ignored by the native relay); JSON control messages `register/registered/connect/allocated/incoming/join/ready/ping/pong/error` (`cmux-remote-protocol/src/relay.rs:97-152`) carrying only opaque slot/circuit/lane/generation values and tickets; and **a plaintext `ClientPrelude`** as the first binary frame of each circuit (also the Noise prologue, `cmux-remote/src/crypto.rs:269-279`): `{name:"cmux-remote-noise", protocol:5, auth:"invitation"|"enrolled", invitation_id, session[16B], lane, lanes, generation, connection_attempt[16B]}`. So the relay learns each circuit's traffic class, whether it is a first enrollment (and the invitation id), and a stable session id linking reconnects; no content, names or paths. Noise is `Noise_XX_25519_ChaChaPoly_BLAKE2s` (`XXpsk3` with an invitation); the device name travels in the encrypted 3rd handshake message; records = 8-byte BE nonce + ChaCha20-Poly1305 ciphertext. Side channels: timing, sizes, 3 circuits per client, peer IPs. Accepted for v1.

**Ticket format the ShellX API must mint** (register and connect only; join tickets are minted by the relay itself, TTL 30 s, `relay.rs:1337`):

- `ticket = "v2." + b64url_nopad(json(claims)) + "." + b64url_nopad(HMAC-SHA256(key, signing_payload))`
- claims `{"version":2,"issuer":"cmux-relay","permission":"register"|"connect","role":"daemon"|"client","slot":"<opaque>","circuit":null,"lane":null,"generation":null,"issued_at_unix":…,"expires_at_unix":…}`
- signing payload (HMAC covers this string, not the JSON): `"cmux-relay-ticket-v2\n{version}\n{issuer}\n{permission}\n{role}\n{slot}\n{circuit|''}\n{lane|''}\n{generation|''}\n{issued_at}\n{expires_at}"`
- key = raw UTF-8 bytes of `CMUX_RELAY_HMAC_SECRET` (≥ 32 bytes, `cmux-relay/src/config.rs:182-184, :249`); issuer must equal `CMUX_RELAY_ISSUER`
- rules: register ⇒ role daemon, circuit/lane/generation null; connect ⇒ role client, circuit null; 0 < lifetime ≤ 300 s, skew 30 s; scope strings 1–256 bytes without CR/LF; ticket ≤ 4096 bytes
- refs: claims `cmux-remote-protocol/src/relay.rs:34-67`, payload `:69-94`; issue `cmux-relay/src/ticket.rs:76-86`, verify `:136-178`, shape `:182-234`, scope `:242-260`; CLI mint `cmux-relay/src/main.rs:18-46`

**Enroll → approve as observed:** daemon `server start --relay … --relay-slot … --relay-ticket-file register.ticket` → owner `remote enroll create --session S --advertise <relay> --relay-route <relay> --relay-slot … --relay-ticket-file connect.ticket` prints `cmux://enroll/<b64url json>` = `{version:1,id,secret(32B PSK),daemon_public_key,daemon_fingerprint,daemon_name,expires_at_unix,route_hints,relay_access:[{route,slot,ticket}],approval_required:true}` (`identity.rs:65-78`; without `--advertise` the invite carries the same-host `unix://` route and the client bypasses the relay) → client `remote connect <relay> --invite-file … --device-name … --headless` (XXpsk3 through the relay, then waits) → owner `remote enroll pending --json` / `remote enroll approve <invitation_id>` → client opens control + tunnel lanes as `auth:"enrolled"`; normal `cmux-tui --socket <local>` commands then run on the daemon through the relay.

**Spec implication (§8.5):** the invitation URI contains the PSK. If it ever transits the ShellX server in clear, the server could claim the invitation first and only on-site approval would stop it. So: the approval screen must show the device fingerprint (not just the name), and the PSK must travel out of band (QR code or a URL `#fragment` the server never receives). Carry into W2.

### Windows build (W0 Task 6) — PASS

Recorded 2026-10-19. Workflow `.github/workflows/shellx-windows-spike.yml` on fork branch `shellx/w0-spikes`. First run `39142103019`: `-gnu` green, `-msvc` test compile failed (`KeyInput { key: u32::MAX }`, bindgen makes `GhosttyKey` `i32` under MSVC). Fix `03e475b590` (`u32::MAX as _`). Run `39146962148`: **both `x86_64-pc-windows-msvc` and `-gnu` green**: libghostty-vt build (Zig 0.16.0), `cmux-tui-core` platform tests, `cmux-tui.exe`, long-path tests, process-exit / ConPTY resize smokes, remote-probe check. Artifacts `cmux-tui-x86_64-pc-windows-msvc` (9.88 MB), `cmux-tui-x86_64-pc-windows-gnu` (9.91 MB). §13 fallback (`alacritty_terminal`) not needed. Note: this proves the core builds and ConPTY works; `cmux-remote` on Windows is still uncompiled (see D-W0-1).

## Handoff (2026-10-18 evening)

State for the next session:
- Done: Task 1, Task 2 (incl. launch), Task 3 code (fork main `5348097e66`), Task 4 PASS, Task 5 desk estimate, Task 6 workflow pushed (`shellx/w0-spikes` on lephus/shellx-pro, pushed over SSH alias `phule9225.github.com:lephus/shellx-pro.git`; the gh token lacks `workflow` scope).
- Task 6 CI run `39142103019`: `-gnu` all green (libghostty-vt, platform tests, cmux-tui.exe, ConPTY smokes). `-msvc`: libghostty-vt builds; platform tests fail to compile at `cmux-tui-core/src/server.rs:24934` (`KeyInput { key: u32::MAX, .. }`, bindgen gives `i32` on MSVC). Next: patch to `u32::MAX as _` on the spike branch, ask the user before re-pushing, then record artifacts.
- Task 3 Step 5: `reload.sh --tag perf-base --release` needs `CMUX_WIREGUARD_GO_REQUIRE=0` (no Go); a rebuild was running when the session ended — check `/tmp/cmux-reload-perf-base.log`. Watch for the Xcode 26.2 `-O` SIL linker crash (see Signing). Then run `scripts/shellx/perf/perf_mac.py` per its README (`--commit d0b2cd7e`, `--cli <app>/Contents/Resources/bin/cmux`), with `scratchpad/perf-quiet.lock` style coordination if another build runs; Typometer by the user.
- Task 5: user ruled (2026-10-18) to replace Step 1 (mobile-RPC spike) with a ~2-day spike of the (b) Mac bridge M-B1. A spike was started in worktree `~/Documents/myProjects/shellx-pro-wt-bridge` (branch `shellx/w0-bridge`, never push/merge); if it has no `spikes/protocol/mac-bridge-spike.md` commit, restart it. Then finalize D-W0-1 and amend spec §8.1/§8.3/C16.
- Remaining after that: Task 7 (Windows UI toolkit; needs a real Windows 11 PC from the user), Task 8 close-out.
- Disk is tight (~12 GB free with perf-base DerivedData + bridge worktree).

## License question to Manaflow (draft, not sent)

Drafted 2026-10-18 (W0 Task 8 Step 2). Sending it is the user's call.

Facts behind it (fork `5348097e66`): root `LICENSE` makes everything GPL-3.0-or-later "except where a file or accompanying notice states otherwise", and puts only `web/`, `workers/*`, `services/iroh-relay-minter/` and `cmux-tui/relays/cloudflare-do/` under BUSL-1.1. `cmux-tui/Cargo.toml:60` sets the workspace `license = "MIT"`, inherited by every crate (`cmux-pty`, `cmux-remote`, `cmux-relay`, `cmux-terminal-client`, …). ShellX would self-host `cmux-tui/crates/cmux-relay` (not the BUSL `cloudflare-do` relay).

> To: founders@cmux.com
> Subject: License of cmux-tui crates (MIT vs GPL) for a downstream fork
>
> Hi Manaflow team,
>
> I'm building ShellX, a GPL-3.0 fork of cmux (github.com/lephus/shellx-pro) that adds a Windows desktop app and a phone companion. Before we ship, I'd like to confirm the license of the Rust code under `cmux-tui/`.
>
> The root LICENSE puts the project under GPL-3.0-or-later except where a file or notice says otherwise, while `cmux-tui/Cargo.toml` declares `license = "MIT"` for the whole workspace (cmux-pty, cmux-remote, cmux-relay, cmux-terminal-client and the rest).
>
> 1. Is the `cmux-tui/` workspace (including `crates/cmux-relay`) licensed under MIT, or does the root GPL apply and the Cargo field is just metadata?
> 2. If it is MIT, is it fine for us to self-host `cmux-relay` from that crate in production? We don't plan to use anything under the BUSL directories (`cmux-tui/relays/cloudflare-do/`, `web/`, `workers/`).
>
> ShellX itself will stay GPL-3.0 and credit cmux in the app and README either way. Thanks for building cmux.
>
> Best,
> Phu Le
