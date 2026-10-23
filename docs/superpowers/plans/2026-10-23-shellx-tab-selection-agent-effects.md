# Tab đang chọn rõ ràng và hiệu ứng agent (desktop Mac): kế hoạch triển khai

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Phiên và tab đang chọn nổi rõ bằng nền xanh dịu (phương án B); tên phiên và tên tab chạy màu khi agent làm việc, lóe sáng rồi chạy cầu vồng dịu khi agent gọi skill hoặc workflow (phương án C).

**Architecture:**
- Bonsplit (fork `lephus/bonsplit`) có thêm hai lựa chọn `Appearance`: `selectedTabStyle` và `titleEffectStyle`. Tab có thêm trường `activity`. Bonsplit cũng có hai view công khai chạy bằng Core Animation, `TitleEffectView` và `ActivityGlyphView`; sidebar của app dùng lại chính hai view này.
- Phần logic thuần (đọc payload hook ra tín hiệu, bảng dấu theo pane, chọn hiệu ứng) nằm trong package `CmuxSidebar`.
- App đọc hook thô ở nhánh `agent.hook.enqueue`, giữ dấu theo từng workspace, rồi đưa hiệu ứng vào snapshot của sidebar và vào tab Bonsplit.

**Tech Stack:** Swift 6.0, AppKit, SwiftUI, Core Animation, Swift Testing (test Bonsplit cũ vẫn là XCTest), Xcode 26 (`scripts/test-unit.sh`, `scripts/reload.sh`).

**Spec:** `docs/superpowers/specs/2026-10-23-shellx-tab-selection-agent-effects-design.md`. Sổ quyết định: `docs/superpowers/ledgers/tab-agent-effects.md`.

## Global Constraints

- Code nối vào app chỉ dùng cú pháp Swift 6.0: không dấu phẩy cuối trong danh sách tham số, không `nonisolated` trên khai báo kiểu (`skills/cmux-architecture/references/swift-6-0-compatibility.md`).
- Mỗi file một kiểu chính. Không hàm tự do. Không enum chỉ làm namespace; `static let` chỉ dùng cho khai báo giá trị. Không làm phình `ContentView.swift` và `Workspace.swift`; với `Workspace.swift` chỉ được thêm một thuộc tính lưu trữ (`skills/cmux-architecture/SKILL.md`).
- Ô sidebar chỉ nhận snapshot bất biến cộng closure. Trường mới phải có mặt trong `==` của snapshot và của `SidebarWorkspaceRowModel` (`skills/cmux-debugging/SKILL.md`).
- Hiệu ứng chỉ chạy bằng animation Core Animation trên render server. Không display link, không timer, không việc trên main thread theo từng khung hình. Không `repeatForever` của SwiftUI trong thanh tab.
- Hiệu ứng tạm dừng khi view bị ẩn (kể cả view cha), cửa sổ không còn `.visible` trong `occlusionState`, `isPresentationActive == false`, hoặc `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` bật. Đây đúng là các điều kiện của `Sources/Sidebar/GPUSpinnerNSView.swift` (`shouldAnimate`).
- Bonsplit: khi `selectedTabStyle == nil` và `titleEffectStyle == nil` thì hành vi và hình ảnh giữ nguyên như upstream. Test Bonsplit hiện có phải xanh mà không cần sửa.
- Màu (spec §6.1, §6.2, §6.4):
  - Nền phiên đang chọn: màu nhấn 22% trên `panel` `#100b1d`; 16% khi cửa sổ không phải key hoặc app không ở phía trước. Tên `#f1f5ff`, dòng phụ `#b4c6e6`.
  - Chọn thêm bằng ⌘-click: 10% (18% khi bật Increase Contrast). Rê chuột: `#1b1530`.
  - Nhãn trạng thái trên dòng đang chọn: thêm nền `#0b0716` 55%; viền nhãn "chờ bạn" `#93c5fd` 80%.
  - Tab đang chọn của pane đang focus: nền màu nhấn 16% (12% khi cửa sổ không phải key), tên `#f1f5ff` đậm, vạch dưới 2 pt màu nhấn.
  - Tab đang chọn của pane khác: nền `#e6e2f2` 7%, tên `#cdc7e0` đậm, vạch `#5b5478`.
  - Hiệu ứng đang làm việc: chữ `#b39550`, vệt sáng `#fff3cf`, mỗi lượt 2.2 s. Cầu vồng `#f4a7c0 → #f2c879 → #8fd9a8 → #7cc8e8 → #9fb0f5 → #c9a7f2 → #f4a7c0`, mỗi vòng 3 s.
  - Lóe sáng `#d6c4ff` 26%: tăng trong 0.15 s, mờ hết trong 0.8 s, chỉ một nhịp.
  - Ký hiệu `· ✢ ✳ ✶ ✻ ✽`, mỗi hình 0.18 s, màu `#e8c468` khi đang làm việc.
- "Màu nhấn" là `CmuxAccentColor` của app (mặc định `ShellXPalette.primary` `#60a5fa`), không phải `NSColor.controlAccentColor`.
- Chỉ đổi giao diện tối. Nếu người dùng đã đặt `sidebarSelectionColorHex`, chọn kiểu `solidFill`, bật subtle selection, hoặc sidebar đang sáng, thì giữ nguyên hành vi hiện tại.
- Chữ mới qua `String(localized:defaultValue:)`, đủ 10 ngôn ngữ (`en de fr ar es zh-Hant zh-Hans ko ja vi`). Chạy `./scripts/localize-changes` và `python3 scripts/localization_catalog.py check`.
- Thêm file vào `cmuxTests/` thì chạy `./scripts/sync-test-wiring`. Thêm file vào `Sources/` thì chạy `./scripts/wire-app-sources.py`.
- Chỉ chạy thử bằng bản build có tag. Không mở, tắt hay thay `/Applications/ShellX.app`.

## Review Focus

1. **Tên dài, tên xuống dòng, phóng to chữ.** Lớp hiệu ứng phải trùng khít chữ thật: cùng khung, cùng font, cùng cách cắt "…", cùng số dòng (sidebar cho phép tên xuống tối đa 8 dòng khi bật wrap). Test: Task 7, `nameEffectMatchesWrappedTitle`.
2. **Đổi tên tại chỗ trong lúc có hiệu ứng.** Lớp hiệu ứng phải ẩn đi, ô nhập hiện chữ bình thường. Test: Task 7, `nameEffectHidesDuringInlineRename`.
3. **Đóng tab hoặc pane khi dấu còn đó.** Dấu phải xoá theo pane, không để workspace chạy cầu vồng mãi. Test: Task 5, `closingPanelClearsMarker`.
4. **Lượt mới không qua `prompt-submit`** (agent tự thức dậy sau thông báo việc nền). Dấu skill không được sống sang lượt sau. Test: Task 4, `skillMarkerDoesNotSurviveStop`.
5. **Cài đặt riêng của người dùng.** Màu chọn riêng, `solidFill`, sidebar sáng, Increase Contrast: cài đặt của người dùng vẫn thắng, và màu không đè lên nhau. Test: Task 2, `explicitSelectionSettingsKeepTheirPaint`.

---

### Task 1: Fork Bonsplit và kiểu tab đang chọn

