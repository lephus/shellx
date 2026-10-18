# ShellX native desktop — Wave 0: spikes and baselines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Settle the five unknowns that block the later waves: the fork builds and signs as ShellX; we have cmux's own performance numbers to compare against; `cmux-relay` really hides terminal content; Mac and Windows get one shared remote protocol; and a Windows terminal can be built natively with Vietnamese input working.

**Architecture:** Spike work lives in the fork `lephus/shellx-pro` (local clone `~/Documents/myProjects/shellx-pro`). Code that later waves reuse (perf harness, signing entitlements) lands on the fork's `main`. Throwaway spike code stays on branch `shellx/w0-spikes` and is never merged. Every result, number and decision goes into the ledger `docs/superpowers/ledgers/native-desktop.md` in the `shellx` repo. The spec gets amended where a spike decides one of its open choices (C16 protocol, Windows UI toolkit).

**Tech Stack:** Xcode 26.2 (installed), Zig 0.16.0 (to install), Rust 1.95 (installed; cmux-tui needs ≥ 1.91), Swift 6.0 language mode for app-linked code, Python 3 for harness scripts, GitHub Actions `windows-latest` for Windows builds.

**Spec:** `docs/superpowers/specs/2026-10-18-shellx-native-desktop-design.md` — §2.2 (criteria 1–2), §8.3, §8.5, §13 (every row is a task here), C10, C16.

## Global Constraints

- Upstream base: `lephus/shellx-pro` `main` at `d0b2cd7e` (= `manaflow-ai/cmux`). Add remote `upstream` = `https://github.com/manaflow-ai/cmux.git`.
- ShellX identity: bundle id `pro.shellx.desktop` (Release), `pro.shellx.desktop.debug` (Debug); Apple Team ID `W4RF3W4VTZ`; signing identity "Developer ID Application: Phu Le huu (W4RF3W4VTZ)".
- Never ask for a certificate, password, API key or HMAC secret in chat. When a step needs one, the user runs it with `! <command>`.
- Never `git push` and never deploy to the VPS without asking the user first (each time). Pushing the fork triggers its CI.
- cmux house rules that still apply: never use bare `xcodebuild` or an untagged dev app — build through `./scripts/reload.sh --tag <tag>`; never touch a running `com.cmuxterm.app`.
- Downloaded third-party code (anything not in `shellx` or `shellx-pro`) goes in its own empty directory and is not executed except as the build input the task names.
- Perf threshold (C10): ShellX may be at most 10 % worse than the baseline on each metric.
- Relay principle (spec §8.5): the relay must not be able to read terminal content; a new device needs on-site approval by the target machine.

## Review Focus

1. **Metadata leaks through the relay.** Even with ciphertext payloads, `RelayControl` messages or ticket claims could carry workspace names, cwd or hostnames in clear. Task 4 greps relay-visible bytes for the hostname and workspace name too, not only the typed marker.
2. **Warm-start numbers.** A perf run that leaves the app or its helpers alive, or reuses a filled page cache, reports a cold start that is really warm. Task 3's harness kills every process of the bundle and checks none survives before each cold-start sample.
3. **Nested binaries left unsigned.** Notarization rejects the bundle if the CLI, Dock tile plugin, `cmux-tui`, `ghostty` helpers or any `.dylib` is unsigned or signed with the wrong team. Task 2 verifies every Mach-O inside the bundle, not just the app.
4. **Vietnamese IME preedit.** Telex/VNI composition shows a preedit (underlined) span before commit; Unikey/EVKey work by key injection, the Windows built-in keyboard by TSF. Task 7 tests all three, plus a tone mark typed after a vowel cluster (`tieengs` → `tiếng`) and backspace inside a composition.
5. **Prebuilt GhosttyKit.** `scripts/setup.sh` may download a prebuilt `GhosttyKit.xcframework` from manaflow-ai's GitHub releases. Task 1 records which path was used and its checksum; Task 2 must succeed with a locally built GhosttyKit (`CMUX_GHOSTTYKIT_NO_PREBUILT=1`) so releases never depend on Manaflow artifacts.

---

### Task 1: Fork workspace and first build

