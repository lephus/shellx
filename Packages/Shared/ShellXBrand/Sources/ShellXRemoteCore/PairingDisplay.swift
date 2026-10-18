import Foundation

public enum PairingDisplay {
    public static func code(_ c: String) -> String { grouped(c, 3) }
    public static func fingerprint(_ f: String) -> String { grouped(f, 4) }

    private static func grouped(_ s: String, _ n: Int) -> String {
        let chars = Array(s)
        return stride(from: 0, to: chars.count, by: n).map { String(chars[$0..<min($0 + n, chars.count)]) }.joined(separator: " ")
    }
}
