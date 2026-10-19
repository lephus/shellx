### Task 3: Coexistence — paths, sockets, CLI name, hook marker, UTIs

**Files (fork):**
- Modify: `Packages/macOS/CmuxSettings/Sources/CmuxSettings/SocketControl/SocketControlSettings.swift:23-25,358` (socket names from `ShellXBrand.socketBaseName`, `/tmp/shellx-last-cli-path`)
- Modify: `CmuxStateDirectory.swift:33` (`~/.local/state/shellx`)
- Modify: the 46 Application Support sites (`ShellX` directory), `KeyboardShortcutSettingsFileStore.swift:20` and `CmuxConfig.swift:1846` plus the other config-path references (197 refs in 52 files: `~/.config/shellx/shellx.json`, per-project `shellx.json` / `.shellx/shellx.json`)
- Modify: `cmux.xcodeproj/project.pbxproj` (`cmux-cli` `PRODUCT_NAME = shellx`; exported UTIs `com.cmux.*` → `pro.shellx.*`; sidebar extension point `com.cmuxterm.app.cmux.sidebar` → `pro.shellx.desktop.sidebar`)
- Modify: `Sources/App/CmuxCLIPathInstaller.swift:55` (`/usr/local/bin/shellx`), `Sources/HostSettingsActions.swift:161`, `Sources/TerminalController+SocketCleanup.swift:54`, `Sources/RemoteInteractiveShellBootstrapBuilder.swift:274` (`~/.shellx/bin/shellx`), `Resources/shell-integration/*`, `Resources/bin/cmux-*-wrapper` (rename to `shellx-*-wrapper`), `cmux.sdef` (suite name ShellX)
- Modify: `CLI/CMUXCLI+AgentHookCatalog.swift` and `cmux-codex-hook-*.sh` (marker `"__shellx"`; hook command `shellx claude-hook` etc.)
- Modify: keychain service names (`com.cmuxterm.app.socket-control`, `com.cmuxterm.iroh.*.v1`, `ai.manaflow.cmux.phone-push.*`) → `pro.shellx.desktop.*`
- Test: `tests/test_shellx_coexistence.py`, `cmuxTests/ShellXPathsTests.swift`

**Interfaces:**
- Consumes: `ShellXBrand` (Task 1), tagged build (Task 2).
- Produces: the bundled CLI at `Contents/Resources/bin/shellx`; Task 13's perf harness calls it.

- [ ] **Step 1: Write the failing tests**

```python
FORBIDDEN = [r"/tmp/cmux", r"\.config/cmux", r"\.local/state/cmux", r"Application Support/cmux",
             r'"__cmux"', r"\bcom\.cmux\.", r"/usr/local/bin/cmux\b", r"cmux\.sock"]
def test_no_cmux_runtime_names():
    for pat in FORBIDDEN:
        assert offenders(pat, roots=["Sources", "CLI", "Packages", "Resources"], allow=ALLOWLIST) == [], pat
def test_cli_product_is_shellx():
    assert re.search(r"PRODUCT_NAME = shellx;", read("cmux.xcodeproj/project.pbxproj"))
```

```swift
@Test func runtimePathsAreShellX() {
  #expect(CmuxStateDirectory.defaultURL.path.hasSuffix("/.local/state/shellx"))
  #expect(SocketControlSettings.defaultSocketFileName.hasPrefix("shellx"))
  #expect(CmuxConfig.userConfigURL.path.hasSuffix("/.config/shellx/shellx.json"))
}
```

Use the real accessor names in those types (read them first). If an accessor doesn't exist, add a `static var` that the existing code already computes inline, and use it at the call site.

- [ ] **Step 2: Run** `python3 -m pytest tests/test_shellx_coexistence.py -q` and `scripts/shellx/test-app.sh ShellXPathsTests` — Expected: FAIL.

- [ ] **Step 3: Make the renames listed under Files.** Environment variable names (`CMUX_*`) stay as they are.

- [ ] **Step 4: Run both tests and the CLI tests** — Expected: PASS for the new tests. Run `xcodebuild test-without-building -only-testing:cmuxCLITests` through the repo's CLI test lane; update CLI tests whose expected text names `cmux` as the command.

- [ ] **Step 5: Manual side-by-side check (Review Focus 1)**

Install upstream cmux (if not present) and launch it together with `ShellX DEV w1.app`. In a cmux terminal, `cmux identify` (or the equivalent status command) reaches cmux. In a ShellX terminal, `shellx identify` reaches ShellX. `ls /tmp | grep -E 'cmux|shellx'` shows separate sockets. Record the result in the ledger.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(shellx): own sockets, config/state paths, CLI name, hook marker and UTIs so ShellX coexists with cmux"
```

