import AppKit
import CmuxFoundation
import CmuxSettings
import ShellXBrand
import SwiftUI
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// ShellX's selected session row (spec §6.1, rulings R4 and R8): in a dark
/// sidebar without explicit selection settings the selection is the accent
/// tinted over `panel`, softer while the window is inactive; ⌘-click members
/// and hovered rows get their own fills, status pills keep their contrast on
/// the selection, and a group header standing in for its selected anchor
/// paints the same fill. Every explicit selection setting keeps its paint.
@Suite(.serialized)
@MainActor
struct ShellXSidebarSelectionTests {
    private static let defaultTint = ShellXSelectionTint(accent: ShellXPalette.primary)

    @Test func defaultDarkSelectionIsTintedAccent() {
        let selected = sidebarSelectedWorkspaceBackgroundNSColor(for: .dark, sidebarSelectionColorHex: nil)

        #expect(selected.hexString() == Self.defaultTint.sidebarFill(isEmphasized: true).nsColor.hexString())
        #expect(selected.hexString() == "#222D4E")
        #expect(selected.alphaComponent == 1)
        #expect(sidebarIsShellXSelectionFill(selected))

        let row = sidebarWorkspaceRowBackgroundStyle(
            activeTabIndicatorStyle: .leftRail,
            isActive: true,
            isMultiSelected: false,
            customColorHex: nil,
            colorScheme: .dark,
            sidebarSelectionColorHex: nil
        )
        #expect(row.color?.hexString() == "#222D4E")
        #expect(row.opacity == 1)
        #expect(row.edgeColor == nil)
    }

    @Test func unemphasizedSelectionIsSofter() {
        let softer = sidebarSelectedWorkspaceBackgroundNSColor(
            for: .dark,
            sidebarSelectionColorHex: nil,
            isEmphasized: false
        )

        #expect(softer.hexString() == Self.defaultTint.sidebarFill(isEmphasized: false).nsColor.hexString())
        #expect(softer.hexString() == "#1D2440")
        #expect(sidebarIsShellXSelectionFill(softer))

        // The row palette asks for the softer fill while its window is inactive.
        let palette = SidebarRowPalette(
            model: SidebarAppKitRowCellTests.makeModel(isActive: true),
            isSelectionEmphasized: false
        )
        #expect(palette.selectedBackground.hexString() == "#1D2440")
        #expect(palette.usesShellXSelection)
    }

    @Test func selectedForegroundIsSelectionTitle() {
        for isEmphasized in [true, false] {
            let fill = sidebarSelectedWorkspaceBackgroundNSColor(
                for: .dark,
                sidebarSelectionColorHex: nil,
                isEmphasized: isEmphasized
            )
            let title = sidebarSelectedWorkspaceForegroundNSColor(on: fill, opacity: 1)
            #expect(title.hexString() == "#F1F5FF")
            #expect(title.alphaComponent == 1)
        }

        // Names keep their weight (R4); the selected row differs by fill and
        // by these colors.
        let selected = SidebarRowPalette(model: SidebarAppKitRowCellTests.makeModel(isActive: true))
        #expect(selected.primaryText.hexString() == "#F1F5FF")
        #expect(selected.secondary().hexString() == "#B4C6E6")
        #expect(selected.secondary(0.55).hexString() == "#B4C6E6")
        #expect(selected.linkText.hexString() == "#F1F5FF")

        let unselected = SidebarRowPalette(model: SidebarAppKitRowCellTests.makeModel(isActive: false))
        #expect(unselected.primaryText.hexString() == "#E6E2F2")
        #expect(unselected.secondary().hexString() == "#8A83A6")
    }

    @Test func customAccentTintsTheSelectionAndKeepsTheTitle() {
        let accent = CmuxAccentColor(mode: .custom, customHex: "#FF8800")
        let settings = SidebarTabItemSettingsSnapshot(defaults: Self.makeDefaults(), accentColor: accent)
        let palette = SidebarRowPalette(
            model: SidebarAppKitRowCellTests.makeModel(isActive: true, settings: settings)
        )
        let orange = ShellXSelectionTint(accent: ShellXColor(hex: 0xff8800))

        #expect(palette.selectedBackground.hexString() == orange.sidebarFill(isEmphasized: true).nsColor.hexString())
        #expect(palette.usesShellXSelection)
        #expect(palette.primaryText.hexString() == "#F1F5FF")
        #expect(palette.secondary().hexString() == "#B4C6E6")
    }

