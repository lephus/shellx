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

    @Test("With no theme set, a light pick keeps ShellX dark, which ships as a real theme with a dark card")
    func firstLightPickKeepsShippedShellXDark() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        // The themes directory the app bundles, not a fixture: Ghostty must
        // find `dark:ShellX` there once the pair is written.
        let bundledThemes = Self.repoRoot.appendingPathComponent("Resources/ghostty/themes", isDirectory: true)
        let (model, file, _) = try makeModel(existingConfig: nil, currentThemeValue: nil, themeDirectories: [bundledThemes])

        model.select("Rose Pine Dawn", slot: .light)

        #expect(try file.managedThemeValue() == "light:Rose Pine Dawn,dark:ShellX")
        #expect(FileManager.default.fileExists(atPath: bundledThemes.appendingPathComponent("ShellX").path))
        await model.load()
        #expect(model.results.dark.map(\.name).contains("ShellX"))
    }

    @Test("An older gallery's dark light:X,dark:X shows Catppuccin Latte for Light without writing, and a dark pick keeps it")
    func singleDarkThemeGetsDefaultLight() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let bundledThemes = Self.repoRoot.appendingPathComponent("Resources/ghostty/themes", isDirectory: true)
        let original = "font-size = 13\n\n# cmux themes start\ntheme = light:Abernathy,dark:Abernathy\n# cmux themes end\n"
        let (model, file, log) = try makeModel(
            existingConfig: original,
            currentThemeValue: "light:Abernathy,dark:Abernathy",
            themeDirectories: [bundledThemes]
        )

        #expect(model.selection == CmuxTerminalThemePair(light: "Catppuccin Latte", dark: "Abernathy"))
        #expect(model.themeInUse == "Catppuccin Latte")
        #expect(try file.readContents() == original)
        #expect(log.phases.isEmpty)

        model.select("Nord", slot: .dark)

        #expect(try file.managedThemeValue() == "light:Catppuccin Latte,dark:Nord")
    }

    @Test("A light theme on both sides shows ShellX for Dark")
    func singleLightThemeGetsDefaultDark() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let bundledThemes = Self.repoRoot.appendingPathComponent("Resources/ghostty/themes", isDirectory: true)
        let (model, _, _) = try makeModel(
            existingConfig: nil,
            currentThemeValue: "Rose Pine Dawn",
            themeDirectories: [bundledThemes]
        )

        #expect(model.selection == CmuxTerminalThemePair(light: "Rose Pine Dawn", dark: "ShellX"))
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

    @Test("Without a query each section lists every theme, in catalog order")
    func everyThemeWhenNoQuery() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = try makeThemes([
            ("Abernathy", "#111416"), ("Catppuccin Latte", "#eff1f5"), ("Nord", "#2e3440"),
            ("Rose Pine Dawn", "#faf4ed"), ("Zenburn", "#3f3f3f"),
        ])
        let (model, _, _) = try makeModel(existingConfig: nil, currentThemeValue: nil, themeDirectories: [dir])
        await model.load()

        #expect(model.results.dark.map(\.name) == ["Abernathy", "Nord", "Zenburn"])
        #expect(model.results.light.map(\.name) == ["Catppuccin Latte", "Rose Pine Dawn"])
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
        #expect(model.selection == CmuxTerminalThemePair(light: "Nord", dark: "Nord"))
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

    /// Tests/CmuxSettingsUITests/<file> -> package -> macOS -> Packages -> repo.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

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