**Files:**
- Create: `docs/superpowers/ledgers/native-desktop.md` (shellx repo)
- Clone: `~/Documents/myProjects/shellx-pro` (fork)

**Interfaces:**
- Produces: a working clone with submodules, remote `upstream`, Zig 0.16.0 on `PATH`, a built tagged dev app `ShellX`-unbranded (`cmux DEV shellx-w0.app`), and the ledger with a "Baseline environment" section that later tasks append to.

- [ ] **Step 1: Clone with submodules and add upstream**

```bash
cd ~/Documents/myProjects
git clone --recursive https://github.com/lephus/shellx-pro.git
cd shellx-pro && git remote add upstream https://github.com/manaflow-ai/cmux.git
git log --oneline -1   # expect d0b2cd7e…
git submodule status   # expect ghostty, homebrew-cmux, vendor/bonsplit all checked out
```

- [ ] **Step 2: Install Zig 0.16.0 and the Metal toolchain**

Install the official Zig 0.16.0 tarball for `aarch64-macos` from ziglang.org into `~/.local/zig-0.16.0` and put it on `PATH` (Homebrew may ship another minor). Then:

```bash
zig version                                   # expect 0.16.0
./scripts/ghostty-zig-version.sh              # must accept the installed Zig
xcodebuild -downloadComponent MetalToolchain  # per CONTRIBUTING.md
```

- [ ] **Step 3: Run setup and a tagged build**

```bash
./scripts/setup.sh 2>&1 | tee /tmp/shellx-w0-setup.log
CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag shellx-w0 --build-only
```

Expected: build succeeds. Record in the log whether `ensure-ghosttykit.sh` used the prebuilt download or a local Zig build, and the GhosttyKit cache key.

- [ ] **Step 4: Run the baseline test lanes**

```bash
python3 scripts/verify-local.py
./scripts/test-unit.sh test 2>&1 | tail -20
```

Expected: record pass/fail counts as-is (upstream state). Failures here are baseline, not ours; list them by name in the ledger so later waves don't chase them.

- [ ] **Step 5: Write the ledger**

Create `docs/superpowers/ledgers/native-desktop.md` with sections `## Baseline environment` (Xcode, Zig, Rust, macOS versions; fork commit; GhosttyKit source + checksum; baseline test counts and known failures), `## Decisions`, `## Spike results`. Commit in the shellx repo:

```bash
git add docs/superpowers/ledgers/native-desktop.md
git commit -m "docs(ledger): native desktop W0 baseline environment"
```

### Task 2: Signing and notarization as ShellX

**Files (fork, branch `main`):**
- Create: `shellx.release.entitlements`
- Create: `scripts/shellx/sign-and-notarize.sh`
- Test: `tests/test_shellx_entitlements.py`

**Interfaces:**
- Consumes: Task 1 clone.
- Produces: `shellx.release.entitlements` (used by W1 and the W3 release pipeline) and `scripts/shellx/sign-and-notarize.sh <app-path>` which signs inside-out with the Developer ID identity, notarizes with the keychain profile `shellx-notary`, staples, and exits non-zero on any failure. Ledger section "Signing" lists every nested Mach-O and its team after signing, and the helper decision below.

- [ ] **Step 1: Write the failing entitlements test**

`tests/test_shellx_entitlements.py` (stdlib `plistlib`, run with `python3 -m pytest`):

```python
def test_release_entitlements_are_shellx_only():
    ent = plistlib.load(open("shellx.release.entitlements", "rb"))
    groups = ent.get("com.apple.security.application-groups", [])
    assert groups == ["W4RF3W4VTZ.pro.shellx.desktop"]
    assert all("7WLXT3NR37" not in str(v) for v in ent.values())
    assert "com.apple.developer.networking.networkextension" not in ent
    assert "com.apple.developer.system-extension.install" not in ent
```

- [ ] **Step 2: Run it to see it fail**

Run: `python3 -m pytest tests/test_shellx_entitlements.py -q` — Expected: FAIL (file missing).

- [ ] **Step 3: Create `shellx.release.entitlements`**