    @Test func explicitSelectionSettingsKeepTheirPaint() {
        let accent = CmuxAccentColor()

        let configured = sidebarSelectedWorkspaceBackgroundNSColor(for: .dark, sidebarSelectionColorHex: "#FF0000")
        #expect(configured.hexString() == "#FF0000")

        let solid = sidebarSelectedWorkspaceBackgroundNSColor(
            for: .dark,
            sidebarSelectionColorHex: nil,
            activeTabIndicatorStyle: .solidFill
        )
        #expect(solid.hexString() == accent.nsColor(isDark: true).hexString())

        let subtle = sidebarSelectedWorkspaceBackgroundNSColor(
            for: .dark,
            sidebarSelectionColorHex: nil,
            subtleSelection: true
        )
        let subtleWash = cmuxCompositedNSColor(
            CmuxSelectionFill.resolve(colorScheme: .dark, isEmphasized: true).color,
            over: NSColor(white: 0.16, alpha: 1)
        )
        #expect(subtle.hexString() == subtleWash.hexString())

        let light = sidebarSelectedWorkspaceBackgroundNSColor(for: .light, sidebarSelectionColorHex: nil)
        #expect(light.hexString() == accent.nsColor(isDark: false).hexString())

        for color in [configured, solid, subtle, light] {
            #expect(!sidebarIsShellXSelectionFill(color), "\(color.hexString())")
        }
        // The configured color keeps its contrast-picked title, not the ShellX one.
        #expect(sidebarSelectedWorkspaceForegroundNSColor(on: configured, opacity: 1).hexString() != "#F1F5FF")

        // ⌘-click members keep today's accent wash under a configured color.
        let multi = sidebarWorkspaceRowBackgroundStyle(
            activeTabIndicatorStyle: .leftRail,
            isActive: false,
            isMultiSelected: true,
            customColorHex: nil,
            colorScheme: .dark,
            sidebarSelectionColorHex: "#FF0000"
        )
        #expect(multi.color?.hexString() == accent.nsColor(isDark: true).hexString())
        #expect(multi.opacity == 0.25)
    }

    @Test func multiSelectionUsesTenPercent() {
        for increaseContrast in [false, true] {
            let style = sidebarWorkspaceRowBackgroundStyle(
                activeTabIndicatorStyle: .leftRail,
                isActive: false,
                isMultiSelected: true,
                customColorHex: nil,
                colorScheme: .dark,
                sidebarSelectionColorHex: nil,
                increaseContrast: increaseContrast
            )
            let expected = Self.defaultTint.multiSelectionFill(increaseContrast: increaseContrast)
            #expect(style.color?.hexString() == expected.nsColor.hexString())
            #expect(style.color?.alphaComponent == 1)
            #expect(style.opacity == 1)
            #expect(style.edgeColor == nil)
        }
        let plain = sidebarWorkspaceRowBackgroundStyle(
            activeTabIndicatorStyle: .leftRail,
            isActive: false,
            isMultiSelected: true,
            customColorHex: nil,
            colorScheme: .dark,
            sidebarSelectionColorHex: nil
        )
        #expect(plain.color?.hexString() == "#181A33")
    }

    @Test func hoveredUnselectedRowPaintsRowHover() throws {
        let cell = SidebarAppKitRowCellTests.configuredCell(model: SidebarAppKitRowCellTests.makeModel(isActive: false))
        #expect((Self.paint(of: cell)?.alphaComponent ?? 0) == 0)

        cell.enforcePointerHovering(true)
        let hovered = try #require(Self.paint(of: cell))
        #expect(hovered.hexString() == "#1B1530")
        #expect(hovered.alphaComponent == 1)

        cell.enforcePointerHovering(false)
        #expect((Self.paint(of: cell)?.alphaComponent ?? 0) == 0)

        // The selected row keeps its tint under the pointer.
        let selected = SidebarAppKitRowCellTests.configuredCell(model: SidebarAppKitRowCellTests.makeModel(isActive: true))
        selected.enforcePointerHovering(true)
        let selectedPaint = try #require(Self.paint(of: selected))
        #expect(Self.isShellXSelectionFill(selectedPaint))

        // An explicit selection setting keeps today's paint: no hover fill.
        let defaults = Self.makeDefaults()
        defaults.set("#FF0000", forKey: "sidebarSelectionColorHex")
        let configured = SidebarAppKitRowCellTests.configuredCell(
            model: SidebarAppKitRowCellTests.makeModel(settings: SidebarTabItemSettingsSnapshot(defaults: defaults))
        )
        configured.enforcePointerHovering(true)
        #expect((Self.paint(of: configured)?.alphaComponent ?? 0) == 0)
    }

    @Test func selectedRowRepaintsWhenItsWindowResignsKey() throws {
        let cell = SidebarAppKitRowCellTests.configuredCell(model: SidebarAppKitRowCellTests.makeModel(isActive: true))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        let host = try #require(window.contentView)
        host.addSubview(cell)
        defer { cell.removeFromSuperview() }
        var applies = 0
        cell.applyModelProbeForTesting = { _ in applies += 1 }

        // The tint's strength follows the window, so the row repaints.
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(applies == 1)
        let painted = try #require(Self.paint(of: cell))
        #expect(Self.isShellXSelectionFill(painted))
    }

