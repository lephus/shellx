import AppKit
import ShellXBrand
import ShellXIcons
import SwiftUI

/// ShellX title bar, right side (spec §7.1): the search field look-alike with
/// its shortcut key cap, and the settings button. The sidebar toggle and the
/// notifications bell stay in the existing left accessory
/// (`TitlebarControlsView`), whose bell badge draws `ShellXTitlebarModel`.
/// Flat colors only (`ShellXPalette`), no gradients or shadows.
struct ShellXTitlebarView: View {
    let shortcutText: String
    let onSearch: () -> Void
    let onSettings: () -> Void

    @State private var searchHover = false
    @State private var settingsHover = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSearch) {
                HStack(spacing: 6) {
                    ShellXIcon.image("magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(ShellXPalette.muted.color)
                    Text(ShellXTitlebarModel(unreadCount: 0).localizedSearchPlaceholder)
                        .font(.system(size: 12))
                        .foregroundColor(ShellXPalette.muted.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(shortcutText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(ShellXPalette.muted.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(ShellXPalette.border.color, lineWidth: 1)
                        )
                }
                .padding(.horizontal, 8)
                .frame(width: 280, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(searchHover ? ShellXPalette.raise.color : ShellXPalette.panel.color)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(searchHover ? ShellXPalette.primaryLine.color : ShellXPalette.border.color, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { searchHover = $0 }
            .accessibilityIdentifier("titlebarControl.shellxSearch")
            .accessibilityLabel(ShellXTitlebarModel(unreadCount: 0).localizedSearchPlaceholder)
            .help(ShellXTitlebarModel(unreadCount: 0).localizedSearchPlaceholder)

            Button(action: onSettings) {
                ShellXIcon.image("gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(settingsHover ? ShellXPalette.textHi.color : ShellXPalette.text.color)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(settingsHover ? ShellXPalette.raise.color : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { settingsHover = $0 }
            .accessibilityIdentifier("titlebarControl.shellxSettings")
            .accessibilityLabel(ShellXTitlebarStrings.settings)
            .help(ShellXTitlebarStrings.settings)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
    }
}

enum ShellXTitlebarStrings {
    static var settings: String {
        String(localized: "titlebar.settings.accessibilityLabel", defaultValue: "Settings")
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

    init() {
        let containerView = TitlebarAccessoryContainerView()
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The command palette's current shortcut (the user may rebind it).
    private static func paletteShortcutText() -> String {
        KeyboardShortcutSettings.Action.commandPalette.displayedShortcutString(
            for: KeyboardShortcutSettings.shortcut(for: .commandPalette)
        )
    }
}
