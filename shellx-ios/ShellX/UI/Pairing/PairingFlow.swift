import Observation
import ShellXAppCore

/// What the pairing sheet drives: pairing a Mac (`PairingModel`) or linking an Apple ID through one (`AppleLinkModel`).
@MainActor protocol PairingFlow: AnyObject, Observable {
    var step: PairingModel.Step { get }
    func begin(uri: String)
    func confirm() async
    func cancel()
}

extension PairingModel: PairingFlow {}
extension AppleLinkModel: PairingFlow {}