**Files:**
- Create: `vendor/bonsplit/Sources/Bonsplit/Public/SelectedTabStyle.swift`
- Create: `vendor/bonsplit/Sources/Bonsplit/Internal/Styling/SelectedTabPaint.swift`
- Modify: `vendor/bonsplit/Sources/Bonsplit/Public/BonsplitConfiguration.swift` (thuộc tính `Appearance` và `init`, quanh dòng 415-690)
- Modify: `vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabItemView.swift`: nền tab ở `tabBackground` (khoảng dòng 1118-1138); chữ tên ở `standardContent` (khoảng 651-659); `.saturation(saturation)` (khoảng 390)
- Modify: `vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabBarSelectionChromeView.swift` (vạch chỉ báo, khoảng dòng 154-175)
- Modify: `vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabBarView.swift`: `selectionChrome` (khoảng 1083-1092) và chỗ truyền vào `TabItemView` (khoảng 1374-1387)
- Test: `vendor/bonsplit/Tests/BonsplitTests/SelectedTabStyleTests.swift`

**Interfaces:**
- Produces:
  - `public struct SelectedTabStyle: Sendable, Equatable` với `fillHex`, `inactiveWindowFillHex`, `unfocusedPaneFillHex`, `titleHex`, `unfocusedPaneTitleHex`, `indicatorHex`, `unfocusedPaneIndicatorHex: String` (mỗi chuỗi dạng `#RRGGBB` hoặc `#RRGGBBAA`, giống `ChromeColors`), `indicatorThickness: CGFloat` (mặc định `2`), `boldsSelectedTitle: Bool` (mặc định `true`), và một `public init` nhận đủ các trường.
  - `BonsplitConfiguration.Appearance.selectedTabStyle: SelectedTabStyle?`, thêm vào cuối `init` với mặc định `nil`.
  - `struct SelectedTabPaint` (internal) với `init(style: SelectedTabStyle, isPaneFocused: Bool, isWindowKey: Bool)` và các thuộc tính `fill: NSColor`, `title: NSColor`, `indicator: NSColor`, `titleWeight: Font.Weight`.

- [ ] **Step 1: Tạo nhánh trong submodule.** Chạy `git -C vendor/bonsplit switch -c shellx/tab-agent-effects`. Kết quả mong đợi: `git -C vendor/bonsplit branch --show-current` in ra `shellx/tab-agent-effects`.
- [ ] **Step 2: Viết test fail** `SelectedTabStyleTests` (Swift Testing, `@testable import Bonsplit`). Dùng style mẫu: fill `#60A5FA29`, inactive `#60A5FA1F`, unfocused fill `#E6E2F212`, title `#F1F5FF`, unfocused title `#CDC7E0`, indicator `#60A5FA`, unfocused indicator `#5B5478`.
  - `focusedPaneUsesStyleFill`: `SelectedTabPaint(style: s, isPaneFocused: true, isWindowKey: true)` cho `fill` ≈ `#60A5FA` alpha 0.16, `title` ≈ `#F1F5FF`, `indicator` ≈ `#60A5FA`, `titleWeight == .semibold`.
  - `inactiveWindowUsesInactiveFill`: pane focus nhưng `isWindowKey == false` thì `fill` có alpha ≈ 0.12.
  - `unfocusedPaneUsesNeutralPaint`: `isPaneFocused == false` thì `fill` ≈ `#E6E2F2` alpha 0.07, `indicator` ≈ `#5B5478`, `title` ≈ `#CDC7E0`.
  - `defaultAppearanceHasNoSelectedTabStyle`: `BonsplitConfiguration.Appearance().selectedTabStyle == nil`.
- [ ] **Step 3: Chạy test, phải fail.** Lệnh: `swift test --package-path vendor/bonsplit --filter SelectedTabStyleTests`. Fail vì chưa có `SelectedTabStyle`.
- [ ] **Step 4: Thêm `SelectedTabStyle`, `SelectedTabPaint` và trường mới của `Appearance`.** Đọc hex bằng chính bộ đọc hex mà `ChromeColors` đang dùng.
- [ ] **Step 5: Vẽ theo style khi `appearance.selectedTabStyle != nil`.**
  - `TabItemView` dùng `SelectedTabPaint` cho nền và chữ của tab đang chọn. Tab đang chọn dùng `saturation` 1, vì màu đã mã hoá trạng thái focus. Tab không chọn giữ nguyên như cũ.
  - `TabBarSelectionChromeView` vẽ vạch dày `indicatorThickness` ở **cạnh dưới** tab đang chọn, màu `SelectedTabPaint.indicator`. Khi `style == nil` thì vẫn vẽ 1.5 pt ở cạnh trên như cũ.
  - `TabBarView` lấy trạng thái key của cửa sổ qua `@Environment(\.controlActiveState)` (`.key`), một lần cho cả thanh, rồi truyền xuống dạng `Bool`.
- [ ] **Step 6: Chạy toàn bộ test Bonsplit, phải pass.** Lệnh: `swift test --package-path vendor/bonsplit`. Mọi test pass, kể cả `testSharedBackdropActiveTabBackgroundIsClear`.
- [ ] **Step 7: Commit trong submodule.**
```bash
git -C vendor/bonsplit add -A
git -C vendor/bonsplit commit -m "Selected tab style: tinted fill, bold title and a bottom indicator, opt-in through Appearance"
```

### Task 2: Màu phiên đang chọn ở sidebar (phương án B)

**Files:**
- Modify: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXPalette.swift` (thêm token và hàm màu cho `ShellXColor`)
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXSelectionTint.swift`
- Test: `Packages/Shared/ShellXBrand/Tests/ShellXBrandTests/ShellXSelectionTintTests.swift`
- Modify: `Sources/Sidebar/SidebarAppearanceSupport.swift`: `sidebarSelectedWorkspaceBackgroundNSColor` (khoảng 345-371), `sidebarIsShellXSelectionFill` và `sidebarSelectedWorkspaceForegroundNSColor` (khoảng 385-409), nhánh chọn nhiều trong `sidebarWorkspaceRowBackgroundStyle` (khoảng 466-528)
- Modify: `Sources/Sidebar/AppKitList/Cells/SidebarWorkspaceRowSupportViews.swift` (`SidebarRowPalette`)
- Modify: `Sources/Sidebar/AppKitList/Cells/SidebarWorkspaceRowCellView.swift`: `applySelectionChrome` (khoảng 216-248), `repaintSelectionChrome` (khoảng 250-267), cập nhật hover (khoảng 863-875)
- Modify: `Sources/ShellX/Sidebar/SidebarStatusPillView.swift` (nền tối và viền sáng khi nằm trên dòng đang chọn)
- Modify tests: `cmuxTests/ShellXThemeTests.swift` (`darkSidebarSelectionIsTheRaiseToken`), `cmuxTests/WorkspaceUnitTests.swift` (`testSelectionStaysSolidUnlessSubtleSelectionIsEnabled`)
- Create test: `cmuxTests/ShellXSidebarSelectionTests.swift`

