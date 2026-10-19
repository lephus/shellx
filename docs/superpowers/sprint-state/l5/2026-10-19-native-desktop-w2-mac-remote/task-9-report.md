# Task 9 report: bundle a fork-built cmux-tui, link shellx-core statically

Status: DONE_WITH_CONCERNS. The Xcode steps of Step 4 were skipped under ruling R18 because free disk was below 20 GB.
Worktree `/Users/lehuuphu/Documents/myProjects/shellx-wt-l5-build`, branch `shellx/l5-build`.
Commit: `9300f22f09 build(shellx): bundle fork-built cmux-tui and link shellx-core statically into the app` (parent f749732953). Not pushed.

## What was implemented
- **`scripts/shellx/build-cmux-tui.sh [--release] [--arch native|universal]`**
  - Prints only the absolute path of the built binary on stdout; cargo output goes to stderr.
  - Runs `cargo build -p cmux-tui --bin cmux-tui --locked` with default features. It never names the iroh feature and never names files.cmux.com.
  - `native` builds without `--target`, so the shared `CARGO_TARGET_DIR` stays warm. Output: `<target>/<profile>/cmux-tui`.
  - `universal` builds the aarch64 and x86_64 apple-darwin slices, adding the rustup targets if needed. It then runs `lipo` into `<target>/universal-apple-darwin/<profile>/cmux-tui` and checks both archs with `-verify_arch`.
  - Exits 2 when `CMUX_TUI_CLIENT_MANIFEST_URL` is set, and 64 on a bad argument.
  - Stamps `CMUX_TUI_BUILD_COMMIT` and `CMUX_TUI_GHOSTTY_COMMIT` the same way upstream CI does, so `--version` shows the source commit.
- **`scripts/shellx/build-shellx-core.sh`** mirrors `scripts/build-command-palette-nucleo-ffi.sh`:
  - Takes the Rust targets from `ARCHS`, or from `TARGET_TRIPLE` when `ARCHS` is empty.
  - Runs `rustup target add`, then `cargo build -p shellx-core --lib --release --locked --target …`.
  - Runs `lipo` (or rsync for a single slice) into `$(TARGET_BUILD_DIR)/shellx-core/libshellx_core.a`.
  - Fails with exit 1 when cargo is missing (no skip).
  - Exports `MACOSX_DEPLOYMENT_TARGET`, defaulting to 14.0, which is the cmux target's value in the pbxproj.
  - Sources `build-phase-caller-path.sh`, as nucleo does.
- **`Sources/ShellX/Remote/ShellXCoreFFI.swift`** has exactly the brief's interface: `final class ShellXCoreFFI: @unchecked Sendable`, `static let shared`, `func call(method:json:) throws -> Data`.
  - `#if DEBUG assert(!Thread.isMainThread)`.
  - Rejects input that is not UTF-8 or that contains a NUL (`CallError.invalidInput`). A NULL result gives `CallError.noResponse`.
  - The returned C string is copied into `Data`, then released with `shellx_core_free` in a `defer`.
  - It has a private `init` and no `ShellXCoreCalling` conformance (Task 13 adds that).
- **`cmux.xcodeproj/project.pbxproj`** (target `cmux`):
  - Run Script phase `5E11A00000000000000000B0 "ShellX core"` is the first phase, before Sources.
  - Its script is `"${SRCROOT}/scripts/shellx/build-shellx-core.sh"`, its input is `$(SRCROOT)/shellx-core/Cargo.lock`, and its output is `$(TARGET_BUILD_DIR)/shellx-core/libshellx_core.a`.
  - In **both** configurations of the target (Debug `A5001082`, Release `A5001083`; the target has no others):
    - `HEADER_SEARCH_PATHS = ($(inherited), $(SRCROOT)/shellx-core/include)`
    - `LIBRARY_SEARCH_PATHS = ($(inherited), $(TARGET_BUILD_DIR)/shellx-core)`
    - `OTHER_LDFLAGS += -lshellx_core -framework Security -framework CoreFoundation`
  - The Swift file was added with `scripts/wire-app-sources.py Sources/ShellX/Remote/ShellXCoreFFI.swift` and the test with `scripts/sync-test-wiring`. Their dry-run showed only my file.
  - `plutil -lint`: OK.
