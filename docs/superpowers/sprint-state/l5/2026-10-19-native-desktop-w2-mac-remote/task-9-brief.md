### Task 9: Build the bundled `cmux-tui` and link `shellx-core` into the app

**Files:**
- Create: `scripts/shellx/build-cmux-tui.sh`, `scripts/shellx/build-shellx-core.sh`, `Sources/ShellX/Remote/ShellXCoreFFI.swift`, `tests/test_shellx_remote.py`, `cmuxTests/ShellXCoreFFITests.swift`
- Modify: `cmux.xcodeproj/project.pbxproj` (target `cmux`: Run Script phase "ShellX core" placed before Compile Sources, `"${SRCROOT}/scripts/shellx/build-shellx-core.sh"`, inputs `$(SRCROOT)/shellx-core/Cargo.lock`, output `$(TARGET_BUILD_DIR)/shellx-core/libshellx_core.a`; `LIBRARY_SEARCH_PATHS += $(TARGET_BUILD_DIR)/shellx-core`; `HEADER_SEARCH_PATHS += $(SRCROOT)/shellx-core/include`; `OTHER_LDFLAGS += -lshellx_core` + the frameworks printed by `--print native-static-libs`), `cmux-Bridging-Header.h` (`#include "shellx_core.h" // ShellX:`), `scripts/shellx/sign-and-notarize.sh` (L0's file: before signing, `CMUX_TUI_CLIENT_LOCAL="$(scripts/shellx/build-cmux-tui.sh --release --arch universal)" scripts/install-cmux-tui-client.sh "$APP"` — flag it in the "ready" report), `tests/test-execution.toml` (`tests/test_shellx_remote.py`, lane `linux-guard`)

**Interfaces:**
- Produces: `scripts/shellx/build-cmux-tui.sh [--release] [--arch native|universal]` → prints the absolute path of the built `cmux-tui` (default features; `lipo` for universal); exits 2 if `CMUX_TUI_CLIENT_MANIFEST_URL` is set. Dev build recipe used by every later task: `CMUX_TUI_CLIENT_LOCAL="$(scripts/shellx/build-cmux-tui.sh)" CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag l5`.
- `scripts/shellx/build-shellx-core.sh` mirrors `scripts/build-command-palette-nucleo-ffi.sh` (targets from `ARCHS`/`TARGET_TRIPLE`, `rustup target add`, `cargo build --release --locked --target …`, `lipo` into `$(TARGET_BUILD_DIR)/shellx-core/libshellx_core.a`); fails (no skip) when cargo is missing.
- `ShellXCoreFFI` (app target): `final class ShellXCoreFFI: @unchecked Sendable { static let shared = ShellXCoreFFI(); func call(method: String, json: Data) throws -> Data }`; DEBUG-asserts `!Thread.isMainThread`. Task 13 adds `extension ShellXCoreFFI: ShellXCoreCalling {}` (the protocol comes from Task 10, which runs in parallel).

- [ ] **Step 1: Write the failing tests**

```python
class ShellXRemoteGuards(unittest.TestCase):
    def test_cmux_tui_is_built_from_this_fork(self):
        s = read("scripts/shellx/build-cmux-tui.sh")
        self.assertNotIn("files.cmux.com", s); self.assertNotIn("iroh-transport", s)
    def test_shellx_code_never_downloads_manaflow_artifacts(self):
        self.assertEqual(offenders(r"files\.cmux\.com|manaflow-ai/cmux/\.github", roots=["scripts/shellx", "shellx-core", "Sources/ShellX"], allow=[]), [])
    def test_core_lock_has_no_forbidden_crates(self):
        lock = read("shellx-core/Cargo.lock")
        for name in ["aws-lc-rs", "aws-lc-sys", "openssl-sys", "native-tls", "iroh"]:
            self.assertNotIn(f'name = "{name}"', lock)
    def test_core_is_linked_statically(self):
        pbx = read("cmux.xcodeproj/project.pbxproj")
        self.assertIn("build-shellx-core.sh", pbx); self.assertIn("-lshellx_core", pbx)
    def test_remote_sources_import_no_cloud_stack(self):
        self.assertEqual(offenders(r"^\s*import (CmuxCloud|CmuxIrohTransport|CmuxIrxTransport|CMUXAuthCore|CmuxAuthRuntime)\b", roots=["Sources/ShellX/Remote"], allow=[]), [])
```

`read`/`offenders` come from `tests/shellx_guard.py` (W1 Task 2); if L1 has not merged it yet, copy those two helpers into this file with a `# TODO(checkpoint 1): import from shellx_guard` and remove the copy after checkpoint 1.

```swift
@Test func coreAnswersThroughFFI() async throws {
  let out = try await Task.detached { try ShellXCoreFFI.shared.call(method: "nope", json: Data("{}".utf8)) }.value
  #expect(String(decoding: out, as: UTF8.self).contains("\"unknown_method\""))
}
```

- [ ] **Step 2: Run** `python3 tests/test_shellx_remote.py` — Expected: FAIL.
- [ ] **Step 3: Implement** the scripts, pbxproj wiring (`scripts/wire-app-sources.py Sources/ShellX/Remote/ShellXCoreFFI.swift`, `scripts/sync-test-wiring`), bridging-header line.
- [ ] **Step 4: Run** `python3 tests/test_shellx_remote.py` → PASS; take the build lock, `CMUX_TUI_CLIENT_LOCAL="$(scripts/shellx/build-cmux-tui.sh)" CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag l5 --build-only` → succeeds; `"<app>/Contents/Resources/bin/cmux-tui" --version` prints a version; `nm -gU "<app>/Contents/MacOS/cmux" | grep -c shellx_core_call` → `1`; `scripts/shellx/test-app.sh ShellXCoreFFITests` → PASS; `python3 scripts/verify-local.py --all` → PASS. Release the lock.
- [ ] **Step 5: Commit** `git commit -m "build(shellx): bundle fork-built cmux-tui and link shellx-core statically into the app"`

