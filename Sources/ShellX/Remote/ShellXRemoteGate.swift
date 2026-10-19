import Foundation
import ShellXBrand

/// ShellX: the one switch for ShellX remote machines (W2 plan Task 13). On when the feature flag is
/// flipped, or in DEBUG builds launched with `SHELLX_REMOTE_MACHINES=1`. Off means the remote service
/// starts no process and makes no core call.
enum ShellXRemoteGate {
    static var isEnabled: Bool {
        if ShellXFeatures.remoteMachines { return true }
        #if DEBUG
        return ProcessInfo.processInfo.environment["SHELLX_REMOTE_MACHINES"] == "1"
        #else
        return false
        #endif
    }
}
