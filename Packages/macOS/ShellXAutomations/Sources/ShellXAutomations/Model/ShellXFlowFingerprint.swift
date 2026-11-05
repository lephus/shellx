import CryptoKit
public import Foundation

/// Fingerprint that ties a stored flow to the `SKILL.md` text it was drawn from.
public enum ShellXFlowFingerprint {
    /// Lowercase SHA-256 hex of the UTF-8 text.
    public static func of(_ markdown: String) -> String {
        SHA256.hash(data: Data(markdown.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