**Interfaces:**
- Produces:
  - Token trong `ShellXPalette`: `selectionTitle` (`0xf1f5ff`), `selectionSecondary` (`0xb4c6e6`), `rowHover` (`0x1b1530`), `unfocusedTabIndicator` (`0x5b5478`), `selectionPillBacking` (`0x0b0716`, alpha 0.55), `selectionWaitingRing` (`0x93c5fd`, alpha 0.8), `effectWorkingBase` (`0xb39550`), `effectWorkingHighlight` (`0xfff3cf`), `effectFlash` (`0xd6c4ff`, alpha 0.26), `effectHighlightStops: [ShellXColor]` (7 màu theo Global Constraints).
  - Trên `ShellXColor`: `public init(nsColor: NSColor)` (đổi sang sRGB), `public func withAlpha(_ alpha: Double) -> ShellXColor`, `public func composited(over base: ShellXColor) -> ShellXColor` (kết quả đục), `public var hexStringWithAlpha: String` (`#rrggbbaa`).
  - `public struct ShellXSelectionTint: Equatable, Sendable`, với `init(accent: ShellXColor)` và các hàm:
    - `sidebarFill(isEmphasized: Bool) -> ShellXColor`: 22% hoặc 16% phủ lên `panel`, kết quả đục;
    - `multiSelectionFill(increaseContrast: Bool) -> ShellXColor`: 10% hoặc 18% phủ lên `panel`;
    - `tabFill(isWindowKey: Bool) -> ShellXColor`: màu nhấn alpha 0.16 hoặc 0.12, không phủ.

- [ ] **Step 1: Viết test fail cho package** `ShellXSelectionTintTests`:
  - `sidebarFillComposesAccentOverPanel`: `ShellXSelectionTint(accent: ShellXPalette.primary).sidebarFill(isEmphasized: true).hexString == "#222d4e"` (sai số ±1 mỗi kênh); khi `isEmphasized: false` thì kênh xanh dương nhỏ hơn.
  - `multiSelectionIsLighterThanSelection`: tương phản với `panel` của `multiSelectionFill(false)` nhỏ hơn của `sidebarFill(true)`.
  - `effectColorsReadOnSelectionAndPanel`: mỗi màu trong `[effectWorkingBase] + effectHighlightStops` có tương phản ≥ 4.5 với `panel` và với `sidebarFill(isEmphasized: true)`.
  - `selectionTitleContrast`: `selectionTitle` trên `sidebarFill(true)` ≥ 7.
- [ ] **Step 2: Chạy, phải fail.** Lệnh: `swift test --package-path Packages/Shared/ShellXBrand --filter ShellXSelectionTintTests`.
- [ ] **Step 3: Thêm token và `ShellXSelectionTint`, rồi chạy lại cho pass.** Chạy cả package: `swift test --package-path Packages/Shared/ShellXBrand`.
- [ ] **Step 4: Viết test fail cho app** trong `cmuxTests/ShellXSidebarSelectionTests.swift` (Swift Testing), gọi qua các hàm sidebar hiện có:
  - `defaultDarkSelectionIsTintedAccent`: `sidebarSelectedWorkspaceBackgroundNSColor(for: .dark)` trùng `sidebarFill(isEmphasized: true)` của màu nhấn mặc định.
  - `unemphasizedSelectionIsSofter`: `isEmphasized: false` ra đúng mức 16%.
  - `selectedForegroundIsSelectionTitle`: chữ trên nền đó là `#f1f5ff`.
  - `explicitSelectionSettingsKeepTheirPaint`: có `sidebarSelectionColorHex: "#FF0000"` thì ra `#FF0000`; `activeTabIndicatorStyle: .solidFill` thì ra màu nhấn đặc; `subtleSelection: true` thì vẫn đi nhánh subtle như cũ; `.light` thì vẫn ra màu nhấn như cũ.
  - `multiSelectionUsesTenPercent`: `sidebarWorkspaceRowBackgroundStyle(... isActive: false, isMultiSelected: true ...)` ra màu `multiSelectionFill(increaseContrast: false)`, opacity 1.
- [ ] **Step 5: Sửa các test cũ đang ghim `#171128`** để chúng ghi hành vi mới. Giữ ý định của từng test: "nền đặc khi không bật subtle" vẫn đúng, chỉ đổi giá trị mong đợi.
- [ ] **Step 6: Chạy, phải fail.** Lệnh: `scripts/shellx/test-app.sh ShellXSidebarSelectionTests ShellXThemeTests SidebarSelectedWorkspaceColorTests`.
- [ ] **Step 7: Sửa các hàm sidebar.**
  - Nhánh mặc định của ShellX trong `sidebarSelectedWorkspaceBackgroundNSColor` (sidebar tối, không màu riêng, không `solidFill`, không subtle) trả `ShellXSelectionTint(accent: ShellXColor(nsColor: accent.nsColor(for: .dark))).sidebarFill(isEmphasized:)`.
  - `sidebarIsShellXSelectionFill` nhận ra nền mới, để `SidebarRowPalette.usesShellXSelection` vẫn đúng.
  - `selectedForeground` trả `selectionTitle`. Dòng phụ trên nền chọn dùng `selectionSecondary`.
  - Chọn nhiều dùng `multiSelectionFill`.
  - `repaintSelectionChrome` không còn return sớm với nền ShellX, vì độ đậm của nền giờ đổi theo trạng thái key của cửa sổ.
- [ ] **Step 8: Rê chuột và nhãn trạng thái.**
  - Dòng chưa chọn, đang rê chuột, ở sidebar tối mặc định thì nền là `rowHover`. Bộ điều khiển đã có trạng thái hover (`SidebarWorkspaceTableController.swift` khoảng 2158-2170).
  - `SidebarStatusPillView` có thêm `isOnSelection: Bool`. Khi bật, vẽ `selectionPillBacking` dưới lớp 12%, và nhãn "chờ bạn" dùng viền `selectionWaitingRing`.
- [ ] **Step 9: Chạy lại test app, phải pass.** Lệnh như Step 6, thêm `SidebarRowPaletteTests SidebarWorkspaceSelectionColorTests SidebarAppKitRowCellTests`.
- [ ] **Step 10: Commit.**
```bash
git add Packages/Shared/ShellXBrand Sources/Sidebar Sources/ShellX/Sidebar cmuxTests cmux.xcodeproj/project.pbxproj
git commit -m "feat(shellx): the selected session row is a soft accent fill that reads at a glance"
```

### Task 3: Nối kiểu tab đang chọn vào app và trỏ submodule sang fork

**Files:**
- Modify: `.gitmodules` (URL của `vendor/bonsplit` là `https://github.com/lephus/bonsplit.git`)
- Create: `Sources/ShellX/Tabs/ShellXBonsplitStyles.swift`
- Modify: `Sources/Workspace.swift` `bonsplitAppearance(from:backgroundOpacity:splitDividerColor:tabTitleFontSize:)` (khoảng 4084-4117), chỉ thêm đối số
- Modify: `Sources/DockSplitStore+Appearance.swift` (khoảng 85-111)
- Test: `cmuxTests/ShellXBonsplitStylesTests.swift`

**Interfaces:**
- Consumes: `SelectedTabStyle` (Task 1); từ Task 2: `ShellXSelectionTint.tabFill(isWindowKey:)`, `ShellXColor.hexStringWithAlpha`, và các token `selectionTitle`, `text`, `textHi` (alpha 0.07 cho nền tab của pane khác), `unfocusedTabIndicator`.
- Produces: `struct ShellXBonsplitStyles: Equatable` với `init(accent: ShellXColor)`, `var selectedTabStyle: SelectedTabStyle` và `var titleEffectStyle: TitleEffectStyle`. Thuộc tính `titleEffectStyle` được thêm ở Task 6, sau khi Bonsplit có kiểu đó.

