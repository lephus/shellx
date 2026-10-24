import AppKit
import Bonsplit
import CmuxFoundation
import CmuxRemoteSession
import CmuxTerminalCore
import ShellXBrand
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The styles ShellX hands to Bonsplit's tab bars (spec §6.2, ruling R6): the
/// selected tab of the focused pane is the app accent at a low alpha behind a
/// near-white bold title and a 2 pt accent indicator, the selected tab of any
/// other pane is a neutral wash with a violet-grey indicator, and a tab bar
/// over a light terminal theme keeps Bonsplit's default selected tab. Only the
/// workspace's own split tree gets the style: the window has exactly one
/// accent tab, so the Dock and the remote-tmux trees nested in a workspace
/// keep Bonsplit's default selected tab. The agent activity effects (spec
/// §6.4) play on every dark bar, those two included, and on no light bar.
@Suite(.serialized)
@MainActor
struct ShellXBonsplitStylesTests {
    private static let darkBar = NSColor(hex: "#0b0716")!
    private static let lightBar = NSColor(hex: "#ffffff")!

    private static func config(background: NSColor) -> GhosttyConfig {
        var config = GhosttyConfig()
        config.backgroundColor = background
        config.backgroundOpacity = 1
        return config
    }

    /// The accent the app draws now, the one the sidebar selection reads.
    private static var appAccent: CmuxAccentColor {
        AppDelegate.shared?.accentColor ?? CmuxAccentColor()
    }

    @Test func defaultAccentTabStyle() {
        let style = ShellXBonsplitStyles(accent: ShellXPalette.primary).selectedTabStyle

        // Focused pane: the accent at 16%, or 12% while the window is not key.
        #expect(style.fillHex == "#60a5fa29")
        #expect(style.fillHex == ShellXPalette.primary.withAlpha(0.16).hexStringWithAlpha)
        #expect(style.inactiveWindowFillHex == "#60a5fa1f")
        #expect(style.inactiveWindowFillHex == ShellXPalette.primary.withAlpha(0.12).hexStringWithAlpha)
        #expect(style.titleHex == "#f1f5ff")
        #expect(style.indicatorHex == "#60a5fa")

        // Any other pane: `text-hi` at 7%, the `text` title and a violet-grey indicator.
        #expect(style.unfocusedPaneFillHex == "#e6e2f212")
        #expect(style.unfocusedPaneFillHex == ShellXPalette.textHi.withAlpha(0.07).hexStringWithAlpha)
        #expect(style.unfocusedPaneTitleHex == "#cdc7e0")
        #expect(style.unfocusedPaneIndicatorHex == "#5b5478")

        #expect(style.indicatorThickness == 2)
        #expect(style.boldsSelectedTitle)
    }

    @Test func customAccentKeepsItsHue() {
        let style = ShellXBonsplitStyles(accent: ShellXColor(hex: 0xff8800)).selectedTabStyle

        #expect(style.fillHex == "#ff880029")
        #expect(style.inactiveWindowFillHex == "#ff88001f")
        #expect(style.indicatorHex == "#ff8800")

        // Only the focused pane draws the accent; the rest is the palette.
        #expect(style.titleHex == "#f1f5ff")
        #expect(style.unfocusedPaneFillHex == "#e6e2f212")
        #expect(style.unfocusedPaneTitleHex == "#cdc7e0")
        #expect(style.unfocusedPaneIndicatorHex == "#5b5478")
    }

    @Test func effectStyleUsesShellXTokens() {
        let style = ShellXBonsplitStyles(accent: ShellXPalette.primary).titleEffectStyle

        #expect(style.workingBaseHex == "#b39550")
        #expect(style.workingHighlightHex == "#fff3cf")
        #expect(style.glyphWorkingHex == "#e8c468")
        // The flash is `#d6c4ff` at 26%: the hex carries the alpha.
        #expect(style.flashHex == "#d6c4ff42")
        #expect(style.flashHex == ShellXPalette.effectFlash.hexStringWithAlpha)
        #expect(style.highlightStopHexes.count == 7)
        #expect(style.highlightStopHexes == ShellXPalette.effectHighlightStops.map(\.hexString))
        #expect(style.workingSweepDuration == 2.2)
        #expect(style.highlightCycleDuration == 3.0)
        #expect(style.glyphFrameDuration == 0.18)
        #expect(style.flashRiseDuration == 0.15)
        #expect(style.flashFadeDuration == 0.8)

        // The effects never follow the accent, and only dark chrome plays them.
        #expect(ShellXBonsplitStyles(accent: ShellXColor(hex: 0xff8800)).titleEffectStyle == style)
        #expect(ShellXBonsplitStyles.titleEffectStyle(for: .dark) == style)
        #expect(ShellXBonsplitStyles.titleEffectStyle(for: .light) == nil)
        #expect(ShellXBonsplitStyles(accent: CmuxAccentColor(), chromeBackground: Self.lightBar)?.titleEffectStyle == nil)
    }

