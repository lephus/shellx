import Foundation

/// `Noise_XX_25519_ChaChaPoly_SHA256` handshake state (Noise spec rev 34 §5.3, §7.5).
///
/// ```
/// XX:
///   -> e
///   <- e, ee, s, es
///   -> s, se
/// ```
///
/// The initiator writes messages 1 and 3 and reads message 2; the responder does the reverse.
/// `trusts` is called with the peer's static public key as soon as it is decrypted (message 2
/// for the initiator, message 3 for the responder); returning `false` throws `.untrustedPeer`.
/// Any error ends the handshake: every later call throws `.badMessage`.
public struct NoiseHandshake: Sendable {
    public static let protocolName = "Noise_XX_25519_ChaChaPoly_SHA256"
    public static let prologue = Data("shellx-link/1".utf8)

    private enum Token { case e, s, ee, es, se }

    private static let pattern: [[Token]] = [
        [.e],
        [.e, .ee, .s, .es],
        [.s, .se],
    ]

    private let role: NoiseRole
    private let local: NoiseStaticKey
    private let trusts: @Sendable (Data) -> Bool
    private var ephemeralForTesting: NoiseStaticKey?
    private var symmetric: NoiseSymmetricState
    private var localEphemeral: NoiseStaticKey?
    private var remoteEphemeral: Data?
    private var messageIndex = 0
    private var failed = false
    private var didSplit = false

    /// The peer's static public key.
    ///
    /// Authenticated only once `isComplete` is true. Before that it is the value decrypted from `s`,
    /// which the peer has not yet proven it owns (that proof is `es`/`se` plus the payload tag).
    /// It is cleared when the handshake fails, so a rejected or forged key is never reported.
    public private(set) var remoteStatic: Data?

    /// - Parameter ephemeralForTesting: a fixed ephemeral key, for known-answer test vectors only.
    ///   **Never pass this in production.** A fixed ephemeral makes every session with the same
    ///   peer derive the same transport keys, so nonces repeat under one key and ChaChaPoly's
    ///   confidentiality and integrity are lost; it also removes forward secrecy.
    public init(
        role: NoiseRole,
        local: NoiseStaticKey,
        trusts: @escaping @Sendable (Data) -> Bool,
        ephemeralForTesting: NoiseStaticKey? = nil
    ) {
        self.role = role
        self.local = local
        self.trusts = trusts
        self.ephemeralForTesting = ephemeralForTesting
        var symmetric = NoiseSymmetricState(protocolName: Self.protocolName)
        symmetric.mixHash(Self.prologue)
        self.symmetric = symmetric
    }

    /// True after all three messages have been written or read successfully.
    public var isComplete: Bool { !failed && messageIndex == Self.pattern.count }

    /// The handshake hash `h`, usable for channel binding once `isComplete` is true.
    public var handshakeHash: Data { symmetric.handshakeHash }

    /// Writes the next handshake message carrying `payload`.
    public mutating func writeMessage(payload: Data) throws -> Data {
        try guarded {
            try $0.checkTurn(writing: true)
            var message = Data()
            for token in Self.pattern[$0.messageIndex] {
                switch token {
                case .e:
                    let ephemeral = $0.ephemeralForTesting ?? NoiseStaticKey()
                    $0.ephemeralForTesting = nil
                    $0.localEphemeral = ephemeral
                    message.append(ephemeral.publicKey)
                    $0.symmetric.mixHash(ephemeral.publicKey)
                case .s:
                    message.append(try $0.symmetric.encryptAndHash($0.local.publicKey))
                default:
                    try $0.mixDiffieHellman(token)
                }
            }
            message.append(try $0.symmetric.encryptAndHash(payload))
            guard message.count <= noiseMaxMessageLength else { throw NoiseError.badMessage }
            $0.messageIndex += 1
            return message
        }
    }

