import CryptoKit
import Foundation

public enum ShareCipherError: Error, Sendable { case frameTooLarge }

/// One side of a share circuit: seals outgoing and opens incoming frames.
/// Frame = nonce(12) || AES-256-GCM ciphertext || tag.
///
/// The AAD is staged per connection (wire format v1 amendment A1) so a relay cannot replay
/// frames from an earlier connection:
///  - stage 1 (initial): `shellx-share/1|<circuit>`           (viewer `hello`)
///  - stage 2: after `setViewerNonce`: `...|<circuit>|<vn>`   (host `welcome`, or `bye`)
///  - stage 3: after `setHostNonce`: `...|<circuit>|<vn>|<hn>` (every later frame)
/// `vn`/`hn` are the standard-base64 strings of the 16-byte nonces carried by `hello`/`welcome`.
/// Host flow: `open(hello)` -> `setViewerNonce` -> `seal(welcome)` -> `setHostNonce`.
/// Viewer flow: `seal(hello)` -> `setViewerNonce` -> `open(welcome)` -> `setHostNonce`.
/// Which message types are acceptable at which stage, and the host-only caps (`in` <= 4 KiB,
/// label <= 40), are the caller's job: `open` returns the decoded message.
/// Counters `seq` run per direction and are not reset by stage changes.
public struct ShareCipher: Sendable {
    /// Hard cap for one frame (a WebSocket binary message); larger inputs are dropped before decrypt.
    public static let maxFrameBytes = 64 * 1024

    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private let circuit: String
    private var viewerNonce: String?
    private var hostNonce: String?
    private var sendSeq = 0
    private var lastReceivedSeq = 0
    public private(set) var dropped = 0

    /// Test hook for byte-exact vectors; consumed by the next `seal`. Never public.
    var fixedNonce: AES.GCM.Nonce?

    public init(sendKey: SymmetricKey, receiveKey: SymmetricKey, circuit: String) {
        self.sendKey = sendKey
        self.receiveKey = receiveKey
        self.circuit = circuit
    }

    /// Moves to stage 2. Pass the `hello` nonce.
    public mutating func setViewerNonce(_ nonce: Data) { viewerNonce = nonce.base64EncodedString() }

    /// Moves to stage 3. Pass the `welcome` nonce; requires the viewer nonce first (else ignored).
    public mutating func setHostNonce(_ nonce: Data) {
        if viewerNonce != nil { hostNonce = nonce.base64EncodedString() }
    }

    /// The AAD of the current stage.
    var aad: Data {
        var s = "shellx-share/1|\(circuit)"
        if let vn = viewerNonce {
            s += "|\(vn)"
            if let hn = hostNonce { s += "|\(hn)" }
        }
        return Data(s.utf8)
    }

    public mutating func seal(_ message: ShareMessage) throws -> Data {
        let nonce = fixedNonce ?? AES.GCM.Nonce()
        fixedNonce = nil
        let plaintext = message.wireJSON(seq: sendSeq + 1)
        guard 12 + plaintext.count + 16 <= Self.maxFrameBytes else { throw ShareCipherError.frameTooLarge }
        let box = try AES.GCM.seal(plaintext, using: sendKey, nonce: nonce, authenticating: aad)
        sendSeq += 1
        return Data(nonce) + box.ciphertext + box.tag
    }

    /// nil means the frame was dropped and counted (oversize, bad length, auth failure under the
    /// current stage's AAD, undecodable JSON, non-integer `seq`, or `seq` not above the last accepted).
    public mutating func open(_ frame: Data) -> ShareMessage? {
        guard frame.count >= 12 + 16, frame.count <= Self.maxFrameBytes,
              let nonce = try? AES.GCM.Nonce(data: frame.prefix(12)),
              let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: frame.dropFirst(12).dropLast(16),
                                               tag: frame.suffix(16)),
              let plain = try? AES.GCM.open(box, using: receiveKey, authenticating: aad),
              ShareEnvelope.hasIntegerSeqToken(plain),
              let env = try? JSONDecoder().decode(ShareEnvelope.self, from: plain),
              env.seq > lastReceivedSeq
        else {
            dropped += 1
            return nil
        }
        lastReceivedSeq = env.seq
        return env.message
    }
}
