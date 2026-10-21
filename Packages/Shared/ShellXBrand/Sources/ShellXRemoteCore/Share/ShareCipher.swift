import CryptoKit
import Foundation

/// One direction pair of a share circuit: seals outgoing and opens incoming frames.
/// Frame = nonce(12) || AES-256-GCM ciphertext || tag, AAD = `shellx-share/1|<circuit>`.
public struct ShareCipher: Sendable {
    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private let aad: Data
    private var sendSeq = 0
    private var lastReceivedSeq = 0
    public private(set) var dropped = 0

    /// Test hook for byte-exact vectors; consumed by the next `seal`. Never public.
    var fixedNonce: AES.GCM.Nonce?

    public init(sendKey: SymmetricKey, receiveKey: SymmetricKey, circuit: String) {
        self.sendKey = sendKey
        self.receiveKey = receiveKey
        self.aad = Data("shellx-share/1|\(circuit)".utf8)
    }

    public mutating func seal(_ message: ShareMessage) throws -> Data {
        let nonce = fixedNonce ?? AES.GCM.Nonce()
        fixedNonce = nil
        let plaintext = message.wireJSON(seq: sendSeq + 1)
        let box = try AES.GCM.seal(plaintext, using: sendKey, nonce: nonce, authenticating: aad)
        sendSeq += 1
        return Data(nonce) + box.ciphertext + box.tag
    }

    /// nil means the frame was dropped (bad length, auth failure, bad JSON or non-increasing seq).
    public mutating func open(_ frame: Data) -> ShareMessage? {
        guard frame.count >= 12 + 16,
              let nonce = try? AES.GCM.Nonce(data: frame.prefix(12)),
              let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: frame.dropFirst(12).dropLast(16),
                                               tag: frame.suffix(16)),
              let plain = try? AES.GCM.open(box, using: receiveKey, authenticating: aad),
              let seq = ShareMessage.wireSeq(plain), seq > lastReceivedSeq,
              let message = try? JSONDecoder().decode(ShareMessage.self, from: plain)
        else {
            dropped += 1
            return nil
        }
        lastReceivedSeq = seq
        return message
    }
}
