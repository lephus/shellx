### Task 6: ShellX name in the UI, CLI help and About

**Files (fork):**
- Create: `scripts/shellx/rebrand_strings.py`
- Modify: `Resources/Localizable.xcstrings`, `Resources/InfoPlist.xcstrings`, `Resources/Info.plist:120-174`, `ConfigPackErrors.xcstrings`, the 10 package catalogs, and Swift `defaultValue:` literals (about 796) — via the script
- Modify: menus `Sources/cmuxApp.swift:528-575` ("About ShellX", "Quit ShellX", "Open shellx.json", "Make ShellX the Default Terminal")
- Modify: `Sources/App/About/AboutPanelView.swift:10-55`, `Sources/AboutLicenseContent.swift:9,33`
- Modify: CLI usage/help text in `CLI/cmux.swift` and `CLI/CMUXCLI+*.swift` where the program name is printed
- Modify: accent-color setting label "cmux" → "ShellX" (`CmuxAccentColor` mode display text)
- Test: `tests/test_shellx_branding.py`, `cmuxTests/ShellXAboutTests.swift`

**Interfaces:**
- Consumes: `ShellXBrand`.
- Produces: `python3 scripts/shellx/rebrand_strings.py [--check]` — rules in this order: `` `cmux `` → `` `shellx `` (command in code spans), `cmux.json` → `shellx.json`, `~/.config/cmux` → `~/.config/shellx`, `.cmux/` → `.shellx/`, whole word `cmux` → `ShellX`; never touches catalog keys, `CMUX_` names or lines listed in its `PRESERVE` set (attribution strings). `--check` exits 1 if a change would be made. Wave 2+ reruns it after upstream merges.
- `AboutLicenseContent.attributions: [Attribution]` where `struct Attribution { let name: String; let license: String; let url: URL? }`.

- [ ] **Step 1: Write the failing tests**

```python
def test_no_cmux_in_english_ui_strings():
    cat = json.load(open("Resources/Localizable.xcstrings"))
    hits = [k for k, v in cat["strings"].items()
            if re.search(r"\bcmux\b", en_value(v) or "", re.I) and k not in PRESERVE_KEYS]
    assert hits == []

def test_rebrand_script_is_idempotent():
    assert subprocess.run([sys.executable, "scripts/shellx/rebrand_strings.py", "--check"]).returncode == 0
```

```swift
@Test func aboutCreditsUpstreamAndAssets() {
  let names = AboutLicenseContent.attributions.map(\.name)
  #expect(names.contains("cmux (Manaflow, Inc.)"))
  #expect(names.contains("Ghostty"))
  #expect(names.contains("coolicons by Kryston Schwarze"))
  #expect(names.contains("Space Grotesk"))
  #expect(AboutLicenseContent.sourceCodeURL == ShellXBrand.sourceCodeURL)
}
```

- [ ] **Step 2: Run** both tests — Expected: FAIL.

- [ ] **Step 3: Write `rebrand_strings.py`, run it, and make the About/menu/CLI edits.** About shows the logo (Task 9 asset; use a placeholder until then), "ShellX", version, "GPL-3.0-or-later — source: github.com/lephus/shellx-pro", and the attribution list with licenses (cmux: GPL-3.0-or-later; Ghostty: MIT; coolicons: CC BY 4.0; Space Grotesk: OFL-1.1).

- [ ] **Step 4: Run** the new tests plus the existing catalog tests (`python3 -m pytest tests/test_localizable_xcstrings_structure.py tests/test_localization_defaults.py tests/test_lint_xcstrings.py -q`, `python3 scripts/localization_catalog.py check`) — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shellx): ShellX name across UI strings, menus, CLI help and About with attributions"
```

