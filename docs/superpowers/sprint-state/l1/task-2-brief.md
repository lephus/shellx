### Task 2: App identity — bundle ids, name, team, scheme, update feed

**Files (fork):**
- Modify: `cmux.xcodeproj/project.pbxproj` (app + `CmuxDockTilePlugin` bundle ids and product names; `CMUX_TEAM_ID_PREFIX` → `W4RF3W4VTZ.`; `CMUX_AUTH_CALLBACK_SCHEME` → `shellx` / `shellx-dev`; `SPARKLE_PUBLIC_KEY` → empty; remove the `cmuxTunnelExtension` target from the app's embed phase and dependencies; exclude helpers listed as excluded in the W0 ledger)
- Modify: `Resources/Info.plist` (`SUFeedURL` → `ShellXBrand.updateFeedURL` value; `SUEnableAutomaticChecks` = `false` until Wave 3 sets the EdDSA key)
- Modify: `scripts/reload.sh:11-12` (`APP_NAME="ShellX DEV"`, `BUNDLE_ID="pro.shellx.desktop.debug"`)
- Modify: Swift team-ID pins: `CLI/cmux.swift:3128,3134,3717,4821`, `CLI/CMUXCLI+Sudo.swift:102`, `ComputerUseHelperTrust.swift:19`, `CodeRouterDebugServerIdentityPolicy.swift:24`, `Sources/Cloud/CodeRouterSocketPeerVerifier.swift` (use `ShellXBrand.teamID` where the file can import it; otherwise the literal `W4RF3W4VTZ`)
- Modify: every non-test Swift literal `com.cmuxterm.app` used as *our own* bundle id (151 files mention `com.cmuxterm`; replace with `ShellXBrand.bundleID`-derived values; leave MDM-domain strings for Task 4)
- Create: `tests/shellx_guard.py` (shared helpers for every `tests/test_shellx_*.py`)
- Test: `tests/test_shellx_identity.py`

**Interfaces:**
- Consumes: `ShellXBrand` (Task 1).
- Produces:
  - tagged dev builds are `ShellX DEV <tag>.app` with bundle id `pro.shellx.desktop.debug.<tag>`;
  - `tests/shellx_guard.py`: `read(path) -> str`, `offenders(pattern: str, roots: list[str], allow: list[tuple[str, str]]) -> list[str]` (walks text files under `roots`, returns `"path:line"` hits whose path is not in `allow`; every allow entry is `(path, reason)`), `png_size(path) -> tuple[int, int]`, `sha256(path) -> str`. Later tasks import these.

- [ ] **Step 1: Write the failing guard test**

```python
def test_app_bundle_ids_are_shellx():
    pbx = read("cmux.xcodeproj/project.pbxproj")
    assert "PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop;" in pbx
    assert "PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop.debug;" in pbx
    assert "com.cmuxterm.app;" not in pbx and "7WLXT3NR37" not in pbx

def test_no_upstream_team_id_in_sources():
    assert offenders(r"7WLXT3NR37", roots=["Sources", "CLI", "Packages", "Resources", "scripts"], allow=ALLOWLIST) == []

def test_update_feed_is_shellx():
    info = plistlib.load(open("Resources/Info.plist", "rb"))
    assert info["SUFeedURL"] == "https://download.shellx.pro/desktop/appcast.xml"
    assert info["SUEnableAutomaticChecks"] is False
```

`offenders` and `read` come from `tests/shellx_guard.py`; `ALLOWLIST` is a module-level list of `(path, reason)` that starts empty.

- [ ] **Step 2: Run** `python3 -m pytest tests/test_shellx_identity.py -q` — Expected: FAIL.

- [ ] **Step 3: Make the identity changes listed under Files.**

- [ ] **Step 4: Run the test** — Expected: PASS. Run `./scripts/reload.sh --tag w1 --build-only` — Expected: `ShellX DEV w1.app` builds; `defaults read "<app>/Contents/Info" CFBundleIdentifier` prints `pro.shellx.desktop.debug.w1`.

- [ ] **Step 5: Register the test lane and commit**

```bash
git add -A tests/test_shellx_identity.py tests/test-execution.toml cmux.xcodeproj Resources/Info.plist scripts/reload.sh Sources CLI Packages
git commit -m "feat(shellx): ShellX bundle ids, team, URL scheme and update feed; drop tunnel extension"
```

