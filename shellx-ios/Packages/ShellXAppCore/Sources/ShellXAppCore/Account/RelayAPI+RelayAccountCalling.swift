import Foundation
import ShellXLinkAccount

extension RelayAPI: RelayAccountCalling {
    public func pair(offerURI: String, clientKey: Data, token: String) async throws -> PairedMachine {
        try await PhonePairing.pair(offerURI: offerURI, clientKey: clientKey, api: self, token: token)
    }
}
