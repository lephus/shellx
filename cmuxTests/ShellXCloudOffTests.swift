import CmuxCloud
import CmuxSettings
import Darwin
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Manaflow Cloud (sign-in, accounts, Cloud machines, billing, Pro, CodeRouter)
/// has no entry point in ShellX, and device mirroring waits for Wave 2's
/// `remoteMachines`. Every test that touches defaults uses a private suite it
/// removes, never the test host's `.standard`.
struct ShellXCloudOffTests {
    private static func withPrivateDefaults<T>(_ body: (UserDefaults) throws -> T) rethrows -> T {
        let name = "ShellXCloudOffTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        return try body(defaults)
    }

    @Test func cloudIsOff() {
        Self.withPrivateDefaults { defaults in
            // Even with the first-use opt-in written, Cloud stays off.
            defaults.set(true, forKey: BetaFeaturesCatalogSection().cloudMachines.userDefaultsKey)
            let policy = ManagedDevicePolicy(defaults: defaults)
            #expect(CloudMachinesFeature.isAvailable(policy: policy) == false)
            #expect(CloudMachinesFeature.isEnabled(defaults: defaults, policy: policy) == false)
            #expect(DevicesFeature.isAvailable(defaults: defaults, policy: policy, cloudEnabled: true) == false)
            #expect(DevicesFeature.isEnabled(defaults: defaults, policy: policy, cloudEnabled: true) == false)
            for version in CloudWelcomeWindowController.campaignAppVersions {
                #expect(CloudWelcomeWindowController.shouldPresentAutomatically(
                    defaults: defaults,
                    appVersion: version,
                    policy: policy
                ) == false)
            }
        }
    }

    @Test func deviceMirroringIsParkedBehindRemoteMachines() {
        Self.withPrivateDefaults { defaults in
            defaults.set(true, forKey: MobileHostService.listeningEnabledDefaultsKey)
            defaults.set(true, forKey: PresenceSettings.enabledKey)
            #expect(MobileHostService.isListeningEnabled(defaults: defaults, buildFlavor: .current) == false)
            #expect(PresenceSettings.isEnabled(defaults: defaults) == false)
            #expect(RightSidebarMode.machines.isAvailable(feedEnabled: true, machinesEnabled: true) == false)
            #expect(!RightSidebarMode.availableModes(feedEnabled: true, machinesEnabled: true).contains(.machines))
        }
    }

    @Test func noCloudShortcutsOrPaletteCommands() {
        func isCommandY(_ stroke: ShortcutStroke) -> Bool {
            stroke.key.lowercased() == "y" && stroke.command && !stroke.option && !stroke.control
        }
        let packageDefaults = ShortcutAction.allCases.compactMap(\.defaultStroke)
        #expect(!packageDefaults.contains(where: isCommandY))
        let appDefaults = KeyboardShortcutSettings.Action.allCases.map(\.defaultShortcut.first)
        #expect(!appDefaults.contains(where: isCommandY))
        let actionIDs = Set(KeyboardShortcutSettings.Action.allCases.map(\.rawValue))
            .union(ShortcutAction.allCases.map(\.rawValue))
        #expect(!actionIDs.contains("newCloudWorkspace"))
        #expect(!actionIDs.contains("newCloudMachine"))

        #expect(ContentView.commandPaletteAuthCommandContributions().isEmpty)
        #expect(ContentView.commandPaletteCloudCommandContributions(isAuthenticated: true).isEmpty)
        #expect(ContentView.commandPaletteProCommandContributions().isEmpty)
    }

    @Test func footerHasNoAccountCloudOrPro() {
        for mode in [WorkspacePresentationModeSettings.Mode.standard, .minimal] {
            #expect(!SidebarFooterPresentationPolicy.isVisible(.account, presentationMode: mode))
            #expect(!SidebarFooterPresentationPolicy.isVisible(.cloud, presentationMode: mode))
            #expect(!SidebarFooterPresentationPolicy.isVisible(.upgrade, presentationMode: mode))
            #expect(!SidebarFooterPresentationPolicy.isVisible(.mobileConnect, presentationMode: mode))
        }
        #expect(SidebarFooterPresentationPolicy.isVisible(.help, presentationMode: .standard))
        #expect(!SidebarFooterPresentationPolicy.isUpgradeVisible(isProActive: false, isProStatusKnown: true))
    }

    @MainActor
    @Test func noUpgradeOffer() {
        #expect(ProUpgradePresenter.currentUpgradeOffer == nil)
    }

    @Test func cloudSocketMethodsAreRefusedBeforeAnyHandler() throws {
        for method in ["auth.begin_sign_in", "auth.sign_in_url", "auth.status", "auth.team.list",
                       "vm.list", "vm.billing_checkout", "remotes.list", "aiAccounts.upload",
                       "coderouter.machines", "coderouter.handoff.complete"] {
            let response = try #require(
                TerminalController.shellXUnavailableServiceResponse(method: method, id: 7),
                "\(method) must be refused"
            )
            let object = try #require(
                try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any]
            )
            let error = try #require(object["error"] as? [String: Any], "\(method): \(response)")
            #expect(error["code"] as? String == "not_available", "\(method)")
            #expect((error["message"] as? String)?.contains("ShellX") == true, "\(method)")
        }
        #expect(TerminalController.shellXUnavailableServiceResponse(method: "auth.login", id: 1) == nil)
        #expect(TerminalController.shellXUnavailableServiceResponse(method: "system.ping", id: 1) == nil)
    }

    /// The CLI refuses each Cloud verb before it looks for the app's socket.
    @Test func cloudCLIVerbsAreRefusedWithoutTheSocket() throws {
        let cliPath = try BundledCLITestSupport.bundledCLIPath(for: BundledCLILinkageTests.self)
        let missingSocket = FileManager.default.temporaryDirectory
            .appendingPathComponent("shellx-cloud-off-\(UUID().uuidString).sock").path
        let cases: [([String], String)] = [
            (["auth", "login"], "Cloud is not available in ShellX."),
            (["auth", "status"], "Cloud is not available in ShellX."),
            (["login"], "Cloud is not available in ShellX."),
            (["logout"], "Cloud is not available in ShellX."),
            (["vm", "ls"], "Cloud is not available in ShellX."),
            (["cloud", "new"], "Cloud is not available in ShellX."),
            (["vm", "tui", "machine"], "Cloud is not available in ShellX."),
            (["billing", "checkout", "--plan", "pro"], "Cloud is not available in ShellX."),
            (["vpn", "status"], "Cloud is not available in ShellX."),
            (["remotes", "list"], "Cloud is not available in ShellX."),
            (["ai-accounts", "list"], "Cloud is not available in ShellX."),
            (["coderouter", "status"], "CodeRouter is not available in ShellX."),
            (["coderouter", "machines"], "CodeRouter is not available in ShellX."),
        ]
        for (arguments, message) in cases {
            let result = Self.run(cliPath: cliPath, arguments: arguments, socketPath: missingSocket)
            let label = Comment(rawValue: "\(arguments): \(result.stderr)")
            #expect(result.status == 127, label)
            #expect(result.stdout.isEmpty, label)
            #expect(result.stderr.contains(message), label)
            #expect(!result.stderr.contains("cmux.com"), label)
        }
    }

    private static func run(
        cliPath: String,
        arguments: [String],
        socketPath: String
    ) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("CMUX_") && !$0.key.hasPrefix("CMUXD_")
        }
        environment["CMUX_SOCKET_PATH"] = socketPath
        environment["CMUX_CLI_SENTRY_DISABLED"] = "1"
        environment["AppleLanguages"] = "(en)"
        environment["AppleLocale"] = "en_US"
        process.environment = environment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return (126, "", error.localizedDescription)
        }
        if finished.wait(timeout: .now() + 10) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 2)
            return (124, "", "timed out")
        }
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, out, err)
    }
}
