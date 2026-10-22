import Foundation
import ShellXLinkCore
import XCTest

final class NoiseTests: XCTestCase {
    // MARK: - snow vectors

    func testMatchesSnowVectors() throws {
        let v = try SnowVectors.load()
        XCTAssertEqual(v.protocolName, NoiseHandshake.protocolName)
        XCTAssertEqual(v.prologue, NoiseHandshake.prologue)

        let iStatic = try NoiseStaticKey(rawPrivate: v.initiator.staticPrivate)
        let iEphemeral = try NoiseStaticKey(rawPrivate: v.initiator.ephemeralPrivate)
        let rStatic = try NoiseStaticKey(rawPrivate: v.responder.staticPrivate)
        let rEphemeral = try NoiseStaticKey(rawPrivate: v.responder.ephemeralPrivate)
        XCTAssertEqual(iStatic.publicKey, v.initiator.staticPublic)
        XCTAssertEqual(iEphemeral.publicKey, v.initiator.ephemeralPublic)
        XCTAssertEqual(rStatic.publicKey, v.responder.staticPublic)
        XCTAssertEqual(rEphemeral.publicKey, v.responder.ephemeralPublic)

        var initiator = NoiseHandshake(
            role: .initiator, local: iStatic, trusts: { _ in true }, ephemeralForTesting: iEphemeral)
        var responder = NoiseHandshake(
            role: .responder, local: rStatic, trusts: { _ in true }, ephemeralForTesting: rEphemeral)

        XCTAssertEqual(v.handshake.count, 3)
        for (index, step) in v.handshake.enumerated() {
            let initiatorSends = index % 2 == 0
            XCTAssertEqual(step.sender, initiatorSends ? "initiator" : "responder")
            let message: Data
            let payload: Data
            if initiatorSends {
                message = try initiator.writeMessage(payload: step.payload)
                payload = try responder.readMessage(message)
            } else {
                message = try responder.writeMessage(payload: step.payload)
                payload = try initiator.readMessage(message)
            }
            XCTAssertEqual(message.hex, step.ciphertext.hex, "handshake message \(index + 1)")
            XCTAssertEqual(payload, step.payload, "handshake payload \(index + 1)")
        }
        XCTAssertTrue(initiator.isComplete)
        XCTAssertTrue(responder.isComplete)
        XCTAssertEqual(initiator.remoteStatic, v.responder.staticPublic)
        XCTAssertEqual(responder.remoteStatic, v.initiator.staticPublic)
        XCTAssertEqual(initiator.handshakeHash.hex, v.handshakeHash.hex)
        XCTAssertEqual(responder.handshakeHash.hex, v.handshakeHash.hex)

        var iTransport = try initiator.split()
        var rTransport = try responder.split()
        for message in v.initiatorToResponder {
            XCTAssertEqual(try iTransport.encrypt(message.payload).hex, message.ciphertext.hex)
            XCTAssertEqual(try rTransport.decrypt(message.ciphertext), message.payload)
        }
        for message in v.responderToInitiator {
            XCTAssertEqual(try rTransport.encrypt(message.payload).hex, message.ciphertext.hex)
            XCTAssertEqual(try iTransport.decrypt(message.ciphertext), message.payload)
        }
        XCTAssertEqual(v.initiatorToResponder.map(\.payload), [Data("ping".utf8), Data("pong".utf8)])
        XCTAssertEqual(v.responderToInitiator.map(\.payload), [Data("ping".utf8), Data("pong".utf8)])
    }

    // MARK: - behaviour

    func testHandshakeRoundTripRandomKeys() throws {
        let iKey = NoiseStaticKey()
        let rKey = NoiseStaticKey()
        XCTAssertEqual(iKey.publicKey.count, 32)
        XCTAssertEqual(iKey.rawPrivate.count, 32)
        XCTAssertNotEqual(iKey.publicKey, rKey.publicKey)
        XCTAssertEqual(try NoiseStaticKey(rawPrivate: iKey.rawPrivate).publicKey, iKey.publicKey)

        var pair = try Pair.handshake(initiator: iKey, responder: rKey)
        XCTAssertEqual(pair.initiator.remoteStatic, rKey.publicKey)
        XCTAssertEqual(pair.responder.remoteStatic, iKey.publicKey)
        XCTAssertEqual(pair.initiator.handshakeHash, pair.responder.handshakeHash)

        var iTransport = try pair.initiator.split()
        var rTransport = try pair.responder.split()
        let hello = Data("hello mac".utf8)
        XCTAssertEqual(try rTransport.decrypt(iTransport.encrypt(hello)), hello)
        let back = Data("hello phone".utf8)
        XCTAssertEqual(try iTransport.decrypt(rTransport.encrypt(back)), back)
        XCTAssertThrowsError(try pair.initiator.split(), "split twice") { error in
            XCTAssertEqual(error as? NoiseError, .badMessage)
        }
    }