    /// Reads the peer's next handshake message and returns its payload.
    public mutating func readMessage(_ message: Data) throws -> Data {
        try guarded {
            try $0.checkTurn(writing: false)
            guard message.count <= noiseMaxMessageLength else { throw NoiseError.badMessage }
            var reader = ByteReader(Data(message))
            for token in Self.pattern[$0.messageIndex] {
                switch token {
                case .e:
                    let ephemeral = try reader.take(noiseDHLength)
                    $0.remoteEphemeral = ephemeral
                    $0.symmetric.mixHash(ephemeral)
                case .s:
                    let length = noiseDHLength + ($0.symmetric.hasKey ? noiseTagLength : 0)
                    let remote = try $0.symmetric.decryptAndHash(reader.take(length))
                    $0.remoteStatic = remote
                    guard $0.trusts(remote) else { throw NoiseError.untrustedPeer }
                default:
                    try $0.mixDiffieHellman(token)
                }
            }
            let payload = try $0.symmetric.decryptAndHash(reader.rest())
            $0.messageIndex += 1
            return payload
        }
    }

    /// Derives the transport cipher states. Call once, after message 3.
    public mutating func split() throws -> NoiseTransport {
        guard isComplete, !didSplit else { throw NoiseError.badMessage }
        didSplit = true
        localEphemeral = nil
        let (initiatorToResponder, responderToInitiator) = symmetric.split()
        switch role {
        case .initiator:
            return NoiseTransport(send: initiatorToResponder, receive: responderToInitiator)
        case .responder:
            return NoiseTransport(send: responderToInitiator, receive: initiatorToResponder)
        }
    }

    // MARK: - private

    /// Runs one message step; any error poisons the handshake. Non-Noise errors become `.badMessage`.
    private mutating func guarded<T>(_ body: (inout NoiseHandshake) throws -> T) throws -> T {
        guard !failed else { throw NoiseError.badMessage }
        do {
            return try body(&self)
        } catch {
            failed = true
            localEphemeral = nil
            // `s` may have decrypted before the failure without the peer proving ownership.
            remoteStatic = nil
            throw (error as? NoiseError) ?? NoiseError.badMessage
        }
    }

    private func checkTurn(writing: Bool) throws {
        guard messageIndex < Self.pattern.count else { throw NoiseError.badMessage }
        let initiatorWrites = messageIndex % 2 == 0
        let weWrite = (role == .initiator) == initiatorWrites
        guard weWrite == writing else { throw NoiseError.badMessage }
    }

    /// `ee`, `es` and `se`: in `xy` the first letter is the initiator's key, the second the responder's.
    private mutating func mixDiffieHellman(_ token: Token) throws {
        let localKey: NoiseStaticKey?
        let remoteKey: Data?
        switch (token, role) {
        case (.ee, _):
            (localKey, remoteKey) = (localEphemeral, remoteEphemeral)
        case (.es, .initiator):
            (localKey, remoteKey) = (localEphemeral, remoteStatic)
        case (.es, .responder):
            (localKey, remoteKey) = (local, remoteEphemeral)
        case (.se, .initiator):
            (localKey, remoteKey) = (local, remoteEphemeral)
        case (.se, .responder):
            (localKey, remoteKey) = (localEphemeral, remoteStatic)
        default:
            throw NoiseError.badMessage
        }
        guard let localKey, let remoteKey else { throw NoiseError.badMessage }
        symmetric.mixKey(try localKey.diffieHellman(with: remoteKey))
    }
}

private struct ByteReader {
    private let data: Data
    private var offset = 0

    init(_ data: Data) {
        self.data = data
    }

    mutating func take(_ count: Int) throws -> Data {
        guard data.count - offset >= count else { throw NoiseError.badMessage }
        let start = data.startIndex + offset
        offset += count
        return Data(data[start..<start + count])
    }

    func rest() -> Data {
        Data(data[(data.startIndex + offset)...])
    }
}
