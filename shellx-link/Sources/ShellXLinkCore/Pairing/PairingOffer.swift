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
        guard let parts = URLComponents(string: uri), parts.scheme == "shellx-link", parts.host == "pair"
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
            guard let data = Self.decodeBase64URL(try text(name)), data.count == count
            else { throw PairingOfferError.badField(name) }
            return data
        }
        self.init(
            machineID: try text("m"), linkSlot: try text("s"), hostKey: try bytes("k", count: 32),
            code: try bytes("c", count: 16), machineName: try text("n"))
    }

    private static func message(machineID: String, clientKey: Data) -> Data {
        var message = Data("shellx-link-pair/1".utf8)
        message.append(0)
        message.append(Data(machineID.utf8))
        message.append(0)
        message.append(clientKey)
        return message
    }

    /// The phone's proof that it scanned this offer: HMAC-SHA256 keyed with `code` over
    /// `"shellx-link-pair/1" 0x00 machineID 0x00 clientKey`.
    public func proof(clientKey: Data) -> Data {
        Data(
            HMAC<SHA256>.authenticationCode(
                for: Self.message(machineID: machineID, clientKey: clientKey),
                using: SymmetricKey(data: code)))
    }

    /// Checks a proof in constant time.
    public func verify(proof: Data, clientKey: Data) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(
            proof, authenticating: Self.message(machineID: machineID, clientKey: clientKey),
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
