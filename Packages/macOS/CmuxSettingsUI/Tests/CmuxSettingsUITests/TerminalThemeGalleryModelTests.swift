import CmuxFoundation
import Foundation
import Testing
@testable import CmuxSettingsUI

/// Picking, previewing and reverting in the Settings terminal theme gallery,
/// against a real temporary config file.
@MainActor
@Suite("Terminal theme gallery model")
struct TerminalThemeGalleryModelTests {
    private final class ReloadLog {
        var phases: [TerminalThemeReloadPhase] = []
    }

    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cmux-theme-gallery-\(UUID().uuidString)", isDirectory: true)

    private func makeModel(
        existingConfig: String?,
        currentThemeValue: String?,
        prefersDark: Bool = false,
        themeDirectories: [URL] = [],
        defaultPair: CmuxTerminalThemePair = CmuxTerminalThemePair(light: "Catppuccin Latte", dark: "ShellX")
    ) throws -> (TerminalThemeGalleryModel, CmuxManagedThemeConfigFile, ReloadLog) {
        let file = CmuxManagedThemeConfigFile(url: root.appendingPathComponent("config.ghostty"))
        if let existingConfig {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try existingConfig.write(to: file.url, atomically: true, encoding: .utf8)
        }
        let log = ReloadLog()
        let model = TerminalThemeGalleryModel(
            context: TerminalThemeGalleryContext(
                configFile: file,
                themeDirectories: themeDirectories,
                readCurrentThemeValue: { currentThemeValue },
                prefersDarkAppearance: prefersDark,
                defaultPair: defaultPair
            ),
            reload: { log.phases.append($0) }
        )
        return (model, file, log)
    }