    @Test func statusPillOnSelectionHasADarkBackingAndABrighterWaitingRing() throws {
        let fill = Self.defaultTint.sidebarFill(isEmphasized: true)
        let statusFill = SidebarStatusPill.waiting.color.withAlpha(SidebarStatusPill.fillAlpha)
        let bodyOff = statusFill.composited(over: fill)
        let bodyOn = statusFill.composited(over: ShellXPalette.selectionPillBacking.composited(over: fill))

        let off = try Self.pillPixels(.waiting, isOnSelection: false, over: fill)
        #expect(Self.distance(off.body, bodyOff) < 0.02)
        #expect(Self.distance(off.ring, ShellXPalette.primaryLine.composited(over: bodyOff)) < 0.03)

        let on = try Self.pillPixels(.waiting, isOnSelection: true, over: fill)
        #expect(Self.distance(on.body, bodyOn) < 0.02)
        #expect(Self.distance(on.ring, ShellXPalette.selectionWaitingRing.composited(over: bodyOn)) < 0.03)

        // Other pills get the backing too, and no ring.
        let running = try Self.pillPixels(.running, isOnSelection: true, over: fill)
        let runningBody = SidebarStatusPill.running.color.withAlpha(SidebarStatusPill.fillAlpha)
            .composited(over: ShellXPalette.selectionPillBacking.composited(over: fill))
        #expect(Self.distance(running.body, runningBody) < 0.02)
        #expect(Self.distance(running.ring, runningBody) < 0.02)
    }

    @Test func groupHeaderOfSelectedAnchorUsesSelectionFill() throws {
        let tint = ShellXSelectionTint(
            sidebarColorScheme: .dark,
            sidebarSelectionColorHex: nil,
            activeTabIndicatorStyle: .leftRail,
            subtleSelection: false,
            accent: CmuxAccentColor()
        )
        #expect(tint == Self.defaultTint)
        let header = Self.groupHeaderModel(isAnchorActive: true, anchorActiveSelectionTint: tint)

        for isEmphasized in [true, false] {
            let palette = SidebarGroupHeaderPalette(model: header, isSelectionEmphasized: isEmphasized)
            let rowFill = sidebarSelectedWorkspaceBackgroundNSColor(
                for: .dark,
                sidebarSelectionColorHex: nil,
                isEmphasized: isEmphasized
            )
            #expect(palette.background.hexString() == rowFill.hexString())
            #expect(palette.background.alphaComponent == 1)
            #expect(palette.anchorActiveBackground.hexString() == rowFill.hexString())
            #expect(palette.nameColor.hexString() == "#F1F5FF")
            #expect(palette.anchorActiveNameColor.hexString() == "#F1F5FF")
        }

        // The configured cell paints it.
        let cell = SidebarGroupHeaderTableCellView()
        cell.configurePresentation(model: header)
        let painted = try #require((cell.backgroundView.layer?.backgroundColor).flatMap { NSColor(cgColor: $0) })
        #expect(Self.isShellXSelectionFill(painted))

        // The same conditions as a session row: an explicit selection setting
        // (or a light sidebar) leaves no tint, so the header keeps its wash.
        for explicit in [
            ShellXSelectionTint(
                sidebarColorScheme: .dark,
                sidebarSelectionColorHex: "#FF0000",
                activeTabIndicatorStyle: .leftRail,
                subtleSelection: false,
                accent: CmuxAccentColor()
            ),
            ShellXSelectionTint(
                sidebarColorScheme: .dark,
                sidebarSelectionColorHex: nil,
                activeTabIndicatorStyle: .solidFill,
                subtleSelection: false,
                accent: CmuxAccentColor()
            ),
            ShellXSelectionTint(
                sidebarColorScheme: .dark,
                sidebarSelectionColorHex: nil,
                activeTabIndicatorStyle: .leftRail,
                subtleSelection: true,
                accent: CmuxAccentColor()
            ),
            ShellXSelectionTint(
                sidebarColorScheme: .light,
                sidebarSelectionColorHex: nil,
                activeTabIndicatorStyle: .leftRail,
                subtleSelection: false,
                accent: CmuxAccentColor()
            )
        ] {
            #expect(explicit == nil)
        }
        let neutral = SidebarGroupHeaderPalette(
            model: Self.groupHeaderModel(isAnchorActive: true, anchorActiveSelectionTint: nil)
        )
        let resolver = SidebarAppearanceColorResolver()
        #expect(Self.sameColor(neutral.background, resolver.resolvedColor(.labelColor, for: .dark, opacity: 0.08)))
        #expect(Self.sameColor(neutral.nameColor, resolver.resolvedColor(.labelColor, for: .dark)))

        // A header whose anchor is not selected stays clear, with the usual name color.
        let idle = SidebarGroupHeaderPalette(
            model: Self.groupHeaderModel(isAnchorActive: false, anchorActiveSelectionTint: tint)
        )
        #expect(idle.background.alphaComponent == 0)
        #expect(Self.sameColor(idle.nameColor, resolver.resolvedColor(.labelColor, for: .dark, opacity: 0.9)))
    }

