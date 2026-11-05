import CmuxFoundation
import Foundation
import Observation
import SwiftUI

/// Drives the Settings terminal theme gallery.
///
/// Picking a card writes the managed `# cmux themes` block through the same
/// ``CmuxManagedThemeConfigFile`` writer `cmux themes` uses, replacing only the
/// side of the light/dark pair its section stands for, then asks the host
/// to reload so terminals preview it live. The first pick remembers the
/// block's previous theme value; ``revert()`` writes only that value back, so
/// other edits to the file made in the meantime survive.
@MainActor
@Observable
final class TerminalThemeGalleryModel {
    /// The appearance whose theme a pick replaces.
    enum Slot: Hashable, CaseIterable, Sendable {
        case light
        case dark
    }

    /// One theme file with the colors its card renders.
    struct Theme: Identifiable, Equatable, Sendable {
        let name: String
        let colors: GhosttyThemeColors
        /// Card colors resolved once at load, so scrolling the gallery never
        /// converts hex components while cards come into view.
        let preview: PreviewColors
        var id: String { name }

        init(name: String, colors: GhosttyThemeColors) {
            self.name = name
            self.colors = colors
            self.preview = PreviewColors(colors)
        }
    }

    /// The SwiftUI colors a theme card draws.
    struct PreviewColors: Equatable, Sendable {
        let background: Color?
        let foreground: Color?
        let cursor: Color?
        let palette: [Color?]

        init(_ colors: GhosttyThemeColors) {
            func color(_ rgb: GhosttyThemeRGB?) -> Color? {
                rgb.map { Color(.sRGB, red: Double($0.red) / 255, green: Double($0.green) / 255, blue: Double($0.blue) / 255, opacity: 1) }
            }
            background = color(colors.background)
            foreground = color(colors.foreground)
            cursor = color(colors.cursor)
            palette = colors.palette.map(color)
        }
    }

    /// The cards shown for a query, one list per section.
    struct Results: Equatable {
        /// Themes with a dark background (unknown counts as dark).
        let dark: [Theme]
        /// Themes with a light background.
        let light: [Theme]

        /// Every card of a section.
        func themes(for slot: Slot) -> [Theme] { slot == .dark ? dark : light }

        /// Whether no card matched.
        var isEmpty: Bool { dark.isEmpty && light.isEmpty }
    }

    /// The managed block's theme before the first pick (`nil`: no block).
    private struct Snapshot {
        let managedThemeValue: String?
    }

    @ObservationIgnored private let context: TerminalThemeGalleryContext
    @ObservationIgnored private let reload: @MainActor (TerminalThemeReloadPhase) -> Void
    @ObservationIgnored private var snapshot: Snapshot?
    @ObservationIgnored private let block = CmuxManagedThemeBlock()

    private(set) var themes: [Theme] = []
    private(set) var isLoaded = false
    private(set) var selection: CmuxTerminalThemePair
    private(set) var hasPendingChange = false
    private(set) var writeFailed = false
    var query = ""
    /// The appearance whose theme the terminal shows now. Orders the cards
    /// (its appearance first) and picks the highlighted card when the config
    /// still holds a light/dark pair written elsewhere.
    private(set) var slotInUse: Slot

    init(
        context: TerminalThemeGalleryContext,
        reload: @escaping @MainActor (TerminalThemeReloadPhase) -> Void
    ) {
        self.context = context
        self.reload = reload
        selection = context.defaultPair
        slotInUse = context.prefersDarkAppearance ? .dark : .light
        selection = currentPair()
    }

    /// Last successful parse per search directories. A new model shows it
    /// at once, so reopening Themes lays out the full gallery in its first
    /// pass, then re-reads the directories so added or edited theme files
    /// still appear. An empty result is never cached.
    private static var themeCache: [[URL]: [Theme]] = [:]

    /// Shows the cached themes at once when there are any, then reads and
    /// parses every theme file off the main actor and keeps the fresh list.
    func load() async {
        guard !isLoaded else { return }
        let directories = context.themeDirectories
        if let cached = Self.themeCache[directories] {
            themes = cached
            isLoaded = true
        }
        let loaded = await Task.detached(priority: .userInitiated) {
            Self.loadThemes(in: directories)
        }.value
        if !loaded.isEmpty {
            Self.themeCache[directories] = loaded
        }
        if loaded != themes {
            themes = loaded
        }
        isLoaded = true
    }

