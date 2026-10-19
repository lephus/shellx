### Task 8: coolicons everywhere

**Files (fork):**
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/Resources/Coolicons.xcassets/` (all 442 coolicons v4.1 SVGs from the `krystonschwarze/coolicons` v4.1 release, one imageset each named like `Terminal`, `Bell_Ring`, `Window_Sidebar`; `"preserves-vector-representation": true`, `"template-rendering-intent": "template"`)
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/Resources/icon-map.json` (`{ "<sf.symbol.name>": "<Coolicon_Name>" }` for every literal symbol the app uses)
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXIcon.swift`
- Create: `scripts/shellx/import_coolicons.py` (builds the asset catalog from the release zip) and `scripts/shellx/icon_codemod.py`
- Modify: about 670 call sites — `Image(systemName:)` (~470), `systemImage:` labels (~153), `NSImage(systemSymbolName:)` (~46) — via the codemod; plus `RenderableSystemSymbol`, `SidebarCompactStatusGlyph` symbol names, `RightSidebarMode` icons, `CmuxButtonIcon`
- Modify: the `Package.swift` of every package whose sources the codemod touched (add the `ShellXBrand` dependency)
- Test: `Packages/Shared/ShellXBrand/Tests/ShellXBrandTests/ShellXIconTests.swift`, `tests/test_shellx_icons.py`

**Interfaces:**
- Consumes: `ShellXBrand` package.
- Produces:
  - `public enum ShellXIcon { static func image(_ sfSymbol: String) -> Image; static func nsImage(_ sfSymbol: String, accessibilityDescription: String?) -> NSImage?; static func cooliconName(for sfSymbol: String) -> String?; static func image(coolicon: String) -> Image; static func nsImage(coolicon: String) -> NSImage? }`. `image(_:)` returns the mapped coolicon as a template image, or `Image(systemName:)` when the name is unmapped (user-supplied names).
  - `ShellXLabel(_ title: LocalizedStringKey, icon: String)` view replacing `Label(_, systemImage:)`.
  - Coolicon names used by later tasks: `Laptop`, `Desktop`, `Data`, `Mobile`, `Link`, `Terminal`, `Bell_Ring`, `Add_Plus`, `Search_Magnifying_Glass`, `Settings`, `Circle_Check`, `Shield_Check`, `Users`, `Window_Sidebar`, `More_Horizontal`, `Qr_Code`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func mappedSymbolUsesCoolicon() { #expect(ShellXIcon.cooliconName(for: "terminal") == "Terminal") }
@Test func everyMappedCooliconExists() {
  for (_, name) in ShellXIcon.map { #expect(ShellXIcon.nsImage(coolicon: name) != nil, "\(name)") }
}
@Test func unmappedUserSymbolFallsBack() {   // Review Focus 3
  #expect(ShellXIcon.cooliconName(for: "figure.surfing") == nil)
  #expect(ShellXIcon.nsImage("figure.surfing", accessibilityDescription: nil) != nil)
}
```

```python
def test_no_direct_sf_symbol_calls_outside_shellxicon():
    pat = r"Image\(systemName:|systemImage:|NSImage\(systemSymbolName:"
    assert offenders(pat, roots=["Sources", "Packages/macOS", "Packages/Shared"], allow=DYNAMIC_ALLOWLIST) == []
def test_every_literal_symbol_is_mapped():
    used = literal_symbols_before_codemod()   # read from scripts/shellx/icon_codemod.py --list (frozen snapshot file)
    mapping = json.load(open(MAP_PATH))
    assert sorted(set(used) - set(mapping)) == []
```

`DYNAMIC_ALLOWLIST` = `ShellXIcon.swift` and the call sites whose symbol name comes from user config (custom commands, workspace group `iconSymbol`, `sidebar.compactStatusIcons`), each with reason.

- [ ] **Step 2: Run** `swift test --package-path Packages/Shared/ShellXBrand` and `python3 -m pytest tests/test_shellx_icons.py -q` — Expected: FAIL.

- [ ] **Step 3: Import the icons, write the map, implement `ShellXIcon`, run the codemod.** For each SF symbol pick the nearest coolicon by meaning; where coolicons has none, pick the closest and list it in `scripts/shellx/icon-substitutions.md` (spec §15). Agent logos in `Assets.xcassets/AgentIcons/*` are brand logos and stay.

- [ ] **Step 4: Run the tests** — Expected: PASS. Build `--tag w1` — Expected: builds; spot-check the sidebar, settings, command palette, browser panel and file preview: no SF Symbols visible.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shellx): replace SF Symbols with coolicons v4.1 via ShellXIcon"
```