- [ ] **Step 1: Push nhánh submodule lên fork.**
  - Tạo fork: `gh repo fork manaflow-ai/bonsplit --clone=false --remote=false`.
  - Thêm remote: `git -C vendor/bonsplit remote add fork phule9225.github.com:lephus/bonsplit.git`.
  - Push: `git -C vendor/bonsplit push fork shellx/tab-agent-effects`.
  - Kết quả mong đợi: `git ls-remote https://github.com/lephus/bonsplit.git shellx/tab-agent-effects` in ra đúng commit HEAD của submodule.
- [ ] **Step 2: Đổi URL trong `.gitmodules`**, rồi chạy `git submodule sync vendor/bonsplit`.
- [ ] **Step 3: Viết test fail** `ShellXBonsplitStylesTests`:
  - `defaultAccentTabStyle`: với `ShellXPalette.primary`, `selectedTabStyle.fillHex` ứng với `#60a5fa` alpha 0.16, `inactiveWindowFillHex` alpha 0.12, `unfocusedPaneFillHex` ứng với `#e6e2f2` alpha 0.07, `titleHex == "#f1f5ff"`, `indicatorHex` ứng với `#60a5fa`, `unfocusedPaneIndicatorHex == "#5b5478"`, `indicatorThickness == 2`.
  - `customAccentKeepsItsHue`: accent `#ff8800` thì `fillHex` mang màu đó.
- [ ] **Step 4: Chạy, phải fail.** Lệnh: `scripts/shellx/test-app.sh ShellXBonsplitStylesTests`.
- [ ] **Step 5: Thêm `ShellXBonsplitStyles` và truyền `selectedTabStyle` vào `Appearance`** ở `Workspace.bonsplitAppearance` và trong `DockSplitStore+Appearance.swift`.
  - Màu nhấn lấy từ cùng nguồn với `SidebarTabItemSettingsSnapshot.accentColor` (khoá `appAccentColor`, `appAccentColorCustomHex`), đổi sang scheme tối.
  - Khi người dùng đổi màu nhấn thì dựng lại appearance qua đường làm mới chrome hiện có (`CmuxAccentColorObserver`).
- [ ] **Step 6: Chạy test, phải pass,** rồi build app: `CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag tabfx --build-only`. Kết quả mong đợi: build thành công.
- [ ] **Step 7: Commit** (gồm cả con trỏ submodule).
```bash
git add .gitmodules vendor/bonsplit Sources/ShellX/Tabs Sources/Workspace.swift Sources/DockSplitStore+Appearance.swift cmuxTests cmux.xcodeproj/project.pbxproj
git commit -m "feat(shellx): the focused pane's selected tab is a tinted accent tab; Bonsplit now comes from lephus/bonsplit"
```

### Task 4: Logic dấu hoạt động và hiệu ứng (package CmuxSidebar)

**Files:**
- Create, mỗi kiểu một file, trong `Packages/macOS/CmuxSidebar/Sources/CmuxSidebar/Status/AgentActivity/`: `AgentActivityMarker.swift`, `AgentActivityHookSignal.swift`, `AgentActivityMarkerTable.swift`, `AgentNameEffect.swift`, `AgentNameEffectInput.swift`, `AgentNameEffectResolution.swift`
- Test: `Packages/macOS/CmuxSidebar/Tests/CmuxSidebarTests/AgentActivityHookSignalTests.swift`, `AgentActivityMarkerTableTests.swift`, `AgentNameEffectResolutionTests.swift`

**Interfaces:**
- Produces (tất cả `public`, có DocC):
  - `struct AgentActivityMarker: Sendable, Equatable`:
    - `enum Kind: Sendable, Equatable { case skill, workflow }`;
    - `let kind: Kind`, `let name: String?`, `let generation: UInt64`.
  - `enum AgentActivityHookSignal: Sendable, Equatable`:
    - các case `turnStarted(slashCommandName: String?)`, `skillInvoked(name: String?)`, `workflowLaunched(name: String?)`, `turnEnded(hasBackgroundWork: Bool)`, `sessionEnded`;
    - `init?(claudeSubcommand: String, payload: String)`.
  - `struct AgentActivityMarkerTable: Sendable, Equatable`:
    - `init()`;
    - `private(set) var markersByPanelId: [UUID: AgentActivityMarker]`;
    - `mutating func apply(_ signal: AgentActivityHookSignal, panelId: UUID) -> Bool`, trả `true` khi bảng đổi;
    - `mutating func removePanel(_ panelId: UUID) -> Bool`.
  - `enum AgentNameEffect: Sendable, Equatable` với các case `working`, `skill(name: String?, generation: UInt64)` và `workflow(name: String?, generation: UInt64)`.
  - `struct AgentNameEffectInput: Sendable, Equatable`:
    - `enum Phase: Sendable, Equatable { case idle, running, backgroundWaiting, needsInput, error }`;
    - `let phase: Phase`, `let marker: AgentActivityMarker?`;
    - `init(phase:marker:)`.
  - `struct AgentNameEffectResolution: Sendable`:
    - `init()`;
    - `func effect(for input: AgentNameEffectInput) -> AgentNameEffect?`;
    - `func strongest(_ effects: [AgentNameEffect]) -> AgentNameEffect?`.

Quy tắc của `AgentActivityHookSignal.init?` (spec §6.6). Trả `nil` với mọi subcommand khác, payload không đọc được, hoặc tool khác:

| `claudeSubcommand` | Kết quả |
|---|---|
| `prompt-submit` | `turnStarted(slashCommandName:)`. Lấy tên từ `prompt` khớp `^\s*/([A-Za-z0-9][A-Za-z0-9_.:-]*)`, hoặc từ `<command-name>/?([^<\s]+)</command-name>` |
| `pre-tool-use`, `tool_name` = `Skill` | `skillInvoked(name: tool_input.skill)` |
| `pre-tool-use`, `tool_name` = `Workflow` | `workflowLaunched(name:)`, tên lấy từ `tool_input.name`, nếu không có thì khớp `name\s*:\s*['"]([^'"]+)['"]` trong khối `meta` của `tool_input.script` |
| `stop`, `stop-failure` | `turnEnded(hasBackgroundWork:)`: `true` khi `session_crons` không rỗng, hoặc có một `background_tasks[].status == "running"` |
| `session-end` | `sessionEnded` |

Với `pre-tool-use`, kiểm tra rẻ trước khi parse JSON: payload phải chứa `Skill` hoặc `Workflow`.

Bảng chuyển trạng thái của `AgentActivityMarkerTable.apply`:
- `turnStarted(nil)` xoá dấu. `turnStarted("x")` đặt dấu skill `x`.
- `skillInvoked` và `workflowLaunched` đặt dấu tương ứng.
- `turnEnded(false)` xoá mọi dấu. `turnEnded(true)` chỉ giữ dấu workflow.
- `sessionEnded` xoá.
- Mỗi lần đặt dấu thì `generation` lấy giá trị tiếp theo của một bộ đếm tăng dần của cả bảng.

Bảng của `AgentNameEffectResolution.effect`:
- `idle`, `needsInput`, `error` → `nil`.
- `running` → dấu skill ra `.skill`, dấu workflow ra `.workflow`, không dấu ra `.working`.
- `backgroundWaiting` → dấu workflow ra `.workflow`; còn lại `nil`.

`strongest`: skill và workflow đứng trên working. Giữa skill và workflow, `generation` lớn hơn thắng.

