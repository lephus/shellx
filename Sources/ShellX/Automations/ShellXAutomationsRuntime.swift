import Foundation
import ShellXAutomations

/// The Automations object graph for one app bundle: where automations live, the store,
/// the launchd scheduler, the library the sidebar reads, and the creator's Claude Code.
///
/// Built once by `AppDelegate` at launch. Each Automations panel gets its own controller
/// from ``makeController(terminalOpener:fileOpener:)``.
@MainActor
final class ShellXAutomationsRuntime {
    let environment: ShellXAutomationEnvironment
    let store: ShellXAutomationStore
    let scheduler: ShellXLaunchAgentScheduler
    let library: ShellXAutomationsLibrary
    let claudePath: ShellXClaudePathCache
    private let bundle: Bundle
    private let processEnvironment: [String: String]

    /// - Parameters:
    ///   - bundle: The app bundle; its id picks the release or dev folders and launchd labels.
    ///   - home: The user's home folder.
    ///   - processEnvironment: The app's environment, for `SHELLX_CLAUDE_PATH` and `PATH`.
    init(bundle: Bundle, home: URL, processEnvironment: [String: String]) {
        self.bundle = bundle
        self.processEnvironment = processEnvironment
        let bundleURL = bundle.bundleURL
        environment = ShellXAutomationEnvironment(
            bundleIdentifier: bundle.bundleIdentifier ?? ShellXAutomationEnvironment.releaseBundleIdentifier,
            home: home,
            cliPath: bundleURL.appending(path: "Contents/Resources/bin/shellx").path,
            notifierAppPath: bundleURL.appending(path: "Contents/Library/ShellX Notifier.app").path
        )
        store = ShellXAutomationStore(environment: environment, trasher: ShellXFileManagerTrasher(), now: { Date() })
        scheduler = ShellXLaunchAgentScheduler(
            environment: environment,
            launchctl: ShellXProcessLaunchctl(),
            userID: getuid()
        )
        library = ShellXAutomationsLibrary(store: store, scheduler: scheduler, changeStampURL: environment.changeStampURL)
        let resolver = ShellXClaudeExecutableResolver(
            environment: processEnvironment,
            home: home,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
            loginShellLookup: { ShellXLoginShellClaudeLookup()() }
        )
        claudePath = ShellXClaudePathCache(
            resolver: resolver,
            environment: .live(inherited: processEnvironment, home: home)
        )
    }

    /// A controller for one Automations panel.
    ///
    /// - Parameters:
    ///   - terminalOpener: Opens a terminal that resumes the automation's last Claude Code session.
    ///   - fileOpener: Opens a file in the user's editor.
    func makeController(
        terminalOpener: @escaping (ShellXAutomation) -> Void,
        fileOpener: @escaping (URL) -> Void
    ) -> ShellXAutomationsController {
        let cliPath = environment.cliPath
        let launcher = ShellXResolvingCreatorLauncher(claude: claudePath)
        let prompt = creatorSystemPrompt()
        let scratch = environment.automationsRoot.appending(path: ".creator", directoryHint: .isDirectory)
        let localeIdentifier = Locale.current.identifier
        let store = store
        let claudePath = claudePath
        return ShellXAutomationsController(
            library: library,
            store: store,
            scheduler: scheduler,
            creatorFactory: { _ in
                ShellXCreatorSession(
                    launcher: launcher,
                    systemPrompt: prompt,
                    workingDirectory: scratch,
                    localeIdentifier: localeIdentifier,
                    cliPath: cliPath
                )
            },
            runLauncher: { id in
                // One run path: the same command launchd calls, detached from the app.
                Task.detached(priority: .utility) {
                    _ = try? await ShellXArgvProcess().run([cliPath, "routine", "run", id, "--trigger", "manual"])
                }
            },
            terminalOpener: terminalOpener,
            fileOpener: fileOpener,
            makeValidator: { _ in
                let names = Set(((try? await store.list()) ?? []).map(\.name))
                let claudeAvailable = await claudePath.path() != nil
                return ShellXAutomationValidator(
                    existingNames: names,
                    directoryExists: { path in
                        // Runs start in this exact path, so `~` and relative paths do not count.
                        var isDirectory: ObjCBool = false
                        return path.hasPrefix("/")
                            && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                            && isDirectory.boolValue
                    },
                    claudeAvailable: claudeAvailable
                )
            }
        )
    }

    /// The bundled creator prompt (adapted from Anthropic's skill-creator, Apache-2.0; the
    /// license ships beside it in `shellx-automations/`).
    private func creatorSystemPrompt() -> String {
        guard let url = bundle.url(forResource: "creator-system-prompt", withExtension: "md", subdirectory: "shellx-automations"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "You help the user create a Claude Code skill, workflow or cronjob for ShellX."
        }
        return text
    }
}