- **`cmux-Bridging-Header.h`**: added `#include "shellx_core.h" // ShellX:`.
- **`scripts/shellx/sign-and-notarize.sh`** (touches an L0 file): in `sign_and_notarize`, before `==> signing`, it now builds the universal cmux-tui and installs it with `CMUX_TUI_CLIENT_LOCAL=… scripts/install-cmux-tui-client.sh "$app"`.
- **`tests/test_shellx_remote.py`** holds the brief's five guards. **`tests/test-execution.toml`** registers it in lane `linux-guard`.
- **`cmuxTests/ShellXCoreFFITests.swift`**: `@Suite struct ShellXCoreFFITests` with the brief's `coreAnswersThroughFFI` test.

## RED / GREEN
- **RED.** `python3 tests/test_shellx_remote.py` gave `FAILED (failures=1, errors=1)`:
  - `test_cmux_tui_is_built_from_this_fork`: `FileNotFoundError scripts/shellx/build-cmux-tui.sh`.
  - `test_core_is_linked_statically`: `pbxproj has no build-shellx-core.sh phase`.
  - The other three passed already: the lock is clean, and the directories they scan are clean or absent.
- **GREEN.** `python3 tests/test_shellx_remote.py` gave `Ran 5 tests … OK`, before the commit and again after.

## Step 4 checks
| Check | Ran? | Result |
| --- | --- | --- |
| `python3 tests/test_shellx_remote.py` | yes | OK (5 tests) |
| `scripts/shellx/build-cmux-tui.sh` dev build (`CARGO_INCREMENTAL=0 CARGO_TARGET_DIR=…/shellx-pro/cmux-tui/target`) | yes | exit 0 in 2m24s; printed `/Users/lehuuphu/Documents/myProjects/shellx-pro/cmux-tui/target/debug/cmux-tui` |
| `cmux-tui --version` on that binary | yes | `cmux 0.1.0 (9300f22f09f4057bcc90079d36bf859eb9cb9e73; ghostty cb1ef7091cdef0b581ee2cbd83742b653253523e)` |
| `cmux-tui remote-probe --json` | yes | app `cmux-tui`; caps include `wireguard-hub` and `browser-proxy`, the two that reload.sh requires |
| `CMUX_TUI_CLIENT_MANIFEST_URL=… build-cmux-tui.sh` | yes | exit 2 |
| `reload.sh --tag l5 --build-only` | **skipped** | R18: df showed 18 GB free (< 20 GB) right before |
| `<app>/Contents/Resources/bin/cmux-tui --version` | **skipped** | needs the app build |
| `nm -gU <app>/Contents/MacOS/cmux \| grep -c shellx_core_call` | **skipped** | needs the app build (substitute below) |
| `scripts/shellx/test-app.sh ShellXCoreFFITests` | **skipped** | needs the app build (substitute below) |
| `python3 scripts/verify-local.py --all` | yes | PASSED 16/16, plus `--swift` syntax parse of both new Swift files |
| `--release --arch universal` | not run locally (ruling) | CI / release will exercise it |