- [ ] **Step 1: Viết test fail** (Swift Testing). Tối thiểu các test:
  - `promptSubmitPlainResets`, `promptSubmitSlashCommandNamesSkill`, `promptSubmitCommandNameTag`;
  - `preToolUseSkillReadsSkillName`, `preToolUseWorkflowReadsNameParam`, `preToolUseWorkflowReadsMetaName`, `preToolUseWorkflowWithoutNameIsUnnamed`;
  - `otherToolsAreIgnored`, `stopWithRunningBackgroundTask`, `stopWithCronsCountsAsBackgroundWork`, `malformedPayloadIsIgnored`;
  - `skillMarkerDoesNotSurviveStop`, `workflowMarkerSurvivesStopWithBackgroundWork`, `workflowMarkerClearedByIdleStop`, `generationIncreases`, `removePanelClears`;
  - `needsInputHasNoEffect`, `runningWithoutMarkerIsWorking`, `backgroundWaitingShowsOnlyWorkflow`, `strongestPrefersNewestHighlight`.
- [ ] **Step 2: Chạy, phải fail.** Lệnh: `swift test --package-path Packages/macOS/CmuxSidebar --filter AgentActivity`. Lệnh thứ hai: `swift test --package-path Packages/macOS/CmuxSidebar --filter AgentNameEffect`.
- [ ] **Step 3: Viết các kiểu theo Interfaces.** Parse bằng `JSONSerialization`, như `AgentHookDeliveryEvent.isBestEffortTelemetry`.
- [ ] **Step 4: Chạy cả package, phải pass.** Lệnh: `swift test --package-path Packages/macOS/CmuxSidebar`.
- [ ] **Step 5: Commit.**
```bash
git add Packages/macOS/CmuxSidebar
git commit -m "feat(shellx): agent activity markers and name effects derived from Claude hook payloads"
```

### Task 5: App giữ dấu theo pane và đưa hiệu ứng vào snapshot

**Files:**
- Create: `Sources/ShellX/AgentActivity/WorkspaceAgentActivityModel.swift`
- Create: `Sources/ShellX/AgentActivity/AgentActivityHookObserver.swift`
- Create: `Sources/ShellX/AgentActivity/Workspace+AgentNameEffects.swift`
- Create: `Sources/ShellX/AgentActivity/AgentActivityText.swift`
- Modify: `Sources/Workspace.swift`: chỉ thêm một thuộc tính `let agentActivity = WorkspaceAgentActivityModel()`, cạnh `sidebarMetadata` (khoảng dòng 3227)
- Modify: `Sources/TerminalController.swift`: nhánh `agent.hook.enqueue` (khoảng 1866-1909), ngay sau khi dựng được `event` và trước `agentHookDeliveryQueue.enqueue`
- Modify: chỗ đóng panel của `Workspace`, để gọi `agentActivity.removePanel`. Tìm theo nơi `agentStatusEntriesByPanelId[panelId]` bị xoá.
- Modify: `Sources/SidebarWorkspaceSnapshotBuilder.swift` (`Snapshot` thêm hai trường), `Sources/SidebarWorkspaceSnapshotFactory.swift` (điền hai trường), `Sources/Sidebar/SidebarWorkspaceSnapshotRefreshPolicy.swift` (nếu cần so sánh trường mới)
- Test: `cmuxTests/ShellXAgentActivityTests.swift`

**Interfaces:**
- Consumes: mọi kiểu của Task 4.
- Produces:
  - `@MainActor final class WorkspaceAgentActivityModel`:
    - `private(set) var table: AgentActivityMarkerTable`;
    - `func apply(_ signal: AgentActivityHookSignal, panelId: UUID)`;
    - `func removePanel(_ panelId: UUID)`;
    - `func marker(forPanel panelId: UUID) -> AgentActivityMarker?`.
    - Khi bảng đổi thì báo cho sidebar dựng lại snapshot và cho thanh tab đồng bộ, theo đúng đường mà thay đổi của `agentStatusEntriesByPanelId` đang đi.
  - `struct AgentActivityHookObserver` với `func observation(for event: AgentHookDeliveryEvent) -> (workspaceId: UUID, surfaceId: UUID, signal: AgentActivityHookSignal)?`. Chỉ xét `event.agent == "claude"`. Id lấy từ `CMUX_WORKSPACE_ID` và `CMUX_SURFACE_ID` trong `event.environment`.
  - `extension Workspace`:
    - `func agentNameEffect(forPanel panelId: UUID) -> AgentNameEffect?`;
    - `var strongestAgentNameEffect: AgentNameEffect?`.
  - Phase của một pane:
    - lifecycle cần người dùng → `needsInput`;
    - entry agent có icon lỗi (StopFailure) → `error`;
    - lifecycle `running` với work state `waiting` → `backgroundWaiting`;
    - lifecycle `running` → `running`;
    - còn lại → `idle`.
  - `struct AgentActivityText` với `func text(for effect: AgentNameEffect) -> String`. Các khoá:
    - `sidebar.agentActivity.thinking` = "Thinking…";
    - `sidebar.agentActivity.skill` = "Skill · %@";
    - `sidebar.agentActivity.skillUnnamed` = "Skill";
    - `sidebar.agentActivity.workflow` = "Workflow · %@";
    - `sidebar.agentActivity.workflowUnnamed` = "Workflow".
  - `SidebarWorkspaceSnapshotBuilder.Snapshot` có thêm `nameEffect: AgentNameEffect?` và `agentActivityText: String?`. Hai trường này có trong `==`.

- [ ] **Step 1: Viết test fail** `ShellXAgentActivityTests` (Swift Testing, `@testable import cmux_DEV`):
  - `observerReadsClaudeSkillEvent`: dựng `AgentHookDeliveryEvent(params:deliverySocketPath:)` có `agent: "claude"`, `subcommand: "pre-tool-use"`, payload `{"tool_name":"Skill","tool_input":{"skill":"brainstorming"}}` và environment có hai id. Kết quả là `.skillInvoked(name: "brainstorming")` cùng đúng hai id.
  - `observerIgnoresCodex`: `agent: "codex"` ra `nil`.
  - `closingPanelClearsMarker`: áp dấu cho một panel rồi đóng panel đó, `marker(forPanel:)` ra `nil`.
  - `runningPanelWithSkillMarkerShowsSkill`: đặt lifecycle `running` cho panel (qua đường app vẫn dùng khi nhận `set_status`) cùng dấu skill, thì `agentNameEffect(forPanel:)` ra `.skill`.
  - `workspaceEffectPrefersNewestHighlight`: hai panel, một working, một workflow, thì `strongestAgentNameEffect` ra `.workflow`.
  - `snapshotCarriesNameEffectAndText`: snapshot của workspace có `nameEffect` và `agentActivityText == "Skill · brainstorming"` (locale `en`).
- [ ] **Step 2: Chạy, phải fail.** Lệnh: `scripts/shellx/test-app.sh ShellXAgentActivityTests`.
- [ ] **Step 3: Viết model, observer và phần mở rộng `Workspace`.**
  - Trong `TerminalController`, quan sát sự kiện trên luồng socket, rồi chuyển sang main bằng `Task { @MainActor in … }`. Không dùng `v2MainSync` và không chặn luồng socket.
  - Workspace tìm theo id. Panel tìm từ surface id bằng ánh xạ có sẵn.
  - Sự kiện của workspace hay panel không còn tồn tại thì bỏ qua.