    /// The extension the workspace's appearance goes through: a dark bar gets
    /// both ShellX styles, a light bar gets both back to Bonsplit's defaults.
    @Test func appearanceTakesBothShellXStylesOrNeither() throws {
        let dark = try #require(ShellXBonsplitStyles(accent: CmuxAccentColor(), chromeBackground: Self.darkBar))
        let light = ShellXBonsplitStyles(accent: CmuxAccentColor(), chromeBackground: Self.lightBar)
        #expect(light == nil)
        var appearance = BonsplitConfiguration.Appearance.default
        #expect(!appearance.carriesShellXStyles(dark))

        appearance.applyShellXStyles(dark)
        #expect(appearance.selectedTabStyle == dark.selectedTabStyle)
        #expect(appearance.titleEffectStyle == dark.titleEffectStyle)
        #expect(appearance.carriesShellXStyles(dark))
        #expect(!appearance.carriesShellXStyles(light))

        appearance.applyShellXStyles(light)
        #expect(appearance.selectedTabStyle == nil)
        #expect(appearance.titleEffectStyle == nil)
        #expect(appearance.carriesShellXStyles(light))

        let copy = BonsplitConfiguration.Appearance.default.applyingShellXStyles(dark)
        #expect(copy.selectedTabStyle == dark.selectedTabStyle)
        #expect(copy.titleEffectStyle == dark.titleEffectStyle)
    }

    @Test func lightTabBarGetsNoStyle() {
        let accent = CmuxAccentColor()

        #expect(ShellXBonsplitStyles(accent: accent, chromeBackground: Self.lightBar) == nil)
        #expect(ShellXBonsplitStyles(accent: accent, chromeBackground: Self.darkBar) != nil)
    }

    /// The decision is the contrast choice Bonsplit makes for the bar's own
    /// text, so the near-white title is only ever drawn where Bonsplit draws
    /// light text. `#e44330` is the mid-tone a plain brightness cutoff gets
    /// wrong: dark by brightness, light by contrast.
    @Test(arguments: ["#ffffff", "#fdf6e3", "#eff1f5", "#e44330"])
    func barsThatTakeDarkTextGetNoStyle(hex: String) {
        let bar = NSColor(hex: hex)!

        #expect(ShellXBonsplitStyles(accent: CmuxAccentColor(), chromeBackground: bar) == nil)
    }

    @Test(arguments: ["#0b0716", "#282c34", "#272822", "#002b36", "#1e1e2e", "#000000"])
    func barsThatTakeLightTextGetTheStyle(hex: String) {
        let bar = NSColor(hex: hex)!

        #expect(ShellXBonsplitStyles(accent: CmuxAccentColor(), chromeBackground: bar) != nil)
    }

    @Test func appAccentIsReadTheWayTheDarkSidebarDrawsIt() throws {
        let cmuxBlue = try #require(
            ShellXBonsplitStyles(accent: CmuxAccentColor(), chromeBackground: Self.darkBar)
        )
        #expect(cmuxBlue == ShellXBonsplitStyles(accent: ShellXPalette.primary))

