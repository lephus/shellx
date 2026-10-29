import CryptoKit
import Foundation

/// Why a pairing URI was refused.
public enum PairingOfferError: Error, Equatable, Sendable {
    /// Not a `shellx-link://pair` URI.
    case badURI
    /// The `v` field is not `1`.
    case unsupportedVersion
    /// The named query field is missing, empty or malformed.
    case badField(String)
}

/// What a Mac shows as a QR code so a phone can pair with it (PROTOCOL.md section 9).
///
/// The offer carries the host key the phone will trust: it travels only through the QR code, never
/// through the relay. `code` is a one-time secret that keys the pairing proof; it is never logged or
/// printed (`description` and the mirror leave it out).
public struct PairingOffer: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    /// How long an offer stays valid, in seconds.
    public static let lifetime: TimeInterval = 300

    public var machineID: String
    public var linkSlot: String
    /// The host's 32-byte Noise static public key.
    public var hostKey: Data
    /// The 16-byte one-time pairing code.
    public var code: Data
    public var machineName: String

    public init(machineID: String, linkSlot: String, hostKey: Data, code: Data, machineName: String) {
        self.machineID = machineID
        self.linkSlot = linkSlot
        self.hostKey = hostKey
        self.code = code
        self.machineName = machineName
    }

    /// A new offer with a random code from `SystemRandomNumberGenerator`.
    public static func make(machineID: String, linkSlot: String, hostKey: Data, machineName: String) -> PairingOffer {
        var generator = SystemRandomNumberGenerator()
        let code = Data((0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        return PairingOffer(
            machineID: machineID, linkSlot: linkSlot, hostKey: hostKey, code: code, machineName: machineName)
    }

    /// `shellx-link://pair?v=1&m=<machine_id>&s=<link_slot>&k=<host key>&c=<code>&n=<name>`:
    /// keys and code are base64url without padding, the name is percent-encoded.
    public var uri: String {
        "shellx-link://pair?v=1&m=\(Self.encode(machineID))&s=\(Self.encode(linkSlot))"
            + "&k=\(Self.base64URL(hostKey))&c=\(Self.base64URL(code))&n=\(Self.encode(machineName))"
    }

    /// Parses an offer URI.
    public init(uri: String) throws {
        guard let parts = URLComponents(string: uri), parts.scheme == "shellx-link", parts.host == "pair",
            parts.path.isEmpty, parts.port == nil, parts.user == nil, parts.password == nil,
            parts.fragment == nil
        else { throw PairingOfferError.badURI }
        var fields: [String: String] = [:]
        for item in parts.queryItems ?? [] {
            guard fields[item.name] == nil else { throw PairingOfferError.badField(item.name) }
            fields[item.name] = item.value ?? ""
        }
        guard fields["v"] == "1" else {
            if fields["v"] == nil { throw PairingOfferError.badField("v") }
            throw PairingOfferError.unsupportedVersion
        }
        func text(_ name: String) throws -> String {
            guard let value = fields[name], !value.isEmpty else { throw PairingOfferError.badField(name) }
            return value
        }
        func bytes(_ name: String, count: Int) throws -> Data {
            let value = try text(name)
            guard Self.isBase64URL(value), let data = Self.decodeBase64URL(value), data.count == count
            else { throw PairingOfferError.badField(name) }
            return data
        }
        func limited(_ name: String, _ allowed: (Character) -> Bool) throws -> String {
            let value = try text(name)
            guard value.count <= 64, value.allSatisfy(allowed) else { throw PairingOfferError.badField(name) }
            return value
        }
        let machineID = try limited("m") { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        let linkSlot = try limited("s") { Self.isBase64URL(String($0)) }
        let hostKey = try bytes("k", count: 32)
        let code = try bytes("c", count: 16)
        let name = try text("n")
        let scalars = name.unicodeScalars
        guard scalars.count <= 100, scalars.allSatisfy({ !Self.isForbiddenInName($0) }) else {
            throw PairingOfferError.badField("n")
        }
        self.init(machineID: machineID, linkSlot: linkSlot, hostKey: hostKey, code: code, machineName: name)
    }

    /// Control characters and the bidi overrides and isolates (U+202A-U+202E, U+2066-U+2069), which
    /// could make a machine name display as something else in the approval prompt.
    private static func isForbiddenInName(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .control
            || (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
    }

    private static func isBase64URL(_ text: String) -> Bool {
        text.utf8.allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A)
                || $0 == 0x2D || $0 == 0x5F
        }
    }

    private static func message(machineID: String, linkSlot: String, hostKey: Data, clientKey: Data) -> Data {
        var message = Data("shellx-link-pair/1".utf8)
        message.append(0)
        message.append(Data(machineID.utf8))
        message.append(0)
        message.append(Data(linkSlot.utf8))
        message.append(0)
        message.append(hostKey)
        message.append(clientKey)
        return message
    }

    /// The phone's proof that it scanned this offer: HMAC-SHA256 keyed with `code` over
    /// `"shellx-link-pair/1" 0x00 machineID 0x00 linkSlot 0x00 hostKey clientKey`.
    public func proof(clientKey: Data) -> Data {
        Data(
            HMAC<SHA256>.authenticationCode(
                for: Self.message(machineID: machineID, linkSlot: linkSlot, hostKey: hostKey, clientKey: clientKey),
                using: SymmetricKey(data: code)))
    }

    /// Checks a proof in constant time.
    public func verify(proof: Data, clientKey: Data) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(
            proof, authenticating: Self.message(machineID: machineID, linkSlot: linkSlot, hostKey: hostKey, clientKey: clientKey),
            using: SymmetricKey(data: code))
    }

    public var description: String { "PairingOffer(machine: \(machineID), slot: \(linkSlot), <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["machineID": machineID, "linkSlot": linkSlot, "machineName": machineName, "code": "<redacted>"],
            displayStyle: .struct)
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodeBase64URL(_ text: String) -> Data? {
        guard !text.contains("=") else { return nil }
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
