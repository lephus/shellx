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
    /// The scheme this bundle registered for its links (`shellx`, or `shellx-dev` for dev builds).
    let urlScheme: String
    private let bundle: Bundle
    private let processEnvironment: [String: String]

    /// - Parameters:
    ///   - bundle: The app bundle; its id picks the release or dev folders and launchd labels.
    ///   - home: The user's home folder.
    ///   - processEnvironment: The app's environment, for `SHELLX_CLAUDE_PATH` and `PATH`.
    init(bundle: Bundle, home: URL, processEnvironment: [String: String]) {
        self.bundle = bundle
        urlScheme = ShellXAppURLScheme(infoDictionary: bundle.infoDictionary).scheme
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
        let prompt = Self.creatorSystemPrompt(bundle: bundle)
        let flowRules = Self.bundledText("flow-rules", bundle: bundle) ?? ""
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
                // One run path: the same command launchd calls; it keeps running after the grace.
                await ShellXRoutineRunLauncher(cliPath: cliPath).start(id)
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
            },
            flowDrawer: { markdown in
                guard let launch = await claudePath.launch() else {
                    throw ShellXFlowDrawError.failed(ShellXResolvingCreatorLauncher.ClaudeMissing().errorDescription ?? "")
                }
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                let drawer = ShellXFlowDrawer(
                    launcher: ShellXClaudeProcess(
                        executable: launch.path,
                        environment: launch.environment,
                        timeLimit: .seconds(120)
                    ),
                    rules: flowRules,
                    workingDirectory: scratch
                )
                return try await drawer.draw(skillMarkdown: markdown)
            }
        )
    }

    /// The bundled creator prompt (adapted from Anthropic's skill-creator, Apache-2.0; the
    /// license ships beside it in `shellx-automations/`), with the flowchart rules filled in.
    static func creatorSystemPrompt(bundle: Bundle) -> String {
        guard let template = bundledText("creator-system-prompt", bundle: bundle) else {
            return "You help the user create a Claude Code skill, workflow or cronjob for ShellX."
        }
        return composeCreatorPrompt(template: template, flowRules: bundledText("flow-rules", bundle: bundle) ?? "")
    }

    /// `template` with `{{SHELLX_FLOW_RULES}}` replaced by the text of `flow-rules.md`.
    nonisolated static func composeCreatorPrompt(template: String, flowRules: String) -> String {
        template.replacingOccurrences(of: "{{SHELLX_FLOW_RULES}}", with: flowRules)
    }

    /// A Markdown file of the bundle's `shellx-automations` folder.
    private static func bundledText(_ name: String, bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: name, withExtension: "md", subdirectory: "shellx-automations") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