        let custom = CmuxAccentColor(mode: .custom, customHex: "#FF8800")
        let orange = try #require(ShellXBonsplitStyles(accent: custom, chromeBackground: Self.darkBar))
        #expect(orange == ShellXBonsplitStyles(accent: ShellXColor(hex: 0xff8800)))
        #expect(orange.selectedTabStyle.fillHex == "#ff880029")
    }

    @Test func workspaceChromeFollowsTheTerminalBackground() throws {
        let darkStyles = try #require(
            ShellXBonsplitStyles(accent: Self.appAccent, chromeBackground: Self.darkBar)
        )
        let expected = darkStyles.selectedTabStyle
        let workspace = Workspace(title: "Tests")
        defer { workspace.teardownAllPanels() }
        let appliedStyle = { workspace.bonsplitController.configuration.appearance.selectedTabStyle }
        let appliedEffects = { workspace.bonsplitController.configuration.appearance.titleEffectStyle }

        workspace.applyGhosttyChrome(from: Self.config(background: Self.darkBar), reason: "test-dark")
        #expect(appliedStyle() == expected)
        #expect(appliedEffects() == darkStyles.titleEffectStyle)

        // A light theme gives the bar back to Bonsplit's default selected tab
        // and plays no agent effects.
        workspace.applyGhosttyChrome(from: Self.config(background: Self.lightBar), reason: "test-light")
        #expect(appliedStyle() == nil)
        #expect(appliedEffects() == nil)

        workspace.applyGhosttyChrome(from: Self.config(background: Self.darkBar), reason: "test-dark-again")
        #expect(appliedStyle() == expected)
        #expect(appliedEffects() == darkStyles.titleEffectStyle)
    }

    /// The Dock is a second Bonsplit tree with a focused pane of its own, so a
    /// style there would put a second accent tab in the window. Its dark tab
    /// bar still plays the agent effects.
    @Test func dockKeepsTheUpstreamSelectedTab() {
        let dark = DockSplitStore.makeAppearance(from: Self.config(background: Self.darkBar))
        #expect(dark.chromeColors.backgroundHex == "#0B0716")
        #expect(dark.selectedTabStyle == nil)
        #expect(dark.titleEffectStyle?.workingBaseHex == "#b39550")
        #expect(dark.titleEffectStyle == ShellXBonsplitStyles(accent: ShellXPalette.primary).titleEffectStyle)

        let light = DockSplitStore.makeAppearance(from: Self.config(background: Self.lightBar))
        #expect(light.chromeColors.backgroundHex == "#FFFFFF")
        #expect(light.selectedTabStyle == nil)
        #expect(light.titleEffectStyle == nil)
    }

    @Test func embeddedRemoteTmuxConfigurationDropsTheSelectedTabStyle() {
        var appearance = BonsplitConfiguration.Appearance.default
        appearance.applyShellXStyles(ShellXBonsplitStyles(accent: ShellXPalette.primary))
        appearance.tabBarHeight = 36
        let workspaceConfiguration = BonsplitConfiguration(appearance: appearance)

        let embedded = workspaceConfiguration.remoteTmuxEmbedded

        #expect(embedded.appearance.selectedTabStyle == nil)
        // Only the style goes; the rest of the appearance still follows the
        // workspace, the agent effects included.
        #expect(embedded.appearance.tabBarHeight == 36)
        #expect(embedded.appearance.titleEffectStyle?.workingBaseHex == "#b39550")
        #expect(embedded.appearance.titleEffectStyle == appearance.titleEffectStyle)
    }

    /// A mirrored tmux window nests its own Bonsplit tree in a workspace tab,
    /// built from the workspace's configuration and updated from it later. Its
    /// focused pane must not draw a second accent tab next to the workspace's.
    @Test func remoteTmuxMirrorKeepsTheUpstreamSelectedTab() {
        let workspace = Workspace(title: "Tests")
        defer { workspace.teardownAllPanels() }
        workspace.applyGhosttyChrome(from: Self.config(background: Self.darkBar), reason: "test-dark")
        let workspaceConfiguration = workspace.bonsplitController.configuration
        #expect(workspaceConfiguration.appearance.selectedTabStyle != nil)

        let connection = RemoteTmuxControlConnection(
            host: RemoteTmuxHost(destination: "user@host"),
            sessionName: "work"
        )
        let mirror = RemoteTmuxWindowMirror(
            windowId: 1,
            panelId: UUID(),
            connection: connection,
            layout: RemoteTmuxLayoutNode(
                width: 80,
                height: 24,
                x: 0,
                y: 0,
                content: .pane(7)
            ),
            appearance: workspaceConfiguration.appearance,
            workspaceBonsplitController: workspace.bonsplitController,
            makePanel: { _ in nil }
        )
        #expect(mirror.bonsplitController.configuration.appearance.selectedTabStyle == nil)

        mirror.applyWorkspaceBonsplitConfiguration(workspaceConfiguration)
        let mirrored = mirror.bonsplitController.configuration.appearance
        #expect(mirrored.selectedTabStyle == nil)
        #expect(mirrored.tabBarHeight == workspaceConfiguration.appearance.tabBarHeight)
    }
}