    /// Follows an app appearance change while Settings is open, so the
    /// highlighted card and the group order track the theme on screen when
    /// the config still holds a light/dark pair.
    func appearanceDidChange(prefersDark: Bool) {
        let slot: Slot = prefersDark ? .dark : .light
        guard slot != slotInUse else { return }
        slotInUse = slot
        refreshSelection()
    }

    /// The cards for the current query.
    var results: Results {
        let inUse = [selection.light, selection.dark].compactMap { $0 }
        return Self.results(in: themes, query: query, inUse: inUse)
    }

    /// The theme the terminal shows now: the highlighted card.
    var themeInUse: String? { selectedName(for: slotInUse) }

    /// The theme in effect for `slot`, or `nil` when it uses Ghostty's defaults.
    func selectedName(for slot: Slot) -> String? {
        switch slot {
        case .light: selection.light
        case .dark: selection.dark
        }
    }

    /// Re-reads the theme in effect, picking up changes made outside Settings.
    func refreshSelection() {
        selection = currentPair()
    }

    /// Uses `name` for `slot`'s appearance only, keeps the other side as it
    /// is, and live-previews the result. With no theme set anywhere, the
    /// other side is filled with the default it currently resolves to.
    func select(_ name: String, slot: Slot) {
        let current: CmuxTerminalThemePair
        let managedValue: String?
        do {
            managedValue = try context.configFile.managedThemeValue()
            current = effectivePair(rawValue: managedValue ?? context.readCurrentThemeValue())
        } catch {
            writeFailed = true
            return
        }
        selection = current
        var next = current
        switch slot {
        case .light: next.light = name
        case .dark: next.dark = name
        }
        guard next != current,
              let rawValue = block.encodedThemeValue(light: next.light, dark: next.dark) else {
            return
        }
        do {
            try context.configFile.write(rawThemeValue: rawValue)
        } catch {
            writeFailed = true
            return
        }
        if snapshot == nil {
            snapshot = Snapshot(managedThemeValue: managedValue)
        }
        selection = next
        hasPendingChange = true
        writeFailed = false
        reload(.preview)
    }

    /// Puts the managed block's theme back as it was before the first pick,
    /// removing the block if there was none. The rest of the file is untouched.
    func revert() {
        guard let snapshot else { return }
        do {
            try context.configFile.setManagedThemeValue(snapshot.managedThemeValue)
        } catch {
            writeFailed = true
            return
        }
        self.snapshot = nil
        selection = currentPair()
        hasPendingChange = false
        writeFailed = false
        reload(.final)
    }

    /// The effective pair: the managed block when present, otherwise the
    /// loaded Ghostty config's theme, otherwise the defaults.
    private func currentPair() -> CmuxTerminalThemePair {
        let managedValue = try? context.configFile.managedThemeValue()
        return effectivePair(rawValue: managedValue ?? context.readCurrentThemeValue())
    }

    /// Reads a raw `theme` value. A plain name fills both sides; a side the
    /// value leaves unnamed takes the default.
    private func effectivePair(rawValue: String?) -> CmuxTerminalThemePair {
        let pair = block.themePair(fromRawValue: rawValue)
        return CmuxTerminalThemePair(light: pair.light ?? context.defaultPair.light, dark: pair.dark ?? context.defaultPair.dark)
    }

    nonisolated static func loadThemes(in directories: [URL]) -> [Theme] {
        GhosttyThemeCatalog(directories: directories).entries().compactMap { entry in
            guard let contents = try? String(contentsOf: entry.url, encoding: .utf8) else { return nil }
            return Theme(name: entry.name, colors: GhosttyThemeColors(parsing: contents))
        }
    }

    /// The cards per section. With an empty query each section lists its
    /// curated themes in order, then any theme in use that the list lacks.
    /// With a query, every matching theme in catalog order. A theme goes to
    /// the dark section unless its background is light.
    nonisolated static func results(in themes: [Theme], query: String, inUse: [String]) -> Results {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func isDark(_ theme: Theme) -> Bool { theme.colors.isDark ?? true }
        if !query.isEmpty {
            let matches = themes.filter { $0.name.localizedCaseInsensitiveContains(query) }
            return Results(dark: matches.filter(isDark), light: matches.filter { !isDark($0) })
        }
        let byName = Dictionary(themes.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var dark = TerminalThemeCuration.dark.compactMap { byName[$0] }
        var light = TerminalThemeCuration.light.compactMap { byName[$0] }
        for name in inUse {
            guard let theme = themes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
                  !dark.contains(theme), !light.contains(theme) else { continue }
            if isDark(theme) { dark.append(theme) } else { light.append(theme) }
        }
        return Results(dark: dark, light: light)
    }
}