Start from `cmux.release.entitlements`; replace team/app ids with `W4RF3W4VTZ` / `pro.shellx.desktop`; drop the network-extension and system-extension entitlements (the tunnel extension is Cloud-only, spec §9). Keep everything libghostty, the browser and Apple Events need.

- [ ] **Step 4: Run the test** — Expected: PASS.

- [ ] **Step 5: Build Release with a local GhosttyKit and ShellX ids**

Build a Release `.app` through `reload.sh --release` with `CMUX_GHOSTTYKIT_NO_PREBUILT=1`, overriding `PRODUCT_BUNDLE_IDENTIFIER=pro.shellx.desktop`, `PRODUCT_NAME=ShellX`, and excluding the `cmuxTunnelExtension` embed. If `reload.sh` cannot take these overrides, write the equivalent `xcodebuild` call into `scripts/shellx/sign-and-notarize.sh --build` (this is the one sanctioned non-tagged build; it uses ShellX ids so it cannot collide with cmux).

- [ ] **Step 6: Write `scripts/shellx/sign-and-notarize.sh` and sign**

Reuse `scripts/sign-cmux-bundle.sh` for the inside-out order. Notarize with `xcrun notarytool submit --keychain-profile shellx-notary --wait`, then `xcrun stapler staple`. The user creates the profile once themselves:

```
! xcrun notarytool store-credentials shellx-notary --apple-id phulealali@gmail.com --team-id W4RF3W4VTZ
```

- [ ] **Step 7: Verify every nested binary and Gatekeeper**

```bash
find build/ShellX.app -type f -perm -111 -exec sh -c 'file "$1" | grep -q Mach-O && codesign -dv "$1" 2>&1 | grep TeamIdentifier' _ {} \;
codesign --verify --deep --strict --verbose=2 build/ShellX.app
spctl -a -vv -t exec build/ShellX.app
```

Expected: every `TeamIdentifier=W4RF3W4VTZ`; `spctl` prints `accepted` and `source=Notarized Developer ID`. Launch it once: the app opens a terminal.

- [ ] **Step 8: Decide the helpers and record**

For `cmux Computer Use.app` (built from manaflow-ai/cmux-cua, bundle `com.cmuxterm.cua`, team-pinned trust in `ComputerUseHelperTrust.swift:19`) and `CmuxDockTilePlugin`: record in the ledger whether each was signed and works under `W4RF3W4VTZ`. Rule: keep a helper in W1 only if it signed, notarized and launched here; otherwise W1 excludes it and the ledger lists it as a follow-up.

- [ ] **Step 9: Commit (fork) and update the ledger (shellx)**

```bash
git add shellx.release.entitlements scripts/shellx/sign-and-notarize.sh tests/test_shellx_entitlements.py
git commit -m "build(shellx): release entitlements and sign/notarize script for W4RF3W4VTZ"
```

### Task 3: Perf harness and cmux baseline (macOS)

**Files (fork, branch `main`):**
- Create: `scripts/shellx/perf/perf_mac.py`
- Create: `scripts/shellx/perf/README.md`
- Test: `tests/test_shellx_perf_harness.py`

**Interfaces:**
- Produces: `python3 scripts/shellx/perf/perf_mac.py --app <path.app> --cli <bundled-cli-path> --runs 5 --out <file.json>` writing `{"app": str, "commit": str, "metrics": {"cold_start_ms": float, "cat_100mb_ms": float, "idle_rss_mb_4panes": float, "idle_cpu_pct": float, "hitch_ms_per_s": float, "max_hitch_ms": float, "keystroke_ms": float | null}, "samples": {...}}` (medians; `compare` skips a metric that is null on either side); and `python3 scripts/shellx/perf/perf_mac.py compare <baseline.json> <candidate.json> --max-regression 0.10` exiting 1 if any metric is worse by more than 10 %. Keystroke latency is measured manually with Typometer and entered with `--keystroke-ms <float>`. W1's final task runs `compare`.

- [ ] **Step 1: Write the failing test for `compare`**