- [ ] **Step 4: Điền hai trường snapshot** trong `SidebarWorkspaceSnapshotFactory.makeSnapshot()`.
- [ ] **Step 5: Wire file mới** bằng `./scripts/wire-app-sources.py` và `./scripts/sync-test-wiring`. Chạy test, phải pass.
- [ ] **Step 6: Commit.**
```bash
git add Sources cmuxTests cmux.xcodeproj/project.pbxproj
git commit -m "feat(shellx): the app tracks each pane's skill and workflow activity from raw Claude hooks"
```

### Task 6: View hiệu ứng tên và ký hiệu ✻ trong Bonsplit, tab mang `activity`

**Files:**
- Create, trong `vendor/bonsplit/Sources/Bonsplit/Public/`: `TabActivity.swift`, `TitleEffectStyle.swift`, `TitleEffectEnvironment.swift`, `SystemTitleEffectEnvironment.swift`, `TitleEffectView.swift`, `ActivityGlyphView.swift`
- Modify: `vendor/bonsplit/Sources/Bonsplit/Internal/Models/TabItem.swift` (trường `activity`, không đưa vào `Codable`)
- Modify: `vendor/bonsplit/Sources/Bonsplit/Public/BonsplitController.swift`: `updateTab` (khoảng 341-356) thêm `activity: TabActivity?? = nil`; kiểu `Tab` công khai cũng có `activity` nếu app đọc tab qua kiểu đó
- Modify: `vendor/bonsplit/Sources/Bonsplit/Public/BonsplitConfiguration.swift` (`Appearance.titleEffectStyle: TitleEffectStyle?`, mặc định `nil`)
- Modify: `vendor/bonsplit/Sources/Bonsplit/Internal/Views/TabItemView.swift`: `leadingIcon` (khoảng 816) và chữ tên trong `standardContent`
- Test: `vendor/bonsplit/Tests/BonsplitTests/TitleEffectViewTests.swift`, `TabActivityTests.swift`
- Modify (app): `Sources/ShellX/Tabs/ShellXBonsplitStyles.swift` (thêm `titleEffectStyle`), chỗ dựng `Appearance` của Task 3

**Interfaces:**
- Consumes: `ShellXBonsplitStyles` (Task 3); token hiệu ứng trong `ShellXPalette` (Task 2).
- Produces (`public`, có DocC):
  - `struct TabActivity: Sendable, Equatable, Hashable`:
    - `enum Kind: Sendable, Equatable, Hashable { case working, highlight }`;
    - `var kind: Kind`, `var generation: UInt64`, `var accessibilityLabel: String?`;
    - `init(kind:generation:accessibilityLabel:)`.
  - `struct TitleEffectStyle: Sendable, Equatable`:
    - `workingBaseHex`, `workingHighlightHex`, `glyphWorkingHex`, `flashHex: String`, `highlightStopHexes: [String]`;
    - `workingSweepDuration` (2.2), `highlightCycleDuration` (3.0), `glyphFrameDuration` (0.18), `flashRiseDuration` (0.15), `flashFadeDuration` (0.8), đều là `Double`;
    - một `init` nhận đủ các trường.
  - `protocol TitleEffectEnvironment` với `var reducesMotion: Bool { get }` và `func isVisible(_ view: NSView) -> Bool`.
  - `struct SystemTitleEffectEnvironment: TitleEffectEnvironment`: cửa sổ có `.visible`, view không ẩn, và đọc Reduce Motion từ `NSWorkspace`.
  - `final class TitleEffectView: NSView`:
    - `init(environment: any TitleEffectEnvironment = SystemTitleEffectEnvironment())`;
    - `func configure(text: NSAttributedString, maximumNumberOfLines: Int, kind: TabActivity.Kind?, generation: UInt64, style: TitleEffectStyle)`;
    - `var isPresentationActive: Bool`.
    - Bên trong: một `CAGradientLayer`, mask là ảnh chữ vẽ đúng cách cắt "…" và số dòng. Các khoá animation: `titleEffect.sweep` (working), `titleEffect.flow` (highlight), `titleEffect.flash` (một lần khi `generation` đổi lúc đang highlight).
    - Khi không được chạy thì gỡ animation và vẽ màu đứng yên (spec §6.4, Giảm chuyển động). Lắng nghe che cửa sổ và Reduce Motion như `GPUSpinnerNSView`.
  - `final class ActivityGlyphView: NSView`:
    - `init(environment: any TitleEffectEnvironment = SystemTitleEffectEnvironment())`;
    - `func configure(kind: TabActivity.Kind, style: TitleEffectStyle, pointSize: CGFloat)`;
    - `var isPresentationActive: Bool`.
    - Animation `CAKeyframeAnimation` rời rạc trên `contents`, 6 khung hình. Khi highlight thì khung hình đổi màu lần lượt theo `highlightStopHexes`. Khi đứng yên thì hiện ✻.
  - `TabItem.activity: TabActivity?`, và tham số mới `updateTab(…, activity: TabActivity?? = nil)`.

- [ ] **Step 1: Viết test fail** (Swift Testing, `@MainActor`). Dùng một `FakeEnvironment` có `reducesMotion` và `visible` gán được:
  - `workingInstallsSweep`: view nằm trong một cửa sổ, `kind: .working`, đang hiện, thì layer gradient có khoá `titleEffect.sweep`.
  - `highlightInstallsFlowAndFlashOnce`: `kind: .highlight`, `generation: 1` có `titleEffect.flow` và `titleEffect.flash`. Configure lại cùng `generation: 1` thì không thêm flash mới (đếm số lần thêm flash qua thuộc tính internal).
  - `reduceMotionStopsAnimations`: `reducesMotion = true` thì không còn khoá animation nào, và mask vẫn hiện chữ.
  - `hiddenViewPausesAnimations`: `visible = false` thì không còn animation.
  - `nilKindClearsEffect`: `kind: nil` thì layer hiệu ứng ẩn.
  - `tabActivityIsNotEncoded`: mã hoá `TabItem` có `activity` rồi giải mã lại, ra `activity == nil`.
  - `updateTabSetsAndClearsActivity`: qua `BonsplitController.updateTab`.
  - `glyphCyclesSixFrames`: `ActivityGlyphView` có animation `contents` với 6 giá trị.
- [ ] **Step 2: Chạy, phải fail.** Lệnh: `swift test --package-path vendor/bonsplit --filter TitleEffect`. Lệnh thứ hai: `swift test --package-path vendor/bonsplit --filter TabActivity`.
- [ ] **Step 3: Viết các kiểu.** Ảnh mask chỉ vẽ lại khi chữ, font, kích thước hoặc số dòng đổi, không vẽ theo khung hình.
- [ ] **Step 4: Dùng trong `TabItemView`** khi `tab.activity != nil` và `appearance.titleEffectStyle != nil`:
  - Ô icon hiện `ActivityGlyphView` (qua `NSViewRepresentable`), thế chỗ icon.
  - Chữ `Text(tab.title)` giữ bố cục và accessibility. Màu chữ thành trong suốt, và một `TitleEffectView` (qua `NSViewRepresentable`) phủ đúng khung chữ bằng `.overlay`.
  - Nhãn accessibility của tab thêm `activity.accessibilityLabel`.
  - Không thêm `@State` hay animation SwiftUI nào chạy lặp.
