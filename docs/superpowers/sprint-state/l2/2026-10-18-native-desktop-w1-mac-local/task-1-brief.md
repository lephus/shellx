### Task 1: Branch, test runner, and the `ShellXBrand` package

**Files (fork):**
- Create: `scripts/shellx/test-app.sh`
- Create: `Packages/Shared/ShellXBrand/Package.swift`
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXBrand.swift`
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXPalette.swift`
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXFeatures.swift`
- Test: `Packages/Shared/ShellXBrand/Tests/ShellXBrandTests/ShellXBrandTests.swift`
- Modify: `cmux.xcodeproj/project.pbxproj` (add the local package; link `ShellXBrand` to the `cmux` app and `cmux-cli` targets)

**Interfaces:**
- Produces:
  - `scripts/shellx/test-app.sh <Suite> [<Suite>…]` — runs the app-hosted `cmux-unit` scheme limited to `-only-testing:cmuxTests/<Suite>` via `scripts/test-unit.sh` (extend that script to forward extra `xcodebuild` args if it doesn't).
  - `public enum ShellXBrand` with `static let` values: `appName = "ShellX"`, `cliName = "shellx"`, `bundleID = "pro.shellx.desktop"`, `teamID = "W4RF3W4VTZ"`, `urlScheme = "shellx"`, `configDirectoryName = "shellx"`, `configFileName = "shellx.json"`, `projectConfigDirectoryName = ".shellx"`, `appSupportDirectoryName = "ShellX"`, `socketBaseName = "shellx"`, `hookMarker = "__shellx"`, `utiPrefix = "pro.shellx"`, `websiteURL: URL` = `https://shellx.pro`, `sourceCodeURL: URL` = `https://github.com/lephus/shellx-pro`, `contactEmail = "phule9225@gmail.com"`, `updateFeedURL: URL` = `https://download.shellx.pro/desktop/appcast.xml`.
  - `public struct ShellXColor: Equatable, Sendable { init(hex: UInt32, alpha: Double = 1); var hexString: String /* "#rrggbb" */; var alpha: Double; var color: SwiftUI.Color; var nsColor: NSColor }`.
  - `public enum ShellXPalette` with `static let` `bg, panel, raise, line, border, text, textHi, muted, primary, primarySoft, primaryLine, primaryText, running, done, error: ShellXColor` (values in Global Constraints).
  - `public enum ShellXFeatures { public static let remoteMachines = false }` — Wave 2 flips it.

- [ ] **Step 1: Branch**

```bash
cd ~/Documents/myProjects/shellx-pro && git switch main && git switch -c shellx/w1-mac-local
```

- [ ] **Step 2: Write the failing package tests**

```swift
@Test func paletteMatchesSpec() {
  #expect(ShellXPalette.bg.hexString == "#0b0716")
  #expect(ShellXPalette.primary.hexString == "#60a5fa")
  #expect(ShellXPalette.running.hexString == "#e8c468")
  #expect(ShellXPalette.done.hexString == "#6fd49a")
  #expect(ShellXPalette.error.hexString == "#e88a8a")
  #expect(ShellXPalette.primarySoft.hexString == "#60a5fa" && ShellXPalette.primarySoft.alpha == 0.12)
  #expect(ShellXPalette.primaryLine.alpha == 0.45)
}
@Test func identity() {
  #expect(ShellXBrand.bundleID == "pro.shellx.desktop")
  #expect(ShellXBrand.cliName == "shellx")
  #expect(ShellXFeatures.remoteMachines == false)
}
```

Add one `#expect` per remaining palette token with its spec value.

- [ ] **Step 3: Run** `swift test --package-path Packages/Shared/ShellXBrand` — Expected: FAIL (types missing).

- [ ] **Step 4: Implement the package** (`swift-tools-version: 6.0`, `.macOS(.v14)`, library product `ShellXBrand`), then link it in the project.

- [ ] **Step 5: Run** `swift test --package-path Packages/Shared/ShellXBrand` — Expected: PASS. Then `CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag w1 --build-only` — Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Packages/Shared/ShellXBrand scripts/shellx/test-app.sh scripts/test-unit.sh cmux.xcodeproj/project.pbxproj
git commit -m "feat(shellx): ShellXBrand package (identity, palette, feature switches) and app test runner"
```

