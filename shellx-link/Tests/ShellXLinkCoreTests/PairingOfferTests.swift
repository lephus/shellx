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

    func testProofIsBoundToHostKeyAndSlot() throws {
        let v = try vector()
        let genuine = offer(v)
        // An attacker swaps the QR's host key (same code): the proof the phone makes from it must
        // not verify against the Mac's own offer.
        var swappedKey = genuine
        swappedKey.hostKey[0] ^= 1
        let forged = swappedKey.proof(clientKey: v.clientKey)
        XCTAssertNotEqual(forged, genuine.proof(clientKey: v.clientKey))
        XCTAssertFalse(genuine.verify(proof: forged, clientKey: v.clientKey))
        var swappedSlot = genuine
        swappedSlot.linkSlot = "attacker-slot"
        XCTAssertFalse(genuine.verify(proof: swappedSlot.proof(clientKey: v.clientKey), clientKey: v.clientKey))
    }

    func testParseRejectsStrictFieldClasses() throws {
        let v = try vector()
        let good = offer(v).uri
        func fails(_ uri: String, _ expected: PairingOfferError? = nil, line: UInt = #line) {
            XCTAssertThrowsError(try PairingOffer(uri: uri), line: line) { error in
                if let expected { XCTAssertEqual(error as? PairingOfferError, expected, line: line) }
            }
        }
        let m = "m=\(v.machineID)", s = "s=slot-test-1", n = "n=Phu%27s%20Mac"
        let k = "k=QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8"
        // m: only [A-Za-z0-9-], 1...64.
        fails(good.replacingOccurrences(of: m, with: "m=a_b"), .badField("m"))
        fails(good.replacingOccurrences(of: m, with: "m=a%2Fb"), .badField("m"))
        fails(good.replacingOccurrences(of: m, with: "m=\(String(repeating: "a", count: 65))"), .badField("m"))
        fails(good.replacingOccurrences(of: m, with: "m="), .badField("m"))
        // s: base64url alphabet only, 1...64.
        fails(good.replacingOccurrences(of: s, with: "s=a.b"), .badField("s"))
        fails(good.replacingOccurrences(of: s, with: "s=a%20b"), .badField("s"))
        fails(good.replacingOccurrences(of: s, with: "s=\(String(repeating: "a", count: 65))"), .badField("s"))
        // k and c: base64url alphabet only (no +, /, =).
        let plus = "k=QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdX+8"
        fails(good.replacingOccurrences(of: k, with: plus), .badField("k"))
        fails(good.replacingOccurrences(of: k, with: "k=QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdX%2F8"), .badField("k"))
        fails(good.replacingOccurrences(of: k, with: k + "%3D"), .badField("k"))
        fails(good.replacingOccurrences(of: "c=AAECAwQFBgcICQoLDA0ODw", with: "c=AAECAwQFBgcICQoLDA0OD%2B"), .badField("c"))
        // n: 1...100 scalars, no controls, no bidi overrides or isolates.
        fails(good.replacingOccurrences(of: n, with: "n="), .badField("n"))
        fails(good.replacingOccurrences(of: n, with: "n=\(String(repeating: "a", count: 101))"), .badField("n"))
        fails(good.replacingOccurrences(of: n, with: "n=a%0Ab"), .badField("n"))
        fails(good.replacingOccurrences(of: n, with: "n=a%00b"), .badField("n"))
        fails(good.replacingOccurrences(of: n, with: "n=a%7Fb"), .badField("n"))
        for scalar in ["%E2%80%AA", "%E2%80%AE", "%E2%81%A6", "%E2%81%A9"] {
            fails(good.replacingOccurrences(of: n, with: "n=a\(scalar)b"), .badField("n"))
        }
        let hundred = String(repeating: "a", count: 100)
        XCTAssertNoThrow(try PairingOffer(uri: good.replacingOccurrences(of: n, with: "n=\(hundred)")))
        XCTAssertNoThrow(try PairingOffer(uri: good.replacingOccurrences(of: n, with: "n=%E2%80%8F%20ok")))
        // Structure: no path, port, userinfo, fragment, duplicate keys.
        fails(good.replacingOccurrences(of: "pair?", with: "pair/x?"), .badURI)
        fails(good.replacingOccurrences(of: "pair?", with: "pair/?"), .badURI)
        fails(good.replacingOccurrences(of: "//pair?", with: "//pair:80?"), .badURI)
        fails(good.replacingOccurrences(of: "//pair?", with: "//user@pair?"), .badURI)
        fails(good + "#frag", .badURI)
        fails(good + "&n=Other", .badField("n"))
        fails(good + "&k=\(String(k.dropFirst(2)))", .badField("k"))
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