```python
def test_compare_flags_regression_over_ten_percent(tmp_path):
    base = {"metrics": {"cold_start_ms": 1000, "cat_100mb_ms": 500, "idle_rss_mb_4panes": 200, "idle_cpu_pct": 1.0, "keystroke_ms": 10}}
    cand = dict(metrics=dict(base["metrics"], cold_start_ms=1101))
    assert compare(base, cand, max_regression=0.10) == ["cold_start_ms"]

def test_compare_passes_at_exactly_ten_percent():
    base = {"metrics": {"cold_start_ms": 1000}}
    assert compare(base, {"metrics": {"cold_start_ms": 1100}}, 0.10) == []
```

- [ ] **Step 2: Run** `python3 -m pytest tests/test_shellx_perf_harness.py -q` — Expected: FAIL (module missing).

- [ ] **Step 3: Implement `compare(base: dict, cand: dict, max_regression: float) -> list[str]` and the measuring commands in `perf_mac.py`**

Methods (record them in the README so W1 reruns exactly the same):
- cold start: kill every process whose executable is inside the bundle and assert none remains; start a clock; `open -n <app>` with a `ZDOTDIR` whose `.zshrc` writes a high-resolution timestamp (`perl -MTime::HiRes=time -e 'printf "%.6f", time'`) to a marker file on the first prompt; cold_start = marker − clock.
- `cat` 100 MB: create a 100 MB text file once; send `{ time cat FILE >/dev/null; } 2> OUT; echo done > MARK` to the focused terminal with the bundled CLI's send-text command; parse `real`.
- idle RSS with 4 panes: create 3 splits with the CLI, wait 60 s, sum RSS of all processes inside the bundle (`ps -o rss=`).
- idle CPU: sample `ps -o %cpu=` for the same processes every 5 s for 60 s; mean.
- hitches (subcommand `perf_mac.py hitches --app … --out …`): record `xcrun xctrace record --template "Animation Hitches"` for 30 s while the CLI prints `seq 1 2000000` in the focused terminal and toggles the sidebar 20 times; report total hitch time per second and the longest hitch. Stored as `metrics.hitch_ms_per_s` and `metrics.max_hitch_ms` and included in `compare`.

- [ ] **Step 4: Run the tests** — Expected: PASS.

- [ ] **Step 5: Measure the cmux baseline**

Build upstream unchanged (`d0b2cd7e`) as a tagged release build: `./scripts/reload.sh --tag perf-base --release --build-only`. Run `perf_mac.py --runs 5 --out /tmp/perf-cmux-d0b2cd7e.json`. Ask the user to run Typometer once (200 samples, default font, empty shell) and add `--keystroke-ms`. Copy the JSON into the ledger under "Spike results → macOS baseline".

- [ ] **Step 6: Commit (fork)**

```bash
git add scripts/shellx/perf tests/test_shellx_perf_harness.py
git commit -m "test(shellx): macOS perf harness with 10% regression gate"
```

### Task 4: `cmux-relay` spike — content stays opaque

**Files (fork, branch `shellx/w0-spikes`):**
- Create: `spikes/relay/tap_proxy.py` (TCP proxy that writes every byte it forwards to a capture file)
- Create: `spikes/relay/run.sh`

**Interfaces:**
- Produces: ledger section "Relay spike" with: pass/fail of the opaque-content check, the exact ticket format (claims JSON fields, encoding, HMAC input) that the W2 ShellX API must mint, the enroll → approve flow as observed, and every plaintext field seen in control messages.

- [ ] **Step 1: Build relay and TUI from the fork**

```bash
cd cmux-tui && cargo build -p cmux-relay -p cmux-tui 2>&1 | tail -3
```

Expected: both binaries build (needs Zig on `PATH` for `ghostty-vt-sys`).

- [ ] **Step 2: Wire the topology in `run.sh`**

Relay on `127.0.0.1:8787` with a random 32-byte `CMUX_RELAY_HMAC_SECRET` generated into a temp file (never printed); `tap_proxy.py` listening on `127.0.0.1:8788` forwarding to 8787 and capturing to `/tmp/relay-capture.bin`; a `cmux-tui` remote daemon registering through `relay+ws://127.0.0.1:8788` with a `register` ticket; a second `cmux-tui` client connecting with a `connect` ticket after enrolling via `remote enroll create` and approving on the daemon side.