    // MARK: Helpers

    private static func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ShellXSidebarSelectionTests.\(UUID().uuidString)")!
    }

    private static func paint(of cell: SidebarWorkspaceRowTableCellView) -> NSColor? {
        cell.backgroundPaintForTesting.flatMap { NSColor(cgColor: $0) }
    }

    /// Either strength of the default tint: rows outside a key window, or
    /// in an inactive test host, paint the softer one.
    private static func isShellXSelectionFill(_ color: NSColor) -> Bool {
        let fills = [true, false].map { defaultTint.sidebarFill(isEmphasized: $0).nsColor.hexString() }
        return color.alphaComponent == 1 && fills.contains(color.hexString())
    }

    private static func sameColor(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        guard let left = lhs.usingColorSpace(.sRGB), let right = rhs.usingColorSpace(.sRGB) else { return false }
        return abs(left.redComponent - right.redComponent) < 0.001
            && abs(left.greenComponent - right.greenComponent) < 0.001
            && abs(left.blueComponent - right.blueComponent) < 0.001
            && abs(left.alphaComponent - right.alphaComponent) < 0.001
    }

    /// Largest per-channel difference in sRGB.
    private static func distance(_ color: NSColor, _ expected: ShellXColor) -> CGFloat {
        guard let actual = color.usingColorSpace(.sRGB),
              let target = expected.nsColor.usingColorSpace(.sRGB) else { return .greatestFiniteMagnitude }
        return max(
            abs(actual.redComponent - target.redComponent),
            abs(actual.greenComponent - target.greenComponent),
            abs(actual.blueComponent - target.blueComponent)
        )
    }

    /// Draws the pill over an opaque `background` and samples its body (left
    /// padding, mid height, clear of the label and ring) and its ring (top
    /// edge, mid width). Like `SidebarAppKitRowCellTests.raster`, the bitmap is
    /// device RGB; sRGB colors drawn into it read back in sRGB unchanged.
    private static func pillPixels(
        _ pill: SidebarStatusPill,
        isOnSelection: Bool,
        over background: ShellXColor
    ) throws -> (body: NSColor, ring: NSColor) {
        let view = SidebarStatusPillView()
        view.configure(pill, fontScale: 1, isOnSelection: isOnSelection)
        view.frame = NSRect(origin: .zero, size: view.preferredSize)
        let width = Int(ceil(view.bounds.width))
        let height = Int(ceil(view.bounds.height))
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        background.nsColor.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        view.displayIgnoringOpacity(view.bounds, in: context)
        NSGraphicsContext.restoreGraphicsState()
        let body = try #require(rep.colorAt(x: 3, y: height / 2))
        let ring = try #require(rep.colorAt(x: width / 2, y: 0))
        return (body, ring)
    }

    static func groupHeaderModel(
        isAnchorActive: Bool,
        anchorActiveSelectionTint: ShellXSelectionTint?
    ) -> SidebarGroupHeaderRowModel {
        SidebarGroupHeaderRowModel(
            groupId: UUID(),
            anchorWorkspaceId: UUID(),
            name: "Group",
            iconSymbol: "folder",
            tintHex: nil,
            isCollapsed: false,
            isPinned: false,
            isAnchorActive: isAnchorActive,
            isMultiSelected: false,
            multiSelectionBackgroundStyle: .clear,
            anchorActiveSelectionTint: anchorActiveSelectionTint,
            memberCount: 1,
            anchorUnreadCount: 0,
            canMarkRead: false,
            canMarkUnread: false,
            hasLatestNotifications: false,
            canMarkAllRead: false,
            canMarkAllUnread: false,
            shortcutHintText: nil,
            shortcutHintXOffset: 0,
            shortcutHintYOffset: 0,
            fontScale: 1,
            globalFontMagnificationPercent: 100,
            cwdContextMenuItems: [],
            rowSpacing: 2,
            isFirstRow: true,
            isBeingDragged: false,
            topDropIndicatorVisible: false,
            bottomDropIndicatorVisible: false,
            colorSchemeIsDark: true,
            notificationBadgeColorHex: nil
        )
    }
}
