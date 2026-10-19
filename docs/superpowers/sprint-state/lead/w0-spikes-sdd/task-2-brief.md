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

