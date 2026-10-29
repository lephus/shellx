import Foundation
import ShellXLinkCore
import ShellXLinkRelay

/// Failures of `SecureChannel` beyond the Noise, codec and relay errors it passes through.
public enum SecureChannelError: Error, Equatable, Sendable {
    /// The peer sent a non-empty handshake payload, which v1 forbids (PROTOCOL.md section 2).
    case nonEmptyHandshakePayload
}

/// Noise over a `RelayCircuit`: one `LinkMessage` per Noise transport message (PROTOCOL.md 1-3).
///
/// `send` may be called from several tasks; frames go out in the order the calls arrive.
/// `receive` must be called from one task at a time.
public struct SecureChannel: Sendable {
    private let circuit: any RelayCircuit
    private let transport: TransportBox
    private let sendGate = SendGate()

    /// The peer's static public key, authenticated by the completed handshake.
    public let peerKey: Data

    private init(circuit: any RelayCircuit, transport: NoiseTransport, peerKey: Data) {
        self.circuit = circuit
        self.transport = TransportBox(transport)
        self.peerKey = peerKey
    }

    /// Runs the XX handshake on `c` with empty payloads. The client is the initiator.
    ///
    /// `trusts` is called once, with the peer's static key only after the handshake has
    /// authenticated it (PROTOCOL.md section 2): the initiator checks after message 2, before
    /// message 3 reveals its own key; the responder checks after message 3. Returning `false`
    /// throws `NoiseError.untrustedPeer`. On any failure the circuit is closed and the error is thrown.
    public static func open(
        _ c: any RelayCircuit, role: NoiseRole, key: NoiseStaticKey,
        trusts: @escaping @Sendable (Data) -> Bool
    ) async throws -> SecureChannel {
        // `NoiseHandshake` would call its closure with the key before the peer has proven it;
        // the trust decision is made below, once the key is authenticated.
        var handshake = NoiseHandshake(role: role, local: key, trusts: { _ in true })
        do {
            switch role {
            case .initiator:
                try await c.send(try handshake.writeMessage(payload: Data()))
                let message2 = try await c.receive()
                try requireEmpty(try handshake.readMessage(message2))
                try requireTrusted(handshake.remoteStatic, trusts)
                try await c.send(try handshake.writeMessage(payload: Data()))
            case .responder:
                let message1 = try await c.receive()
                try requireEmpty(try handshake.readMessage(message1))
                try await c.send(try handshake.writeMessage(payload: Data()))
                let message3 = try await c.receive()
                try requireEmpty(try handshake.readMessage(message3))
                try requireTrusted(handshake.remoteStatic, trusts)
            }
            guard handshake.isComplete, let peer = handshake.remoteStatic else { throw NoiseError.badMessage }
            return SecureChannel(circuit: c, transport: try handshake.split(), peerKey: peer)
        } catch {
            await c.close()
            throw error
        }
    }

    /// Encodes, encrypts and sends one message. Throws `LinkCodecError.frameTooLarge` (nothing is
    /// sent, the channel stays usable) or the circuit's error.
    public func send(_ m: LinkMessage) async throws {
        try await send(frame: LinkCodec.encode(m))
    }

    /// Receives and decrypts the next frame and decodes it.
    ///
    /// A `LinkCodecError` means the frame was received but does not decode; the channel stays
    /// usable and the caller applies PROTOCOL.md section 7. Any other error ends the channel
    /// (a frame that fails to decrypt also closes the circuit).
    public func receive() async throws -> LinkMessage {
        let ciphertext = try await circuit.receive()
        let plaintext: Data
        do {
            plaintext = try transport.decrypt(ciphertext)
        } catch {
            await circuit.close()
            throw error
        }
        return try LinkCodec.decode(plaintext)
    }

    /// Sends an already encoded frame. Also lets tests send frames `LinkCodec` cannot produce.
    func send(frame: Data) async throws {
        let circuit = self.circuit
        let transport = self.transport
        await sendGate.acquire()
        do {
            let ciphertext = try transport.encrypt(frame)
            // A detached send: cancelling the caller must not cancel a relay send, which would
            // close the whole circuit.
            try await Task { try await circuit.send(ciphertext) }.value
        } catch {
            await sendGate.release()
            throw error
        }
        await sendGate.release()
    }

    func close() async {
        await circuit.close()
    }

    /// Called right after the message that authenticates the peer's static key was read.
    private static func requireTrusted(_ peer: Data?, _ trusts: @Sendable (Data) -> Bool) throws {
        guard let peer, trusts(peer) else { throw NoiseError.untrustedPeer }
    }

    private static func requireEmpty(_ payload: Data) throws {
        guard payload.isEmpty else { throw SecureChannelError.nonEmptyHandshakePayload }
    }
}

/// The Noise transport state, shared by the copies of one `SecureChannel`.
private final class TransportBox: @unchecked Sendable {
    private let lock = NSLock()
    private var transport: NoiseTransport

    init(_ transport: NoiseTransport) {
        self.transport = transport
    }

    func encrypt(_ plaintext: Data) throws -> Data {
        try lock.withLock { try transport.encrypt(plaintext) }
    }

    func decrypt(_ ciphertext: Data) throws -> Data {
        try lock.withLock { try transport.decrypt(ciphertext) }
    }
}

/// A FIFO lock across suspension points, so frames are encrypted and sent in one order.
private actor SendGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