    func testUntrustedPeerRejected() throws {
        let iKey = NoiseStaticKey()
        let rKey = NoiseStaticKey()

        // Initiator distrusts the responder: rejected while reading message 2.
        let seenByInitiator = KeyRecorder()
        var initiator = NoiseHandshake(role: .initiator, local: iKey, trusts: { key in
            seenByInitiator.record(key)
            return false
        })
        var responder = NoiseHandshake(role: .responder, local: rKey, trusts: { _ in true })
        _ = try responder.readMessage(initiator.writeMessage(payload: Data()))
        let message2 = try responder.writeMessage(payload: Data("hello-r".utf8))
        XCTAssertThrowsError(try initiator.readMessage(message2)) { error in
            XCTAssertEqual(error as? NoiseError, .untrustedPeer)
        }
        XCTAssertEqual(seenByInitiator.keys, [rKey.publicKey])
        XCTAssertFalse(initiator.isComplete)
        XCTAssertNil(initiator.remoteStatic, "a rejected key is not kept")
        XCTAssertThrowsError(try initiator.writeMessage(payload: Data()), "failed handshake stays dead")

        // Responder distrusts the initiator: rejected while reading message 3.
        var initiator2 = NoiseHandshake(role: .initiator, local: iKey, trusts: { _ in true })
        var responder2 = NoiseHandshake(role: .responder, local: rKey, trusts: { $0 != iKey.publicKey })
        _ = try responder2.readMessage(initiator2.writeMessage(payload: Data()))
        _ = try initiator2.readMessage(responder2.writeMessage(payload: Data()))
        let message3 = try initiator2.writeMessage(payload: Data("hello-i".utf8))
        XCTAssertThrowsError(try responder2.readMessage(message3)) { error in
            XCTAssertEqual(error as? NoiseError, .untrustedPeer)
        }
        XCTAssertFalse(responder2.isComplete)
        XCTAssertNil(responder2.remoteStatic, "a rejected key is not kept")
        XCTAssertThrowsError(try responder2.split())
    }

    func testTamperedCiphertextFails() throws {
        // Transport: one flipped bit anywhere fails authentication.
        var pair = try Pair.handshake(initiator: NoiseStaticKey(), responder: NoiseStaticKey())
        var iTransport = try pair.initiator.split()
        var rTransport = try pair.responder.split()
        let ciphertext = try iTransport.encrypt(Data("ping".utf8))
        for bit in [0, 7, ciphertext.count * 8 - 1] {
            var tampered = ciphertext
            tampered[bit / 8] ^= UInt8(1 << (bit % 8))
            XCTAssertThrowsError(try rTransport.decrypt(tampered), "bit \(bit)") { error in
                XCTAssertEqual(error as? NoiseError, .decryptFailed)
            }
        }
        // A failed decrypt does not consume the nonce: the genuine message still opens.
        XCTAssertEqual(try rTransport.decrypt(ciphertext), Data("ping".utf8))

        // Handshake: flip a bit in the encrypted static key of message 2.
        var initiator = NoiseHandshake(role: .initiator, local: NoiseStaticKey(), trusts: { _ in true })
        var responder = NoiseHandshake(role: .responder, local: NoiseStaticKey(), trusts: { _ in true })
        _ = try responder.readMessage(initiator.writeMessage(payload: Data()))
        var message2 = try responder.writeMessage(payload: Data("hello-r".utf8))
        message2[40] ^= 0x01
        XCTAssertThrowsError(try initiator.readMessage(message2)) { error in
            XCTAssertEqual(error as? NoiseError, .decryptFailed)
        }
        XCTAssertNil(initiator.remoteStatic)

        // Handshake: `s` decrypts and is trusted, but the payload tag fails. The key in `s` was never
        // proven (an active attacker who completed `ee` can put any trusted key there), so it is dropped.
        let trustedKey = NoiseStaticKey()
        var initiator2 = NoiseHandshake(role: .initiator, local: NoiseStaticKey(), trusts: { _ in true })
        var responder2 = NoiseHandshake(role: .responder, local: trustedKey, trusts: { _ in true })
        _ = try responder2.readMessage(initiator2.writeMessage(payload: Data()))
        var message2b = try responder2.writeMessage(payload: Data("hello-r".utf8))
        message2b[message2b.count - 1] ^= 0x01
        XCTAssertThrowsError(try initiator2.readMessage(message2b)) { error in
            XCTAssertEqual(error as? NoiseError, .decryptFailed)
        }
        XCTAssertNil(initiator2.remoteStatic)
        XCTAssertFalse(initiator2.isComplete)
    }

