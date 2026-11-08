import CryptoKit
import Foundation

/// Small crypto helpers for the Google and Apple sign-in flows.
public enum AuthCrypto {
    /// Base64 with the URL alphabet (`-_`) and no padding.
    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// `base64URL` of `byteCount` secure random bytes.
    public static func randomToken(byteCount: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return base64URL(Data(bytes))
    }

    /// PKCE S256: `base64URL(SHA-256(verifier))`.
    public static func pkceChallenge(verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Lowercase hex of SHA-256 over the UTF-8 text (the nonce Apple gets).
    public static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