- [ ] **Step 5: Chạy toàn bộ test Bonsplit, phải pass.** Lệnh: `swift test --package-path vendor/bonsplit`.
- [ ] **Step 6: Commit trong submodule rồi push fork.**
```bash
git -C vendor/bonsplit add -A
git -C vendor/bonsplit commit -m "Tab activity: Core Animation title shimmer, highlight flow, flash and a cycling glyph, opt-in through Appearance"
git -C vendor/bonsplit push fork shellx/tab-agent-effects
```
- [ ] **Step 7: Thêm `titleEffectStyle` vào `ShellXBonsplitStyles`** từ token Task 2. Test thêm `effectStyleUsesShellXTokens` trong `ShellXBonsplitStylesTests`: `workingBaseHex == "#b39550"`, `highlightStopHexes.count == 7`, `workingSweepDuration == 2.2`. Truyền vào `Appearance`. Chạy `scripts/shellx/test-app.sh ShellXBonsplitStylesTests`, phải pass.
- [ ] **Step 8: Đồng bộ `activity` cho tab.**
  - Tạo `Sources/ShellX/AgentActivity/WorkspaceContentView+AgentActivitySync.swift` với `func syncBonsplitAgentActivity()`. Hàm này chạy theo cùng các lần kích hoạt với `syncBonsplitNotificationBadges()` (`Sources/WorkspaceContentView.swift` khoảng 545), và thêm một lần khi `WorkspaceAgentActivityModel` đổi.
  - Mỗi tab: id panel → `workspace.agentNameEffect(forPanel:)` → `TabActivity`. `.working` ra `kind: .working, generation: 0`; `.skill` và `.workflow` ra `kind: .highlight` cùng `generation` của dấu. `accessibilityLabel` lấy từ `AgentActivityText`.
  - Chỉ gọi `updateTab` khi giá trị đổi.
- [ ] **Step 9: Build app có tag, phải thành công.** Lệnh: `CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag tabfx --build-only`. Sau đó commit ở repo chính, gồm cả con trỏ submodule.
```bash
git add vendor/bonsplit Sources cmuxTests cmux.xcodeproj/project.pbxproj
git commit -m "feat(shellx): pane tabs shimmer while their agent works and light up for skills and workflows"
```

### Task 7: Tên phiên ở sidebar chạy màu, có dòng hoạt động

**Files:**
- Create: `Sources/Sidebar/AppKitList/Cells/SidebarRowNameEffectPresenter.swift` (một kiểu nhỏ lo đặt, cấu hình và ẩn hiện `TitleEffectView` trên `titleView`)
- Modify: `Sources/Sidebar/AppKitList/Cells/SidebarWorkspaceRowCellView.swift`: phần tên (khoảng 611-628); `setPresentationActive` (khoảng 402-407); bố cục (`layoutContent`); phiên đổi tên tại chỗ (`SidebarRowInlineRenameSession`)
- Modify: nơi vẽ dòng metadata của agent (tìm chỗ hiển thị `snapshot.metadataEntries`, như `SidebarWorkspaceRowSlotViews.swift`). Khi `snapshot.agentActivityText != nil`, dòng của khoá agent đang có hiệu ứng (`claude_code`) ghi chữ đó, và icon dòng thay bằng `ActivityGlyphView`.
- Modify: `Sources/Sidebar/AppKitList/Cells/SidebarWorkspaceRowModel.swift`, chỉ khi cần trường mới cho `==`; snapshot đã mang `nameEffect`
- Test: thêm vào `cmuxTests/SidebarAppKitRowCellTests.swift`, hoặc file mới `cmuxTests/ShellXSidebarNameEffectTests.swift`

**Interfaces:**
- Consumes: `TitleEffectView`, `ActivityGlyphView`, `TitleEffectStyle`, `TabActivity.Kind` (Task 6); `Snapshot.nameEffect`, `Snapshot.agentActivityText` (Task 5); `ShellXBonsplitStyles.titleEffectStyle` (Task 6).
- Produces: `final class SidebarRowNameEffectPresenter` với `init(titleView: NSTextField, host: NSView)`, `func apply(effect: AgentNameEffect?, isRenaming: Bool, style: TitleEffectStyle)`, `func layout()` và `var isPresentationActive: Bool`.

- [ ] **Step 1: Viết test fail** (cấu hình ô bằng model giống các test sẵn có trong `SidebarAppKitRowCellTests`):
  - `nameEffectHiddenWithoutEffect`: `nameEffect == nil` thì view hiệu ứng ẩn, và chữ tên giữ màu `primaryText`.
  - `nameEffectShownForWorking`: `.working` thì view hiện, frame trùng `titleView.frame`, chữ của mask bằng `titleView.stringValue`, và `titleView` vẫn giữ `stringValue` (accessibility không đổi).
  - `nameEffectMatchesWrappedTitle`: bật wrap và tên dài thì `maximumNumberOfLines` của hiệu ứng bằng của `titleView`.
  - `nameEffectHidesDuringInlineRename`: đang đổi tên thì view hiệu ứng ẩn.
  - `activityTextReplacesAgentStatusRow`: snapshot có metadata entry `claude_code` "Running" và `agentActivityText = "Thinking…"` thì dòng đó hiện "Thinking…".
  - `noNewRowWhenMetadataHidden`: không có metadata entry thì số dòng và chiều cao đo được giữ như khi không có hiệu ứng.
- [ ] **Step 2: Chạy, phải fail.** Lệnh: `scripts/shellx/test-app.sh SidebarAppKitRowCellTests ShellXSidebarNameEffectTests`.
- [ ] **Step 3: Viết `SidebarRowNameEffectPresenter` và nối vào ô.**
  - Khi có hiệu ứng: `titleView.textColor = .clear`, presenter vẽ chữ bằng mask.
  - Khi hết hiệu ứng: trả lại màu `palette.primaryText`.
  - `generation` đổi thì lóe sáng: `TitleEffectView` tự lo việc này.
  - `setPresentationActive` chuyển xuống presenter và `ActivityGlyphView`.
- [ ] **Step 4: Chạy test, phải pass.** Chạy thêm bộ ô sidebar hiện có: `scripts/shellx/test-app.sh SidebarAppKitRowCellTests SidebarRowPaletteTests ShellXSidebarSelectionTests`.
- [ ] **Step 5: Commit.**
```bash
git add Sources cmuxTests cmux.xcodeproj/project.pbxproj
git commit -m "feat(shellx): session names shimmer in the sidebar and the agent row says what it is doing"
```

### Task 8: Chữ đủ 10 ngôn ngữ và sửa spec gốc

**Files:**
- Modify: `Resources/Localizable.xcstrings` (5 khoá của Task 5)
- Modify: `scripts/localization-allowed-omissions.json`, chỉ khi cần ghi ngoại lệ trùng chữ (`identityLocales`)
- Modify: `docs/superpowers/specs/2026-10-18-shellx-native-desktop-design.md` §7.4

Bản dịch (người viết plan chọn): "Skill" và "Workflow" là tên tính năng của Claude Code, nên `vi` và `de` giữ nguyên chữ tiếng Anh, có ghi `identityLocales` kèm lý do.

