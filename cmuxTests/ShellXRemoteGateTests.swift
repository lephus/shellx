@testable import CmuxComputerUse
import Foundation
import ShellXBrand
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// ShellX 1.5.1 serves phones (sign-in, `machines.register`, the ShellX Link host and phone pairing) while the
/// remote machines UI and features stay off.
struct ShellXRemoteGateTests {
    @Test func phonePairingAloneServesPhonesWithoutRemoteMachines() {
        #expect(ShellXRemoteGate.servesPhones(remoteMachines: false, phonePairing: true, environment: [:]))
        #expect(!ShellXRemoteGate.isEnabled(remoteMachines: false, environment: [:]))
    }

    @Test func bothSwitchesOffServeNothing() {
        #expect(!ShellXRemoteGate.servesPhones(remoteMachines: false, phonePairing: false, environment: [:]))
    }

    @Test func remoteMachinesAlsoServePhones() {
        #expect(ShellXRemoteGate.isEnabled(remoteMachines: true, environment: [:]))
        #expect(ShellXRemoteGate.servesPhones(remoteMachines: true, phonePairing: false, environment: [:]))
    }

    /// DEBUG builds launched with `SHELLX_REMOTE_MACHINES=1` turn on remote machines, and with them phones.
    @Test func debugLaunchOverrideTurnsOnBoth() {
        let environment = [ShellXRemoteGate.remoteMachinesEnvironmentKey: "1"]
        #expect(ShellXRemoteGate.isEnabled(remoteMachines: false, environment: environment))
        #expect(ShellXRemoteGate.servesPhones(remoteMachines: false, phonePairing: false, environment: environment))
    }

    // MARK: Launch

    /// A process hosting tests never starts the remote service: it would sign in and register this Mac with the
    /// production relay.
    @Test func processHostingTestsNeverStartsTheRemoteService() {
        // Evaluated first, so a failure does not print this process's environment.
        let startsInThisProcess = ShellXRemoteGate.startsAtLaunch(environment: ProcessInfo.processInfo.environment)
        #expect(!startsInThisProcess)
        let xctest = ["XCTestConfigurationFilePath": "/tmp/cmuxTests.xctestconfiguration"]
        #expect(!ShellXRemoteGate.startsAtLaunch(servesPhones: true, environment: xctest))
    }

    @Test func appStartsTheRemoteServiceWhileItServesPhones() {
        #expect(ShellXRemoteGate.startsAtLaunch(servesPhones: true, environment: [:]))
        #expect(!ShellXRemoteGate.startsAtLaunch(servesPhones: false, environment: [:]))
    }

    // MARK: Settings › Mobile

    /// Settings › Mobile shows the "Pair iPhone" row only while this Mac serves phones over ShellX Link.
    @MainActor
    @Test func settingsPairsPhonesOnlyWhileThisMacServesPhones() {
        #expect(!Self.settingsHost(servesPhones: false).pairsPhonesThroughShellXLink)
        #expect(Self.settingsHost(servesPhones: true).pairsPhonesThroughShellXLink)
    }

    @MainActor
    static func settingsHost(servesPhones: Bool) -> HostSettingsActions {
        HostSettingsActions(
            configFileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json"),
            computerUseRuntimeService: ComputerUseRuntimeService(),
            browserDataImportCoordinator: BrowserDataImportCoordinator(),
            runComputerUseOnboardingAction: { _ in },
            servesPhones: { servesPhones })
    }

    /// The flags this build ships with: phones are served, remote machines are not.
    @Test(.enabled(if: ProcessInfo.processInfo.environment[ShellXRemoteGate.remoteMachinesEnvironmentKey] != "1"))
    func shippedFlagsServePhonesOnly() {
        #expect(ShellXRemoteGate.servesPhones)
        #expect(!ShellXRemoteGate.isEnabled)
    }
}