- [ ] **Step 3: Type a marker and check the capture**

In the client, open the daemon's terminal, run `echo SHELLX-MARKER-7f3a` in a workspace named `shellx-secret-ws` with cwd `/tmp/shellx-secret-dir`. Then:

```bash
grep -a -c 'SHELLX-MARKER-7f3a' /tmp/relay-capture.bin   # expect 0
grep -a -c 'shellx-secret-ws'  /tmp/relay-capture.bin    # expect 0
grep -a -c 'shellx-secret-dir' /tmp/relay-capture.bin    # expect 0
grep -a -c "$(hostname -s)"    /tmp/relay-capture.bin    # record; hostname in clear is a finding
```

Expected: the first three are 0. Any non-zero is a FAIL to record with the message type that carried it.

- [ ] **Step 4: Record and commit the spike branch**

Write the ledger section. Commit spike files on `shellx/w0-spikes`.

### Task 5: Choose the shared remote protocol (C16)

**Files (fork, branch `shellx/w0-spikes`):**
- Create: `spikes/protocol/mobile-rpc-over-relay/` (Swift spike inside the app target behind a debug-only flag)
- Create: `spikes/protocol/windows-daemon-port-estimate.md`

**Interfaces:**
- Consumes: Task 4's working relay and ticket notes.
- Produces: ledger "Decisions → D-W0-1 Remote protocol" naming exactly one of `mobile-rpc` or `cmux-tui-remote`, scored on the four criteria from spec §13; and the matching edit to spec §8.1/§8.3/C16 replacing "chọn ở bước thử §13" with the choice.

- [ ] **Step 1: Candidate (a) — mobile RPC over the relay, two Macs**

Implement a `CmxByteTransport` (`Packages/Shared/CMUXMobileCore/.../CmxTransport.swift:406`) that dials the Task 4 relay over WebSocket and runs a Noise_XX channel (reuse the Rust `cmux-terminal-client` xcframework from `Packages/Shared/CmuxTerminalClient` if it exposes Noise + relay dialing; otherwise note the gap). Bypass Stack Auth and the iroh grant judge with a hard-coded debug grant. Goal: two tagged dev builds on this Mac (`--tag w0-a`, `--tag w0-b`) where B mirrors one terminal of A through `DeviceTerminalMirrorSession` (`Sources/Devices/DeviceTerminalMirrorSession.swift`). Time-box: 3 working days. Record what worked, what had to be stubbed, and the files touched.

- [ ] **Step 2: Candidate (b) — cmux-tui remote protocol, Windows host**

Without building on Windows, list in `windows-daemon-port-estimate.md` every Unix-only path the remote daemon needs ported: `crates/cmux-tui/src/main.rs:47-64` (remote CLI stub), PTY availability (`docs/remote.md:260`), Unix sockets vs named pipes, `owner_lock.rs:93`, file permissions in `identity.rs`. Also list what the Mac app would need to *serve* its libghostty sessions over this protocol (today it is client-only via `RemoteTui`). Estimate each in days.

- [ ] **Step 3: Score and decide**

Score both on: Windows host effort; Mac host additions; reuse by future iOS/Android clients (iOS already speaks mobile RPC via `CMUXMobileCore`); upstream-merge risk. Write D-W0-1 with the scores and the choice. Amend the spec (§8.1 diagram label, §8.3 "Kết nối với máy khác", C16) and commit both repos.

### Task 6: Windows build of `cmux-tui` + `libghostty-vt` (CI)

**Files (fork, branch `shellx/w0-spikes`):**
- Create: `.github/workflows/shellx-windows-spike.yml`

**Interfaces:**
- Produces: ledger "Spike results → Windows build" with pass/fail for `x86_64-pc-windows-msvc` and `x86_64-pc-windows-gnu`, and the artifact names.

- [ ] **Step 1: Write the workflow**

`workflow_dispatch` + `push` on `shellx/w0-spikes`; `runs-on: windows-latest`; install Zig 0.16.0; `cargo build -p ghostty-vt-sys --target x86_64-pc-windows-msvc` and the same for `-gnu` (MSYS2 + lld as in upstream `cmux-tui.yml:666`); `cargo test -p cmux-tui-core platform::tests`; reuse the ConPTY smoke steps from `cmux-tui-build-package.yml:413` (`build-windows`). Upload `cmux-tui.exe`.

