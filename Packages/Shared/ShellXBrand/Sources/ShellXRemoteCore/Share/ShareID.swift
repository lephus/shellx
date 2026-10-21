import Foundation

/// Share ids: 8 characters of a Crockford-style base32 alphabet (no i, l, o, u).
/// The client proposes the id because it salts the `access` derivation.
public enum ShareID {
    public static let alphabet = Array("0123456789abcdefghjkmnpqrstvwxyz")
    public static let length = 8

    /// 8 random characters; 32 symbols divide the draw evenly, so there is no modulo bias.
    public static func random() -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &rng)] })
    }

    /// `xxxx-xxxx` for people; any dash already present is dropped first. Anything but 8 characters is returned unchanged.
    public static func display(_ id: String) -> String {
        let plain = id.replacingOccurrences(of: "-", with: "")
        guard plain.count == length else { return id }
        return "\(plain.prefix(4))-\(plain.suffix(4))"
    }
}
