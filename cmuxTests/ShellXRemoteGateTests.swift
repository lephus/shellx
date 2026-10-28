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

    /// The flags this build ships with: phones are served, remote machines are not.
    @Test(.enabled(if: ProcessInfo.processInfo.environment[ShellXRemoteGate.remoteMachinesEnvironmentKey] != "1"))
    func shippedFlagsServePhonesOnly() {
        #expect(ShellXRemoteGate.servesPhones)
        #expect(!ShellXRemoteGate.isEnabled)
    }
}
