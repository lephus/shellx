import Foundation
import ShellXBrand

/// ShellX: the switches of ShellX remote (W2 plan Task 13).
///
/// * ``servesPhones``: this Mac signs in, registers with the relay (`machines.register`, its link slot) and
///   runs the ShellX Link host with its Feed, sessions, chat, phone pairing and paired-phone grants. Off means
///   the remote service starts no process and makes no core call.
/// * ``isEnabled``: remote machines, the UI and features that show or use the account's *other* machines
///   (sidebar machine headers, share links, access requests, remote terminals and the cmux-tui host daemon).
///
/// Both are on in DEBUG builds launched with `SHELLX_REMOTE_MACHINES=1`.
enum ShellXRemoteGate {
    static let remoteMachinesEnvironmentKey = "SHELLX_REMOTE_MACHINES"

    /// Remote machines: on when the feature flag is flipped, or with the DEBUG launch override.
    static var isEnabled: Bool {
        isEnabled(remoteMachines: ShellXFeatures.remoteMachines, environment: ProcessInfo.processInfo.environment)
    }

    /// This Mac serves phones: remote machines, or iPhone pairing on its own.
    static var servesPhones: Bool {
        servesPhones(remoteMachines: ShellXFeatures.remoteMachines, phonePairing: ShellXFeatures.phonePairing,
                     environment: ProcessInfo.processInfo.environment)
    }

    /// ``isEnabled`` for the given flag and launch environment.
    static func isEnabled(remoteMachines: Bool, environment: [String: String]) -> Bool {
        if remoteMachines { return true }
        #if DEBUG
        return environment[remoteMachinesEnvironmentKey] == "1"
        #else
        return false
        #endif
    }

    /// ``servesPhones`` for the given flags and launch environment.
    static func servesPhones(remoteMachines: Bool, phonePairing: Bool, environment: [String: String]) -> Bool {
        phonePairing || isEnabled(remoteMachines: remoteMachines, environment: environment)
    }
}
