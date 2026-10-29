import CryptoKit
import Foundation

/// A Curve25519 key pair used as a Noise static (or, in tests, ephemeral) key.
///
/// The key is held as its 32 raw private bytes so the type stays `Sendable` on every
/// SDK the package builds with; CryptoKit key objects are created per operation.
public struct NoiseStaticKey: Sendable {
    /// The 32-byte X25519 private key.
    public let rawPrivate: Data
    /// The 32-byte X25519 public key.
    public let publicKey: Data

    /// Generates a fresh random key pair.
    public init() {
        let key = Curve25519.KeyAgreement.PrivateKey()
        rawPrivate = key.rawRepresentation
        publicKey = key.publicKey.rawRepresentation
    }

    /// Restores a key pair from its 32 raw private bytes. Throws CryptoKit's error for a wrong length.
    public init(rawPrivate: Data) throws {
        let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: rawPrivate)
        self.rawPrivate = key.rawRepresentation
        publicKey = key.publicKey.rawRepresentation
    }

    /// Noise `DH(key_pair, public_key)`: the 32-byte X25519 shared secret.
    func diffieHellman(with remotePublic: Data) throws -> Data {
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: rawPrivate)
        let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: remotePublic)
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        return secret.withUnsafeBytes { Data($0) }
    }
}

/// Which side of the handshake this party plays. The initiator sends message 1.
public enum NoiseRole: Sendable {
    case initiator, responder
}

/// Failures from the Noise handshake and transport.
public enum NoiseError: Error, Equatable {
    /// The peer's static key was decrypted and `trusts` returned `false`.
    case untrustedPeer
    /// An AEAD tag did not verify: the message was tampered with, replayed, reordered or sent under another key.
    case decryptFailed
    /// A malformed or oversized message, a call out of handshake order, or use after a failure.
    case badMessage
    /// The 64-bit nonce counter is used up; the session must be re-established.
    case nonceExhausted
}

/// Noise's maximum message length (spec §3).
let noiseMaxMessageLength = 65535
/// DHLEN for 25519.
let noiseDHLength = 32
/// ChaChaPoly authentication tag length.
let noiseTagLength = 16