    /// Checks that the counter advances per frame and gates ordering. The little-endian byte order
    /// itself is pinned by `testMatchesSnowVectors` (frames at nonce 1 differ under big-endian).
    func testNonceIncrementsLittleEndianCounter() throws {
        var pair = try Pair.handshake(initiator: NoiseStaticKey(), responder: NoiseStaticKey())
        var iTransport = try pair.initiator.split()
        var rTransport = try pair.responder.split()
        let plaintext = Data("same".utf8)
        let first = try iTransport.encrypt(plaintext)
        let second = try iTransport.encrypt(plaintext)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.count, plaintext.count + 16)

        // Out of order: the receiver expects nonce 0, so message 1 does not open yet.
        XCTAssertThrowsError(try rTransport.decrypt(second)) { error in
            XCTAssertEqual(error as? NoiseError, .decryptFailed)
        }
        XCTAssertEqual(try rTransport.decrypt(first), plaintext)
        XCTAssertEqual(try rTransport.decrypt(second), plaintext)
        // Replay of an already-consumed nonce is rejected.
        XCTAssertThrowsError(try rTransport.decrypt(first))

        // Frames are capped at 65535 bytes of ciphertext.
        XCTAssertNoThrow(try iTransport.encrypt(Data(count: 65535 - 16)))
        XCTAssertThrowsError(try iTransport.encrypt(Data(count: 65535 - 15))) { error in
            XCTAssertEqual(error as? NoiseError, .badMessage)
        }
    }
}

// MARK: - helpers

private final class KeyRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Data] = []

    func record(_ key: Data) {
        lock.lock(); defer { lock.unlock() }
        recorded.append(key)
    }

    var keys: [Data] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }
}

private struct Pair {
    var initiator: NoiseHandshake
    var responder: NoiseHandshake

    static func handshake(initiator iKey: NoiseStaticKey, responder rKey: NoiseStaticKey) throws -> Pair {
        var initiator = NoiseHandshake(role: .initiator, local: iKey, trusts: { _ in true })
        var responder = NoiseHandshake(role: .responder, local: rKey, trusts: { _ in true })
        XCTAssertEqual(try responder.readMessage(initiator.writeMessage(payload: Data())), Data())
        XCTAssertEqual(try initiator.readMessage(responder.writeMessage(payload: Data("r".utf8))), Data("r".utf8))
        XCTAssertFalse(initiator.isComplete)
        XCTAssertEqual(try responder.readMessage(initiator.writeMessage(payload: Data("i".utf8))), Data("i".utf8))
        XCTAssertTrue(initiator.isComplete)
        XCTAssertTrue(responder.isComplete)
        return Pair(initiator: initiator, responder: responder)
    }
}

private struct SnowVectors {
    struct Party { var staticPrivate, staticPublic, ephemeralPrivate, ephemeralPublic: Data }
    struct Message { var sender: String; var payload: Data; var ciphertext: Data }

    var protocolName: String
    var prologue: Data
    var initiator: Party
    var responder: Party
    var handshake: [Message]
    var handshakeHash: Data
    var initiatorToResponder: [Message]
    var responderToInitiator: [Message]

    /// `shellx-link/vectors/noise_xx.json`, generated by `shellx-link/vectors/gen` with Rust `snow`.
    static func load() throws -> SnowVectors {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ShellXLinkCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // shellx-link
            .appendingPathComponent("vectors/noise_xx.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])

        func string(_ object: [String: Any], _ key: String) throws -> String {
            try XCTUnwrap(object[key] as? String, "missing \(key)")
        }
        func bytes(_ object: [String: Any], _ key: String) throws -> Data {
            try XCTUnwrap(Data(hex: string(object, key)), "bad hex in \(key)")
        }
        func party(_ key: String) throws -> Party {
            let p = try XCTUnwrap(root[key] as? [String: Any])
            return try Party(
                staticPrivate: bytes(p, "static_private"), staticPublic: bytes(p, "static_public"),
                ephemeralPrivate: bytes(p, "ephemeral_private"), ephemeralPublic: bytes(p, "ephemeral_public"))
        }
        func messages(_ list: Any?) throws -> [Message] {
            try XCTUnwrap(list as? [[String: Any]]).map {
                Message(sender: ($0["sender"] as? String) ?? "",
                        payload: try bytes($0, "payload"), ciphertext: try bytes($0, "ciphertext"))
            }
        }
        let transport = try XCTUnwrap(root["transport"] as? [String: Any])
        return try SnowVectors(
            protocolName: string(root, "protocol"),
            prologue: bytes(root, "prologue"),
            initiator: party("initiator"),
            responder: party("responder"),
            handshake: messages(root["handshake"]),
            handshakeHash: bytes(root, "handshake_hash"),
            initiatorToResponder: messages(transport["initiator_to_responder"]),
            responderToInitiator: messages(transport["responder_to_initiator"]))
    }
}

private extension Data {
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var out = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        self = out
    }

    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