| Khoá | en | vi | ja | ko | zh-Hans | zh-Hant | fr | es | de | ar |
|---|---|---|---|---|---|---|---|---|---|---|
| `sidebar.agentActivity.thinking` | Thinking… | Đang nghĩ… | 考え中… | 생각 중… | 思考中… | 思考中… | Réflexion… | Pensando… | Denkt nach… | يفكر… |
| `sidebar.agentActivity.skill` | Skill · %@ | Skill · %@ | スキル · %@ | 스킬 · %@ | 技能 · %@ | 技能 · %@ | Compétence · %@ | Habilidad · %@ | Skill · %@ | مهارة · %@ |
| `sidebar.agentActivity.skillUnnamed` | Skill | Skill | スキル | 스킬 | 技能 | 技能 | Compétence | Habilidad | Skill | مهارة |
| `sidebar.agentActivity.workflow` | Workflow · %@ | Workflow · %@ | ワークフロー · %@ | 워크플로 · %@ | 工作流 · %@ | 工作流程 · %@ | Flux de travail · %@ | Flujo de trabajo · %@ | Workflow · %@ | سير العمل · %@ |
| `sidebar.agentActivity.workflowUnnamed` | Workflow | Workflow | ワークフロー | 워크플로 | 工作流 | 工作流程 | Flux de travail | Flujo de trabajo | Workflow | سير العمل |

- [ ] **Step 1: Chạy `./scripts/localize-changes`**, điền đúng bảng trên vào packet, rồi chạy lại cho tới khi không còn mục nào cần người xem.
- [ ] **Step 2: Chạy `python3 scripts/localization_catalog.py check`.** Kết quả mong đợi: pass.
- [ ] **Step 3: Kiểm tra chữ trần.** Chạy `rg` tìm chữ tiếng Anh trần trong các file Swift đã đổi. Kết quả mong đợi: không có `Text("…")`, tooltip hay nhãn nào chưa qua `String(localized:)`.
- [ ] **Step 4: Thêm ngoại lệ vào spec gốc §7.4.** Thêm một gạch đầu dòng sau quy tắc "Không dùng gradient…": "Ngoại lệ (23/10/2026): khi agent hoạt động, chữ tên phiên và tên tab được chạy màu (vàng lướt, hoặc cầu vồng dịu khi gọi skill/workflow); xem `2026-10-23-shellx-tab-selection-agent-effects-design.md`."
- [ ] **Step 5: Commit.**
```bash
git add Resources/Localizable.xcstrings scripts/localization-allowed-omissions.json docs/superpowers/specs/2026-10-18-shellx-native-desktop-design.md
git commit -m "chore(shellx): agent activity strings in ten languages; §7.4 notes the name-effect exception"
```

### Task 9: Chạy thử bản build có tag, chụp màn hình, review toàn nhánh

**Files:**
- Create: `docs/superpowers/design/2026-10-23-tab-selection-agent-effects/dogfood/` (ảnh chụp)
- Modify: `docs/superpowers/ledgers/tab-agent-effects.md` (ghi kết quả)

- [ ] **Step 1: Kiểm tra tĩnh.** Lệnh: `python3 scripts/verify-local.py --all --jobs 3`. Kết quả mong đợi: mọi bước pass.
- [ ] **Step 2: Chạy test package.** Lệnh: `swift test --package-path Packages/Shared/ShellXBrand`, `swift test --package-path Packages/macOS/CmuxSidebar` và `swift test --package-path vendor/bonsplit`. Kết quả mong đợi: pass hết, số test chạy lớn hơn 0.
- [ ] **Step 3: Chạy test app** cho mọi suite đã đụng tới. Lệnh: `scripts/shellx/test-app.sh ShellXSidebarSelectionTests ShellXThemeTests SidebarSelectedWorkspaceColorTests SidebarRowPaletteTests SidebarWorkspaceSelectionColorTests SidebarAppKitRowCellTests ShellXBonsplitStylesTests ShellXAgentActivityTests ShellXSidebarNameEffectTests`. Kết quả mong đợi: pass, ghi lại số test đã chạy.
- [ ] **Step 4: Build có tag và mở.** Lệnh: `CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag tabfx --launch`. Mở 2 workspace, chia pane, rồi gửi sự kiện hook giả qua CLI của tag (`CMUX_TAG=tabfx scripts/cmux-debug-cli.sh …`), hoặc chạy Claude Code thật trong một tab. Mục tiêu là thấy đủ: phiên đang chọn, tab xanh của pane focus, tab xám của pane kia, vệt vàng, cầu vồng và lóe sáng khi gọi skill. Chụp màn hình bằng skill `cmux-capture` và lưu vào thư mục `dogfood/`.
- [ ] **Step 5: Đo nhanh độ trễ gõ phím.** Có 8 tab cùng hiệu ứng, attach `sample <pid>` của bản tag trong 10 giây. Kết quả mong đợi: không có khung nào của `TitleEffectView` hay `ActivityGlyphView` trên main thread theo chu kỳ. Ghi kết quả vào sổ.
- [ ] **Step 6: Review toàn nhánh** theo `skills/cmux-review/SKILL.md`, ưu tiên tính đúng. Sửa hết lỗi Critical và Important, rồi chạy lại Step 1-3.
- [ ] **Step 7: Tắt app có tag mình đã mở.** Xoá socket cũ của tag. Commit ảnh chụp và sổ.

### Task 10: Gộp, đẩy lên develop và main, dựng bản 1.3.0

Người điều phối tự làm task này, không giao cho subagent.

- [ ] **Step 1: Gộp vào develop.** Chạy `git switch develop && git merge --no-ff shellx/tab-agent-effects`. Sau đó `git push origin develop`, và `git -C vendor/bonsplit push fork shellx/tab-agent-effects` (nếu còn commit chưa đẩy).
- [ ] **Step 2: Chờ CI trên develop.** Chờ `shellx-mac`, và `shellx-mac-unit` chạy tay với các suite ở Task 9 Step 3. Kết quả mong đợi: xanh. Nếu đỏ thì sửa trên develop.
- [ ] **Step 3: Gộp vào main.** Mở PR develop → main bằng `gh pr create --base main --head develop`, rồi merge bằng `gh pr merge --merge`. Không đụng `relay/`, `web/`, `deploy/`.
- [ ] **Step 4: Tăng phiên bản lên 1.3.0.**
  - `MARKETING_VERSION = 1.3.0` và `CURRENT_PROJECT_VERSION = 113` ở mọi cấu hình của `cmux.xcodeproj`.
  - `version = "1.3.0"` trong `windows/Cargo.toml`, rồi cập nhật `Cargo.lock`.
  - Commit trên nhánh `release/1.3.0`, tách từ main.
- [ ] **Step 5: Dựng bản Windows trên CI.** Lệnh: `gh workflow run shellx-windows.yml --ref release/1.3.0`. Kết quả mong đợi: có artifact `ShellX-Setup-1.3.0.exe`.
- [ ] **Step 6: Dựng bản Mac trên máy này.** Chạy lần lượt:
  - `CMUX_GHOSTTYKIT_NO_PREBUILT=1 SHELLX_UNIVERSAL=1 scripts/shellx/sign-and-notarize.sh --build`;
  - `scripts/shellx/sign-and-notarize.sh <app>`;
  - `scripts/shellx/release/make-dmg.sh`;
  - `scripts/shellx/release/make-feeds.sh`.
  - Kết quả mong đợi: một DMG universal đã notarize, cùng các file feed.
- [ ] **Step 7: Tạo release nháp.** Lệnh: `gh release create shellx-v1.3.0 --draft`, đính kèm 6 file và `SHA256SUMS`. **Không publish** (sổ quyết định R3). Ghi lệnh publish vào báo cáo cuối.
