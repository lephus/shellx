@testable import ShellXLinkRelay
import XCTest

final class RelayEndpointTests: XCTestCase {
    func testPlainWebSocketRefusedForRemoteHost() {
        for text in [
            "ws://relay.example.com", "http://relay.example.com/v2/relay", "relay+ws://relay.example.com",
            "ws://10.0.0.5:8080", "ws://192.168.1.2", "ws://[2001:db8::1]/", "ws://localhost.example.com",
            "ws://127.0.0.1.example.com",
        ] {
            XCTAssertThrowsError(try RelayEndpoint.control(URL(string: text)!), text) { error in
                guard case RelayError.insecureTransport = error else {
                    return XCTFail("\(text) threw \(error)")
                }
            }
        }
        XCTAssertThrowsError(try RelayEndpoint.control(URL(string: "ws://relay.example.com")!)) { error in
            XCTAssertEqual(error as? RelayError, .insecureTransport(scheme: "ws"))
        }
    }

    func testLoopbackPlainAllowed() throws {
        for text in [
            "ws://localhost:1/x", "ws://LOCALHOST", "http://127.0.0.1:9", "relay+ws://127.9.8.7",
            "ws://[::1]:8080/v1/relay",
        ] {
            XCTAssertEqual(try RelayEndpoint.control(URL(string: text)!).scheme, "ws", text)
        }
        XCTAssertEqual(try RelayEndpoint.control(URL(string: "ws://127.0.0.1:9")!).path, "/v1/relay")
    }

    func testSecureSchemesAllowed() throws {
        for text in ["wss://relay.example.com", "https://relay.example.com", "relay+wss://relay.example.com"] {
            XCTAssertEqual(try RelayEndpoint.control(URL(string: text)!).scheme, "wss", text)
        }
        XCTAssertEqual(
            try RelayEndpoint.control(URL(string: "https://relay.example.com/v2/relay")!).path, "/v2/relay")
    }
}
