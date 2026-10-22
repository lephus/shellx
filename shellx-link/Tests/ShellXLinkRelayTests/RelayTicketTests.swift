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
}
