import AppKit
import ShellXBrand
import ShellXIcons
import SwiftUI

/// ShellX title bar, right side (spec §7.1): the search field look-alike with
/// its shortcut key cap, the settings button and the right sidebar toggle.
/// The left sidebar toggle and the notifications bell stay in the existing left
/// accessory (`TitlebarControlsView`), whose bell badge draws `ShellXTitlebarModel`.
/// Flat colors only, no gradients or shadows; everything but the lit right sidebar
/// toggle follows the terminal theme.
struct ShellXTitlebarView: View {
    let shortcutText: String
    let onSearch: () -> Void
    let onSettings: () -> Void
    /// "Chia sẻ phiên" (L7); hidden while `ShellXShareGate` is off.
    var showsShare: Bool = false
    var onShare: () -> Void = {}
    /// Lit while this window's right sidebar (Files, Find, …) is open.
    @ObservedObject var rightSidebarToggle: ShellXRightSidebarToggleModel = ShellXRightSidebarToggleModel()
    var onToggleRightSidebar: () -> Void = {}

    @State private var searchHover = false
    /// The terminal theme the search field and the icons take their colors from.
    @State private var themeObserver = GhosttyDialogThemeObserver.shared
    @State private var settingsHover = false
    @State private var shareHover = false
    @State private var rightSidebarHover = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSearch) {
                let theme = themeObserver.theme
                let muted = Color(nsColor: theme.secondaryForeground)
                HStack(spacing: 6) {
                    ShellXIcon.image("magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(muted)
                    Text(ShellXTitlebarModel(unreadCount: 0).localizedSearchPlaceholder)
                        .font(.system(size: 12))
                        .foregroundColor(muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(shortcutText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(muted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color(nsColor: theme.separator), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 8)
                .frame(width: 280, height: 24)
                // Tints of the terminal theme's foreground, so the field sits on any theme.
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: theme.foreground.withAlphaComponent(searchHover ? 0.1 : 0.05)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(nsColor: searchHover ? theme.border : theme.separator), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { searchHover = $0 }
            .accessibilityIdentifier("titlebarControl.shellxSearch")
            .accessibilityLabel(ShellXTitlebarModel(unreadCount: 0).localizedSearchPlaceholder)
            .help(ShellXTitlebarModel(unreadCount: 0).localizedSearchPlaceholder)

            if showsShare {
                Button(action: onShare) {
                    ShellXIcon.image("link")
                        .font(.system(size: 14))
                        .foregroundColor(iconColor(hover: shareHover))
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(iconFill(hover: shareHover))
                        )
                        .background(ShellXShareAnchor())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { shareHover = $0 }
                .accessibilityIdentifier("titlebarControl.shellxShare")
                .accessibilityLabel(ShellXShareStrings.title)
                .help(ShellXShareStrings.title)
            }

            Button(action: onSettings) {
                ShellXIcon.image("gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(iconColor(hover: settingsHover))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(iconFill(hover: settingsHover))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { settingsHover = $0 }
            .accessibilityIdentifier("titlebarControl.shellxSettings")
            .accessibilityLabel(ShellXTitlebarStrings.settings)
            .help(ShellXTitlebarStrings.settings)

            Button(action: onToggleRightSidebar) {
                // AppKit-hosted like the left accessory's icons, which stay
                // visible where a SwiftUI-composited symbol can draw blank.
                CmuxSystemSymbolImage(symbolName: "sidebar.right", pointSize: 14, tint: rightSidebarIconColor)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(rightSidebarFill)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { rightSidebarHover = $0 }
            .accessibilityIdentifier("titlebarControl.shellxRightSidebar")
            .accessibilityLabel(ShellXTitlebarStrings.toggleRightSidebar)
            .accessibilityAddTraits(rightSidebarToggle.isOn ? .isSelected : [])
            .help(ShellXTitlebarStrings.toggleRightSidebarTooltip)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
    }

    private var rightSidebarIconColor: Color {
        if rightSidebarToggle.isOn { return ShellXPalette.primaryText.color }
        return iconColor(hover: rightSidebarHover)
    }

    private var rightSidebarFill: Color {
        if rightSidebarToggle.isOn { return ShellXPalette.primarySoft.color }
        return iconFill(hover: rightSidebarHover)
    }

    /// Icon tint from the terminal theme's foreground: softer at rest, full on hover.
    private func iconColor(hover: Bool) -> Color {
        let foreground = themeObserver.theme.foreground
        return Color(nsColor: hover ? foreground : foreground.withAlphaComponent(0.72))
    }

    private func iconFill(hover: Bool) -> Color {
        hover ? Color(nsColor: themeObserver.theme.foreground.withAlphaComponent(0.1)) : Color.clear
    }
}

/// Where the right sidebar goes while this accessory shows. Upstream its mode
/// bar shares the titlebar row, so its trailing icons drew under the gear and
/// the toggle; while the accessory shows the sidebar starts below the row.
enum ShellXTitlebarAccessoryLayout {
    /// Both titlebar accessories hide in minimal mode and full screen.
    static func isShown(isMinimalMode: Bool, isFullScreen: Bool) -> Bool {
        !isMinimalMode && !isFullScreen
    }

    static func rightSidebarTopInset(isMinimalMode: Bool, isFullScreen: Bool) -> CGFloat {
        isShown(isMinimalMode: isMinimalMode, isFullScreen: isFullScreen) ? WindowChromeMetrics.appTitlebarHeight : 0
    }

    /// The workspace titlebar band keeps its drag surface off a right sidebar
    /// mode bar in the same row (#5099); below the row there is none to avoid.
    static func titlebarBandTrailingInset(rightSidebarWidth: CGFloat, isMinimalMode: Bool, isFullScreen: Bool) -> CGFloat {
        rightSidebarTopInset(isMinimalMode: isMinimalMode, isFullScreen: isFullScreen) > 0 ? 0 : rightSidebarWidth
    }
}

/// Applies `ShellXTitlebarAccessoryLayout.rightSidebarTopInset`, following
/// presentation mode changes the same way as the terminal's top padding.
struct ShellXRightSidebarTitlebarInsetModifier: ViewModifier {
    let isFullScreen: Bool

    @AppStorage(WorkspacePresentationModeSettings.modeKey)
    private var workspacePresentationMode = WorkspacePresentationModeSettings.defaultMode.rawValue

    func body(content: Content) -> some View {
        content.padding(.top, ShellXTitlebarAccessoryLayout.rightSidebarTopInset(
            isMinimalMode: WorkspacePresentationModeSettings.mode(for: workspacePresentationMode) == .minimal,
            isFullScreen: isFullScreen
        ))
    }
}

enum ShellXTitlebarStrings {
    static var settings: String {
        String(localized: "titlebar.settings.accessibilityLabel", defaultValue: "Settings")
    }

    static var toggleRightSidebar: String {
        String(localized: "menu.view.toggleRightSidebar", defaultValue: "Toggle Right Sidebar")
    }

    /// Same tooltip as the right sidebar's own close button, with the
    /// current ⌘⌥B binding appended.
    static var toggleRightSidebarTooltip: String {
        KeyboardShortcutSettings.Action.toggleRightSidebar.tooltip(
            String(localized: "rightSidebar.toggle.tooltip", defaultValue: "Toggle right sidebar")
        )
    }
}

extension ShellXTitlebarModel {
    /// The placeholder, localized (the pure package keeps the English default).
    var localizedSearchPlaceholder: String {
        String(localized: "titlebar.search.placeholder", defaultValue: "Search sessions, machines, commands…")
    }
}

/// Titlebar accessory on the right edge hosting `ShellXTitlebarView`.
final class ShellXTitlebarAccessoryViewController: NSTitlebarAccessoryViewController {
    static let identifier = NSUserInterfaceItemIdentifier("shellx.titlebar.accessory")
    private let hostingView: NSHostingView<ShellXTitlebarView>
    private let rightSidebarToggle = ShellXRightSidebarToggleModel()
    private let resolveRightSidebarState: @MainActor (NSWindow?) -> FileExplorerState?
    private var contextsObserver: NSObjectProtocol?

    /// The right sidebar button toggles through the same path as ⌘⌥B and
    /// View ▸ Toggle Right Sidebar; tests inject both closures.
    init(
        resolveRightSidebarState: @escaping @MainActor (NSWindow?) -> FileExplorerState? = { window in
            guard let window else { return nil }
            return AppDelegate.shared?.contextForMainTerminalWindow(window, reindex: false)?.fileExplorerState
        },
        toggleRightSidebar: @escaping @MainActor (NSWindow?) -> Void = { window in
            _ = AppDelegate.shared?.toggleRightSidebarInActiveMainWindow(preferredWindow: window)
        }
    ) {
        self.resolveRightSidebarState = resolveRightSidebarState
        let containerView = TitlebarAccessoryContainerView()
        let toggleModel = rightSidebarToggle
        let host = NSHostingView(rootView: ShellXTitlebarView(
            shortcutText: Self.paletteShortcutText(),
            onSearch: { [weak containerView] in
                AppDelegate.shared?.requestCommandPaletteCommands(
                    preferredWindow: containerView?.window,
                    source: "titlebar.shellxSearch"
                )
            },
            onSettings: {
                AppDelegate.shared?.openPreferencesWindow(debugSource: "titlebar.shellxSettings")
            },
            showsShare: ShellXShareGate.isEnabled,
            onShare: { [weak containerView] in
                ShellXShareActions.shareSelectedWorkspace(in: containerView?.window)
            },
            rightSidebarToggle: toggleModel,
            onToggleRightSidebar: { [weak containerView] in
                toggleRightSidebar(containerView?.window)
            }
        ))
        hostingView = host
        super.init(nibName: nil, bundle: nil)
        view = containerView
        view.identifier = Self.identifier
        layoutAttribute = .right
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        containerView.frame = host.frame
        containerView.addSubview(host)
        preferredContentSize = size

        // The accessory is attached before the window registers its context,
        // so bind again whenever the window or the registered contexts change.
        containerView.onWindowChange = { [weak self] _ in self?.bindRightSidebarState() }
        contextsObserver = NotificationCenter.default.addObserver(
            forName: .mainWindowContextsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.bindRightSidebarState() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let contextsObserver {
            NotificationCenter.default.removeObserver(contextsObserver)
        }
    }

    private func bindRightSidebarState() {
        rightSidebarToggle.bind(to: resolveRightSidebarState(view.window))
    }

    /// The hosted view (tests read which buttons it shows).
    var rootView: ShellXTitlebarView { hostingView.rootView }

    /// The command palette's current shortcut (the user may rebind it).
    private static func paletteShortcutText() -> String {
        KeyboardShortcutSettings.Action.commandPalette.displayedShortcutString(
            for: KeyboardShortcutSettings.shortcut(for: .commandPalette)
        )
    }
}