    @Test("A pick writes the managed block, keeps user lines, and previews")
    func pickWritesBlock() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, file, log) = try makeModel(
            existingConfig: "font-size = 13\n",
            currentThemeValue: "light:Catppuccin Latte,dark:Catppuccin Mocha",
            prefersDark: true
        )
        #expect(model.themeInUse == "Catppuccin Mocha")

        model.select("Nord", slot: .dark)

        #expect(model.selection == CmuxTerminalThemePair(light: "Catppuccin Latte", dark: "Nord"))
        #expect(model.themeInUse == "Nord")
        #expect(try file.readContents() == """
        font-size = 13

        # cmux themes start
        theme = light:Catppuccin Latte,dark:Nord
        # cmux themes end

        """)
        #expect(log.phases == [.preview])
        #expect(model.hasPendingChange)
    }

    @Test("The highlighted card is the theme the terminal shows, even from a pair")
    func highlightedThemeIsThemeInUse() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        // A pair written by `cmux themes set --light/--dark`, whose light side
        // is a dark theme: the terminal shows the dark side in dark mode.
        let (model, _, _) = try makeModel(
            existingConfig: nil,
            currentThemeValue: "light:Front End Delight,dark:Iceberg Light",
            prefersDark: true
        )

        #expect(model.themeInUse == "Iceberg Light")

        model.select("Front End Delight", slot: .dark)

        #expect(model.selection == CmuxTerminalThemePair(light: "Front End Delight", dark: "Front End Delight"))
        #expect(model.themeInUse == "Front End Delight")
    }

    @Test("Changing the app appearance moves the highlight to the side now shown")
    func appearanceChangeFollowsThemeInUse() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, _, _) = try makeModel(
            existingConfig: nil,
            currentThemeValue: "light:Violet Light,dark:3024 Night",
            prefersDark: false
        )
        #expect(model.themeInUse == "Violet Light")

        model.appearanceDidChange(prefersDark: true)

        #expect(model.slotInUse == .dark)
        #expect(model.themeInUse == "3024 Night")
    }

    @Test("A later gallery shows cached themes, then picks up theme files added since")
    func reloadPicksUpAddedThemes() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let themesDirectory = root.appendingPathComponent("themes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: themesDirectory, withIntermediateDirectories: true)
        try "background = #000000\n".write(to: themesDirectory.appendingPathComponent("Alpha"), atomically: true, encoding: .utf8)

        let (first, _, _) = try makeModel(existingConfig: nil, currentThemeValue: nil, themeDirectories: [themesDirectory])
        await first.load()
        #expect(first.themes.map(\.name) == ["Alpha"])

        try "background = #ffffff\n".write(to: themesDirectory.appendingPathComponent("Beta"), atomically: true, encoding: .utf8)
        let (second, _, _) = try makeModel(existingConfig: nil, currentThemeValue: nil, themeDirectories: [themesDirectory])
        await second.load()

        #expect(second.themes.map(\.name) == ["Alpha", "Beta"])
    }

    @Test("With no theme set, the first pick fills the other side with the default")
    func firstPickWithNoThemeFillsDefault() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, file, _) = try makeModel(existingConfig: nil, currentThemeValue: nil)

        model.select("TokyoNight", slot: .dark)

        #expect(try file.managedThemeValue() == "light:Catppuccin Latte,dark:TokyoNight")
    }

    @Test("A dark pick keeps the light side")
    func selectDarkKeepsLight() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, file, _) = try makeModel(existingConfig: nil, currentThemeValue: "light:Nord Light,dark:Abernathy")

        model.select("TokyoNight", slot: .dark)

        #expect(try file.managedThemeValue() == "light:Nord Light,dark:TokyoNight")
    }

    @Test("A light pick keeps the dark side")
    func selectLightKeepsDark() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, file, _) = try makeModel(existingConfig: nil, currentThemeValue: "light:Nord Light,dark:Abernathy")

        model.select("Rose Pine Dawn", slot: .light)

        #expect(try file.managedThemeValue() == "light:Rose Pine Dawn,dark:Abernathy")
    }

    @Test("A single dark theme stays the dark side")
    func singleDarkThemeIsDarkSide() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = try makeThemes([("Abernathy", "#000000"), ("Rose Pine Dawn", "#faf4ed")])
        let (model, file, _) = try makeModel(existingConfig: nil, currentThemeValue: "Abernathy", themeDirectories: [dir])
        await model.load()

        model.select("Rose Pine Dawn", slot: .light)

        #expect(try file.managedThemeValue() == "light:Rose Pine Dawn,dark:Abernathy")
    }

    @Test("A single light theme becomes the light side")
    func singleLightThemeIsLightSide() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = try makeThemes([("Nord", "#2e3440"), ("Rose Pine Dawn", "#faf4ed")])
        let (model, file, _) = try makeModel(existingConfig: nil, currentThemeValue: "Rose Pine Dawn", themeDirectories: [dir])
        await model.load()

        model.select("Nord", slot: .dark)

        #expect(try file.managedThemeValue() == "light:Rose Pine Dawn,dark:Nord")
    }

    @Test("Opening Settings writes nothing")
    func openingSettingsWritesNothing() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let original = "font-size = 13\n\n# cmux themes start\ntheme = Nord\n# cmux themes end\n"
        let dir = try makeThemes([("Nord", "#2e3440")])
        let (model, file, log) = try makeModel(existingConfig: original, currentThemeValue: "Nord", themeDirectories: [dir])
        let before = try Data(contentsOf: file.url)

        await model.load()
        _ = model.results
        model.refreshSelection()

        #expect(try Data(contentsOf: file.url) == before)
        #expect(log.phases.isEmpty)
    }

    @Test("Without a query each section lists its curated themes in order")
    func curatedWhenNoQuery() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = try makeThemes(Self.curatedDark.map { ($0, "#101010") } + Self.curatedLight.map { ($0, "#f5f5f5") } + [("Zenburn", "#3f3f3f")])
        let (model, _, _) = try makeModel(existingConfig: nil, currentThemeValue: nil, themeDirectories: [dir])
        await model.load()

        #expect(model.results.dark.map(\.name) == Self.curatedDark)
        #expect(model.results.light.map(\.name) == Self.curatedLight)
        #expect(Self.curatedDark == TerminalThemeCuration.dark)
        #expect(Self.curatedLight == TerminalThemeCuration.light)
    }

    @Test("A theme in use outside the curated set is still shown")
    func inUseOutsideCurationShown() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = try makeThemes([("Abernathy", "#000000"), ("Nord", "#2e3440")])
        let (model, _, _) = try makeModel(existingConfig: nil, currentThemeValue: "light:Nord Light,dark:Abernathy", themeDirectories: [dir])
        await model.load()

        #expect(model.results.dark.map(\.name).contains("Abernathy"))
    }

    @Test("A query shows every matching theme in its section")
    func queryShowsAll() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = try makeThemes([
            ("Gruvbox Dark", "#282828"), ("Gruvbox Dark Hard", "#1d2021"), ("Gruvbox Light", "#fbf1c7"),
            ("Gruvbox Material", "#282828"), ("Nord", "#2e3440"),
        ])
        let (model, _, _) = try makeModel(existingConfig: nil, currentThemeValue: nil, themeDirectories: [dir])
        await model.load()
        model.query = "gruvbox"

        #expect(model.results.dark.map(\.name) == ["Gruvbox Dark", "Gruvbox Dark Hard", "Gruvbox Material"])
        #expect(model.results.light.map(\.name) == ["Gruvbox Light"])
    }

    @Test("Badges follow the slots a theme fills")
    func badgesFollowSlots() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (both, _, _) = try makeModel(existingConfig: nil, currentThemeValue: "light:X,dark:X")
        #expect(both.badges(for: "X") == [.light, .dark])
        let (split, _, _) = try makeModel(existingConfig: nil, currentThemeValue: "light:A,dark:B")
        #expect(split.badges(for: "A") == [.light])
        #expect(split.badges(for: "B") == [.dark])
        #expect(split.badges(for: "C").isEmpty)
    }

    @Test("Picking the theme already in effect writes nothing")
    func pickingCurrentThemeIsNoOp() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, file, log) = try makeModel(existingConfig: nil, currentThemeValue: "light:Catppuccin Latte,dark:Nord")

        model.select("Nord", slot: .dark)

        #expect(try file.readContents() == nil)
        #expect(log.phases.isEmpty)
        #expect(!model.hasPendingChange)
    }

    @Test("Revert restores the theme from before the first of several picks")
    func revertRestoresSnapshot() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let original = "font-size = 13\n\n# cmux themes start\ntheme = Nord\n# cmux themes end\n"
        let (model, file, log) = try makeModel(existingConfig: original, currentThemeValue: "Nord")

        model.select("Rose Pine Dawn", slot: .light)
        model.select("Rose Pine", slot: .dark)
        model.revert()

        #expect(try file.readContents() == original)
        #expect(model.selection == CmuxTerminalThemePair(light: "Catppuccin Latte", dark: "Nord"))
        #expect(!model.hasPendingChange)
        #expect(log.phases == [.preview, .preview, .final])
    }

    @Test("Revert only touches the theme block, keeping edits made since the pick")
    func revertKeepsLaterEdits() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, file, _) = try makeModel(existingConfig: "font-size = 13\n", currentThemeValue: nil)

        model.select("Nord", slot: .dark)
        try (try file.readContents()! + "cursor-style = bar\n").write(to: file.url, atomically: true, encoding: .utf8)
        model.revert()

        #expect(try file.readContents() == "font-size = 13\n\ncursor-style = bar\n")
    }

    @Test("Revert restores a pair cmux themes wrote after Settings opened")
    func pickReadsCurrentBlock() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, file, _) = try makeModel(
            existingConfig: nil,
            currentThemeValue: "light:Catppuccin Latte,dark:Catppuccin Mocha"
        )

        // `cmux themes set --dark Dracula` from a terminal while Settings is open.
        try file.write(rawThemeValue: "light:Catppuccin Latte,dark:Dracula")
        model.select("Nord Light", slot: .light)
        #expect(try file.managedThemeValue() == "light:Nord Light,dark:Dracula")

        model.revert()
        #expect(try file.managedThemeValue() == "light:Catppuccin Latte,dark:Dracula")
    }

    @Test("Revert removes a config file the gallery created")
    func revertRemovesCreatedFile() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, file, _) = try makeModel(existingConfig: nil, currentThemeValue: nil)

        model.select("Nord", slot: .dark)
        model.revert()

        #expect(try file.readContents() == nil)
    }

    private static let curatedDark = [
        "ShellX", "Catppuccin Mocha", "iTerm2 Solarized Dark", "GitHub Dark Default", "TokyoNight", "Rose Pine",
        "Gruvbox Dark", "Everforest Dark Hard", "Atom One Dark", "Nord", "Ayu Mirage", "Kanagawa Wave",
    ]
    private static let curatedLight = [
        "Catppuccin Latte", "iTerm2 Solarized Light", "GitHub Light Default", "TokyoNight Day", "Rose Pine Dawn",
        "Gruvbox Light", "Everforest Light Med", "Atom One Light", "Nord Light", "Ayu Light", "Kanagawa Lotus", "One Half Light",
    ]

    /// Writes one theme file per `(name, background)` into a fresh directory.
    private func makeThemes(_ items: [(String, String)]) throws -> URL {
        let dir = root.appendingPathComponent("themes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, background) in items {
            try "background = \(background)\n".write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return dir
    }
}
