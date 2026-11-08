import Foundation
import ShellXLinkAccount

extension RelayAPI: RelayAccountCalling {
    public func pair(offerURI: String, clientKey: Data, token: String) async throws -> PairedMachine {
        try await PhonePairing.pair(offerURI: offerURI, clientKey: clientKey, api: self, token: token)
    }

    public func linkApple(offerURI: String, linkToken: String, clientKey: Data) async throws -> AppleLinkApproval {
        try await AppleLinkPairing.link(offerURI: offerURI, linkToken: linkToken, clientKey: clientKey, api: self)
    }
}
