import Foundation
import XCTest

@testable import ShellXLinkCore

final class PairingOfferTests: XCTestCase {
    private struct Vector {
        var machineID: String
        var linkSlot: String
        var machineName: String
        var hostKey: Data
        var code: Data
        var clientKey: Data
        var proof: Data
    }

    private func vector() throws -> Vector {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("spec/vectors/pairing.json")
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: String])
        func b64u(_ key: String) throws -> Data {
            var s = try XCTUnwrap(json[key]).replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            s += String(repeating: "=", count: (4 - s.count % 4) % 4)
            return try XCTUnwrap(Data(base64Encoded: s))
        }
        return Vector(
            machineID: try XCTUnwrap(json["machine_id"]), linkSlot: try XCTUnwrap(json["link_slot"]),
            machineName: try XCTUnwrap(json["machine_name"]), hostKey: try b64u("host_key_b64url"),
            code: try b64u("code_b64url"), clientKey: try b64u("client_key_b64url"),
            proof: try b64u("proof_b64url"))
    }

    private func offer(_ v: Vector) -> PairingOffer {
        PairingOffer(
            machineID: v.machineID, linkSlot: v.linkSlot, hostKey: v.hostKey, code: v.code,
            machineName: v.machineName)
    }

    func testURIRoundTrip() throws {
        let v = try vector()
        let original = offer(v)
        let uri = original.uri
        XCTAssertTrue(uri.hasPrefix("shellx-link://pair?v=1&m=\(v.machineID)&s=\(v.linkSlot)&k="), uri)
        XCTAssertFalse(uri.contains("+"))
        XCTAssertTrue(uri.hasSuffix("&n=Phu%27s%20Mac"), uri)
        XCTAssertEqual(try PairingOffer(uri: uri), original)
        let made = PairingOffer.make(
            machineID: v.machineID, linkSlot: v.linkSlot, hostKey: v.hostKey, machineName: "Mac é ü & =")
        XCTAssertEqual(made.code.count, 16)
        XCTAssertEqual(try PairingOffer(uri: made.uri), made)
        XCTAssertNotEqual(
            made.code,
            PairingOffer.make(machineID: v.machineID, linkSlot: v.linkSlot, hostKey: v.hostKey, machineName: "x").code)
        XCTAssertEqual(PairingOffer.lifetime, 300)
    }

    func testProofMatchesVector() throws {
        let v = try vector()
        let o = offer(v)
        XCTAssertEqual(o.proof(clientKey: v.clientKey), v.proof)
        XCTAssertTrue(o.verify(proof: v.proof, clientKey: v.clientKey))
    }

    func testVerifyRejectsOtherKeyOrMachine() throws {
        let v = try vector()
        let o = offer(v)
        var otherKey = v.clientKey
        otherKey[0] ^= 1
        XCTAssertFalse(o.verify(proof: v.proof, clientKey: otherKey))
        var other = o
        other.machineID = "00000000-0000-4000-8000-000000000000"
        XCTAssertFalse(other.verify(proof: v.proof, clientKey: v.clientKey))
        XCTAssertFalse(o.verify(proof: Data(v.proof.dropLast()), clientKey: v.clientKey))
    }

    func testParseRejectsBadFields() throws {
        let v = try vector()
        let good = offer(v).uri
        func fails(_ uri: String, _ expected: PairingOfferError, line: UInt = #line) {
            XCTAssertThrowsError(try PairingOffer(uri: uri), line: line) { error in
                XCTAssertEqual(error as? PairingOfferError, expected, line: line)
            }
        }
        fails("https://example.com/pair?v=1", .badURI)
        fails("not a uri", .badURI)
        fails(good.replacingOccurrences(of: "v=1", with: "v=2"), .unsupportedVersion)
        let short = Data(v.hostKey.dropLast()).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        fails(good.replacingOccurrences(of: "k=QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8", with: "k=\(short)"), .badField("k"))
        let noCode = good.components(separatedBy: "&").filter { !$0.hasPrefix("c=") }.joined(separator: "&")
        fails(noCode, .badField("c"))
        fails(good.replacingOccurrences(of: "&s=slot-test-1", with: ""), .badField("s"))
    }

    func testDescriptionHidesCode() throws {
        let o = offer(try vector())
        let code = "AAECAwQFBgcICQoLDA0ODw"
        for text in [o.description, o.debugDescription, "\(o)", String(reflecting: o)] {
            XCTAssertFalse(text.contains(code), text)
        }
        var dumped = ""
        dump(o, to: &dumped)
        XCTAssertFalse(dumped.contains(code))
    }
}
