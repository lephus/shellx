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

