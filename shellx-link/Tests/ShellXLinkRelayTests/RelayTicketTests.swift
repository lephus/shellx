import ShellXLinkRelay
import XCTest

/// A relay ticket is a bearer secret: no description, debug description, mirror or `dump` may print it.
final class RelayTicketTests: XCTestCase {
    func testRenderingsNeverContainTheTicket() {
        // Shaped like a `v2.<claims>.<signature>` ticket; no relay accepts it.
        let signature = "dGVzdC1zaWduYXR1cmUtbm90LWEtc2VjcmV0"
        let secret = "v2.eyJzbG90Ijoic2hlbGx4LWxpbmstdGVzdCJ9.\(signature)"
        let ticket = RelayTicket(ticket: secret, expiresAtUnix: 1_900_000_000)
        var dumped = ""
        dump(ticket, to: &dumped)
        let mirrored = Mirror(reflecting: ticket).children.map { "\($0.label ?? ""): \($0.value)" }.joined(separator: ", ")

        let renderings: KeyValuePairs<String, String> = [
            "interpolation": "\(ticket)",
            "String(describing:)": String(describing: ticket),
            "String(reflecting:)": String(reflecting: ticket),
            "dump": dumped,
            "mirror": mirrored,
        ]
        for (name, text) in renderings {
            // Failure messages name the rendering, never the text that leaked.
            XCTAssertFalse(text.contains(secret), "\(name) printed the ticket")
            XCTAssertFalse(text.contains(signature), "\(name) printed the ticket's signature")
        }
        XCTAssertTrue("\(ticket)".contains("1900000000"), "the description still says when the ticket expires")
        XCTAssertTrue(ticket.ticket == secret, "the stored ticket is unchanged")
    }

    func testClaimsParseSlotPermissionExpiry() {
        let minter = TestTicketMinter(secret: "0123456789abcdef0123456789abcdef")
        let register = minter.mint(.register, slot: "slot-a", now: Date(timeIntervalSince1970: 1_000), lifetime: 90)
        XCTAssertEqual(
            register.claims,
            RelayTicketClaims(
                slot: "slot-a", permission: "register", role: "daemon", expiresAtUnix: 1_090, issuedAtUnix: 1_000))
        let connect = minter.mint(.connect, slot: "slot-b", now: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(connect.claims?.permission, "connect")
        XCTAssertEqual(connect.claims?.role, "client")
        XCTAssertEqual(connect.claims?.expiresAtUnix, 2_120)
        XCTAssertEqual(connect.claims?.issuedAtUnix, 2_000)
        // A ticket without `issued_at_unix` still parses; the renewal then falls back to the local clock.
        let older = TestTicketMinter.base64URL(Data(
            #"{"slot":"s","permission":"register","role":"daemon","expires_at_unix":5}"#.utf8))
        XCTAssertEqual(
            RelayTicket(ticket: "v2.\(older).sig", expiresAtUnix: 5).claims,
            RelayTicketClaims(slot: "s", permission: "register", role: "daemon", expiresAtUnix: 5))
    }

    func testClaimsNilForMalformedTicket() {
        let notJSON = TestTicketMinter.base64URL(Data("not json".utf8))
        let missing = TestTicketMinter.base64URL(Data(#"{"slot":"s"}"#.utf8))
        for text in [
            "", "garbage", "v2.only", "v2..sig", "v1.\(missing).sig", "v2.\(notJSON).sig",
            "v2.\(missing).sig", "v2.!!!.sig",
        ] {
            XCTAssertNil(RelayTicket(ticket: text, expiresAtUnix: 0).claims)
        }
    }
}