- [ ] **Step 2: Ask the user before pushing**

Pushing `shellx/w0-spikes` to `lephus/shellx-pro` starts CI on a public repo. Ask; on yes: `git push -u origin shellx/w0-spikes`.

- [ ] **Step 3: Read the run and record**

```bash
gh run list --repo lephus/shellx-pro --branch shellx/w0-spikes --limit 1
gh run view --repo lephus/shellx-pro <run-id> --log-failed | tail -40
```

Expected: both targets build and the platform tests pass. If `ghostty-vt-sys` fails, record the error and mark the §13 fallback (`alacritty_terminal`) as active for Task 7.

### Task 7: Windows UI toolkit spike (terminal window + Vietnamese IME)

**Files (fork, branch `shellx/w0-spikes`):**
- Create: `spikes/windows-term/` (Rust crate: GPUI window drawing a terminal grid fed by `libghostty-vt` — or `alacritty_terminal` if Task 6 failed — over ConPTY running PowerShell)
- Modify: `.github/workflows/shellx-windows-spike.yml` (build `spikes/windows-term`, upload `shellx-term-spike.exe`)

**Interfaces:**
- Produces: ledger "Decisions → D-W0-2 Windows UI toolkit" naming the toolkit, with the manual check results below and the Windows Terminal baseline numbers (same five metrics as Task 3, measured by hand on the same PC).

- [ ] **Step 1: Build the spike on CI** — artifact `shellx-term-spike.exe` builds on `windows-latest`.

- [ ] **Step 2: Ask the user for a real Windows PC**

The checks below need a physical Windows 11 machine (no CI can do IME or latency). Ask the user whether they have one and when; this task waits for them.

- [ ] **Step 3: Manual checks (user runs, agent records)**

On the PC, with `shellx-term-spike.exe` and Windows Terminal side by side:
1. Windows built-in Vietnamese Telex keyboard: type `tieengs Vieetj` → `tiếng Việt` appears in the shell; preedit is visible while composing; backspace inside a composition removes one character.
2. Unikey (Telex) and EVKey (Telex): same text, same result.
3. Display scaling 150 % and 200 %: text is crisp (no bitmap scaling blur).
4. Typometer, 200 samples: keystroke latency of the spike vs Windows Terminal.
5. Narrator reads the current line.

Pass = 1–3 and 5 work and latency ≤ 110 % of Windows Terminal. On fail, retry with the next toolkit (winit + wgpu with IME, then native Win32 + DirectWrite) and record each attempt.

- [ ] **Step 4: Record D-W0-2 and amend the spec**

Write the decision; replace the toolkit example in spec §8.3 with the chosen toolkit; commit both repos.

### Task 8: Wave 0 close-out

**Files:**
- Modify: `docs/superpowers/ledgers/native-desktop.md`
- Modify: `docs/superpowers/specs/2026-10-18-shellx-native-desktop-design.md` (only if Tasks 5/7 did not already)

- [ ] **Step 1: Write the go/no-go summary**

Ledger section `## W0 summary`: one line per §13 risk with outcome; D-W0-1 and D-W0-2; what W1 must exclude (helpers from Task 2); the license question below.

- [ ] **Step 2: Draft (do not send) the license question to Manaflow**

Draft in the ledger an email to `founders@cmux.com` asking whether `cmux-tui` is MIT (its `Cargo.toml` `license = "MIT"`) or GPL (root `LICENSE` lines 5–22). Sending it is outward-facing: tell the user it is ready and let them send it.

- [ ] **Step 3: Merge reusable work into the fork's `main` (local only)**

Tasks 2–3 already committed on `main`. Confirm `shellx/w0-spikes` is not merged. Commit the ledger in the shellx repo:

```bash
git add docs/superpowers/ledgers/native-desktop.md docs/superpowers/specs/2026-10-18-shellx-native-desktop-design.md
git commit -m "docs: native desktop W0 results, protocol and Windows toolkit decisions"
```