I never took the build lock, because I never ran an Xcode build. I created no DerivedData. The tag-l5 bundle id would have been `com.cmuxterm.app.debug.l5`, app name "cmux DEV l5" (reload.sh's tag default). It is not `pro.shellx…`.

**Substitute evidence for the FFI test and the `nm` check (not app-hosted).** I compiled `ShellXCoreFFI.swift` with a two-line driver. The command was `swiftc -swift-version 5 -DDEBUG -import-objc-header shellx-core/include/shellx_core.h` against `libshellx_core.a`, with `-framework Security -framework CoreFoundation -target arm64-apple-macos14.0`.
- It linked with no ld warnings.
- Calling `call(method:"nope")` from `Task.detached` printed `PASS {"error":{"code":"unknown_method","message":"unknown method: nope"}}`.
- `nm -gU <binary> | grep -c shellx_core_call` returned `1`.
- I deleted the scratch output afterwards.

**Native static libs.** `cargo rustc --release --lib --crate-type staticlib -- --print native-static-libs` (with `MACOSX_DEPLOYMENT_TARGET=14.0`) printed `-framework Security -framework CoreFoundation -liconv -lSystem -lc -lm`.
- `-lSystem`, `-lc` and `-lm` are implicit.
- `nm -u libshellx_core.a | grep iconv` was empty, so `-liconv` was left out.

## df readings (`/`)
| When | Free |
| --- | --- |
| Start | 21 GB |
| After the submodule init | 20 GB |
| During the first cmux-tui build | 13, then 11, then 10 GB |

The drop came from other processes. The shared target stayed at about 3.6 GB, and other lanes and node processes were active. Following the 15 GB rule, I stopped my cargo build, which ended with exit 143.

| When | Free |
| --- | --- |
| After deleting my `shellx-core/target` (415 MB) | 19 GB |
| Guarded retry of the cmux-tui build | 18 GB at the end |

The retry used a guard that kills the build below 15 GB, and the guard never fired. 18 GB was also the reading right before the Xcode gate, so the Xcode steps were skipped.

## Files changed (commit 9300f22f09)
- New: `scripts/shellx/build-cmux-tui.sh`, `scripts/shellx/build-shellx-core.sh`, `Sources/ShellX/Remote/ShellXCoreFFI.swift`, `tests/test_shellx_remote.py`, `cmuxTests/ShellXCoreFFITests.swift`
- Modified: `cmux.xcodeproj/project.pbxproj`, `cmux-Bridging-Header.h`, `tests/test-execution.toml`, `scripts/shellx/sign-and-notarize.sh` (**touches an L0 file**)

The worktree also has the `ghostty` (793 MB) and `vendor/bonsplit` submodules initialised with `--reference` from shellx-pro. They sit at the recorded commits, so the commit carries no gitlink change. They are kept for the later Xcode build.

## Concerns
1. **The Xcode build has not been verified.** Step 4's app build, the bundled `--version`, the `nm` check on the app, and `test-app.sh ShellXCoreFFITests` are still open. Run them once disk is at least 20 GB, under `~/.shellx-build.lock`:
   `CMUX_TUI_CLIENT_LOCAL="$(scripts/shellx/build-cmux-tui.sh)" CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag l5 --build-only`
   - Build-only removes its staged tagged app at the end. The cmux-tui install goes into `…/DerivedData/cmux-l5/Build/Products/Debug/cmux DEV.app` (the `$APP_PATH` before staging), so check that bundle.
   - The pbxproj wiring, the header search, the bridging include and the link flags are proven only statically and by the swiftc and C smoke tests.
2. **The `sign-and-notarize.sh` edit differs from the brief's one-liner.** The brief's `CMUX_TUI_CLIENT_LOCAL="$(…)" install…` would run the installer with an empty variable if the build failed. That includes exit 2 when the manifest URL is set. The installer would then download from files.cmux.com. I split it into two lines:
   `local tui; tui="$(scripts/shellx/build-cmux-tui.sh --release --arch universal)"`
   `CMUX_TUI_CLIENT_LOCAL="$tui" scripts/install-cmux-tui-client.sh "$app"`
   This fails closed under `set -e`. The file had no `# ShellX:` markers (it is all ShellX code), so I added a plain comment.
3. **The phase's only input is `Cargo.lock`, as the brief specifies verbatim.** Xcode therefore skips "ShellX core" when only `shellx-core/src` changes and the `.a` already exists. That gives stale cores in incremental dev builds. A follow-up could add `$(SRCROOT)/shellx-core/src` or set `alwaysOutOfDate = 1`; cargo's no-op takes about 1 s.
4. **The shared `CARGO_TARGET_DIR` has one output path, `target/debug/cmux-tui`, for every worktree.** Whichever lane built last owns it. My retry overwrote the binary at `/Users/lehuuphu/Documents/myProjects/shellx-pro/cmux-tui/target/debug/cmux-tui`, which is now stamped with commit 9300f22f09. reload.sh copies it right away, but parallel lanes can race.
5. **`reload.sh` still downloads a Manaflow-published artifact.** Its unconditional `scripts/install-coderouter-client.sh` fetches from `github.com/manaflow-ai/coderouter-releases`. That is not files.cmux.com, so the guards pass, but it is Manaflow's build. Flag it to L0.
6. **The release universal path, including the x86_64 cross-build of ghostty-vt with zig, has never run.** Its first real run will be on CI or in a release.
7. **Small deviations:**
   - `build-shellx-core.sh` prefers `ARCHS` over `TARGET_TRIPLE` (nucleo prefers `TARGET_TRIPLE`). This way a universal Release links both slices.
   - The copied guard helpers also skip `target/` directories.
   - The guard class sets `longMessage = False` and has short messages on the two pbxproj asserts. A failure would otherwise print the whole pbxproj (about 2.5 MB).

## Fix round 1 (ruling R20)
Commit: `7d67ae9a5c fix(shellx): ShellX core phase always runs cargo, tests see the core header` (parent 9300f22f09). Not pushed.

### Changes
1. **The "ShellX core" phase always runs cargo, and the `.a` changes only when its bytes do.**
   - Phase `5E11A00000000000000000B0` now has `alwaysOutOfDate = 1`. The input (`Cargo.lock`) and output (`libshellx_core.a`) declarations are unchanged.
   - `build-shellx-core.sh` copies or lipos the slices into a staging file, `.libshellx_core.a.$$`, in the same dir. If the existing `.a` has the same bytes (`cmp -s`), the script prints `unchanged …` and leaves the `.a` and its mtime alone. Otherwise it `mv -f`s the staged file in. An EXIT trap removes the staging file.
   - The unconditional `touch` is gone.
2. **The test target can find the core header.** Both cmuxTests configs (`F1000011A1B2C3D4E5F60718` Debug, `F1000012A1B2C3D4E5F60718` Release) now have `HEADER_SEARCH_PATHS = ("$(inherited)", "$(SRCROOT)/shellx-core/include")`. The bridging-header include line is unchanged.
3. **`openssl` added to the forbidden lock names** in `tests/test_shellx_remote.py`.

### Checks and their output
| Check | Covers | Output |
| --- | --- | --- |
| `plutil -lint cmux.xcodeproj/project.pbxproj` | 1, 2 | `OK` |
| `python3 tests/test_shellx_remote.py` | 3, plus the pbxproj guard | `OK` (5 tests) |
| `python3 scripts/verify-local.py --affected` | the pbxproj changes | `PASSED: 15/15 selected checks` |

**The mtime check, for change 1.** Free disk was 17 GB before the runs. I ran the script twice:
`TARGET_BUILD_DIR=<scratch>/tbd ARCHS=arm64 CARGO_INCREMENTAL=0 scripts/shellx/build-shellx-core.sh`

```
run 1: Finished `release` … in 22.83s / built …/tbd/shellx-core/libshellx_core.a
       exit=0 mtime=1792363403 (Oct 19 05:43:23 2026)
run 2: Finished `release` … in 0.05s / unchanged …/tbd/shellx-core/libshellx_core.a
       exit=0 mtime=1792363403 (Oct 19 05:43:23 2026)
```

- After the two runs the output dir held only `libshellx_core.a`; the staging file was removed.
- `lipo -info` reported arm64.
- I deleted the scratch output and `shellx-core/target` afterwards. Disk was 17 GB at the end.

No Xcode build was run: R18 needs ≥20 GB free and the lock, and df showed 17 GB.
