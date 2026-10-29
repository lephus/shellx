import CryptoKit
import Foundation

/// Noise `CipherState` (spec rev 34 §5.1) for ChaChaPoly.
///
/// The key is kept as raw bytes for `Sendable` portability; a `SymmetricKey` is built per call.
struct NoiseCipherState: Sendable {
    private var key: Data?
    private var nonce: UInt64 = 0

    init(key: Data? = nil) {
        self.key = key
    }

    var hasKey: Bool { key != nil }

    /// `EncryptWithAd`. Without a key the plaintext passes through unchanged.
    mutating func encrypt(ad: Data, plaintext: Data) throws -> Data {
        guard let key else { return plaintext }
        let sealed = try ChaChaPoly.seal(
            plaintext, using: SymmetricKey(data: key), nonce: try currentNonce(), authenticating: ad)
        nonce += 1
        var out = Data(sealed.ciphertext)
        out.append(contentsOf: sealed.tag)
        return out
    }

    /// `DecryptWithAd`. A failed decryption leaves the nonce unchanged, as the spec requires.
    mutating func decrypt(ad: Data, ciphertext: Data) throws -> Data {
        guard let key else { return ciphertext }
        let nonceValue = try currentNonce()
        guard ciphertext.count >= noiseTagLength else { throw NoiseError.decryptFailed }
        let body = Data(ciphertext.prefix(ciphertext.count - noiseTagLength))
        let tag = Data(ciphertext.suffix(noiseTagLength))
        let plaintext: Data
        do {
            let box = try ChaChaPoly.SealedBox(nonce: nonceValue, ciphertext: body, tag: tag)
            plaintext = try ChaChaPoly.open(box, using: SymmetricKey(data: key), authenticating: ad)
        } catch {
            throw NoiseError.decryptFailed
        }
        nonce += 1
        return plaintext
    }

    /// 32 bits of zeros followed by the little-endian 64-bit counter (spec §12.3).
    /// The counter value 2^64-1 is reserved, so it is never used to encrypt.
    private func currentNonce() throws -> ChaChaPoly.Nonce {
        guard nonce < UInt64.max else { throw NoiseError.nonceExhausted }
        var bytes = Data(count: 4)
        withUnsafeBytes(of: nonce.littleEndian) { bytes.append(contentsOf: $0) }
        return try ChaChaPoly.Nonce(data: bytes)
    }
}

/// Noise `SymmetricState` (spec §5.2) with SHA-256.
struct NoiseSymmetricState: Sendable {
    private(set) var chainingKey: Data
    private(set) var handshakeHash: Data
    private var cipher = NoiseCipherState()

    /// `InitializeSymmetric(protocol_name)`.
    init(protocolName: String) {
        let name = Data(protocolName.utf8)
        if name.count <= SHA256.byteCount {
            handshakeHash = name + Data(count: SHA256.byteCount - name.count)
        } else {
            handshakeHash = Data(SHA256.hash(data: name))
        }
        chainingKey = handshakeHash
    }

    var hasKey: Bool { cipher.hasKey }

    mutating func mixKey(_ inputKeyMaterial: Data) {
        let (newChainingKey, tempKey) = noiseHKDF(chainingKey: chainingKey, inputKeyMaterial: inputKeyMaterial)
        chainingKey = newChainingKey
        // HASHLEN is 32, so temp_k needs no truncation.
        cipher = NoiseCipherState(key: tempKey)
    }

    mutating func mixHash(_ data: Data) {
        var hasher = SHA256()
        hasher.update(data: handshakeHash)
        hasher.update(data: data)
        handshakeHash = Data(hasher.finalize())
    }

    mutating func encryptAndHash(_ plaintext: Data) throws -> Data {
        let ciphertext = try cipher.encrypt(ad: handshakeHash, plaintext: plaintext)
        mixHash(ciphertext)
        return ciphertext
    }

    mutating func decryptAndHash(_ ciphertext: Data) throws -> Data {
        let plaintext = try cipher.decrypt(ad: handshakeHash, ciphertext: ciphertext)
        mixHash(ciphertext)
        return plaintext
    }

    /// `Split()`: the initiator-to-responder and responder-to-initiator cipher states.
    func split() -> (initiatorToResponder: NoiseCipherState, responderToInitiator: NoiseCipherState) {
        let (k1, k2) = noiseHKDF(chainingKey: chainingKey, inputKeyMaterial: Data())
        return (NoiseCipherState(key: k1), NoiseCipherState(key: k2))
    }
}

/// Noise `HKDF(chaining_key, input_key_material, 2)` (spec §4.3), built from HMAC-SHA256.
///
/// CryptoKit's `HKDF` is not used: Noise feeds the chaining key as the HMAC key of the extract
/// step and defines its own output chaining, so the explicit construction keeps that exact.
func noiseHKDF(chainingKey: Data, inputKeyMaterial: Data) -> (Data, Data) {
    let tempKey = hmacSHA256(key: chainingKey, data: inputKeyMaterial)
    let output1 = hmacSHA256(key: tempKey, data: Data([0x01]))
    let output2 = hmacSHA256(key: tempKey, data: output1 + Data([0x02]))
    return (output1, output2)
}

private func hmacSHA256(key: Data, data: Data) -> Data {
    Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
}

/// The two cipher states produced when the handshake completes.
///
/// Messages must be decrypted in the order they were encrypted; the receive counter only
/// advances on a successful decryption.
public struct NoiseTransport: Sendable {
    private var send: NoiseCipherState
    private var receive: NoiseCipherState

    init(send: NoiseCipherState, receive: NoiseCipherState) {
        self.send = send
        self.receive = receive
    }

    /// Encrypts one frame. The ciphertext is `plaintext.count + 16` bytes and at most 65535.
    public mutating func encrypt(_ plaintext: Data) throws -> Data {
        guard plaintext.count + noiseTagLength <= noiseMaxMessageLength else { throw NoiseError.badMessage }
        return try send.encrypt(ad: Data(), plaintext: plaintext)
    }

    /// Decrypts the next frame from the peer.
    public mutating func decrypt(_ ciphertext: Data) throws -> Data {
        guard ciphertext.count <= noiseMaxMessageLength else { throw NoiseError.badMessage }
        return try receive.decrypt(ad: Data(), ciphertext: ciphertext)
    }
}
