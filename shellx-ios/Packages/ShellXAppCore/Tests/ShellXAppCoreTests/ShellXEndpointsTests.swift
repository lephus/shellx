import Foundation
import XCTest
import ShellXAppCore

final class ShellXEndpointsTests: XCTestCase {
    private let key = "SHELLX_API_BASE"

    func testReleaseIgnoresOverride() {
        for value in ["https://staging.example.com", "http://127.0.0.1:8787", "http://localhost:8787"] {
            let endpoints = ShellXEndpoints(debugBuild: false, environment: [key: value])
            XCTAssertEqual(endpoints.apiBase, ShellXEndpoints.production, value)
        }
    }

    func testDebugUsesLoopbackOverride() {
        let endpoints = ShellXEndpoints(debugBuild: true, environment: [key: "http://127.0.0.1:8787"])
        XCTAssertEqual(endpoints.apiBase, URL(string: "http://127.0.0.1:8787")!)
    }

    func testDebugAcceptsEveryLoopbackForm() {
        for value in ["http://localhost:8787", "http://127.9.8.7:1", "http://[::1]:8787", "HTTP://LOCALHOST:8787"] {
            let endpoints = ShellXEndpoints(debugBuild: true, environment: [key: value])
            XCTAssertEqual(endpoints.apiBase, URL(string: value)!, value)
        }
    }

    func testDebugAcceptsHTTPS() {
        let endpoints = ShellXEndpoints(debugBuild: true, environment: [key: "https://staging.example.com"])
        XCTAssertEqual(endpoints.apiBase, URL(string: "https://staging.example.com")!)
    }

    func testDebugRejectsPlainHTTPRemote() {
        let endpoints = ShellXEndpoints(debugBuild: true, environment: [key: "http://192.168.1.5:8787"])
        XCTAssertEqual(endpoints.apiBase, ShellXEndpoints.production)
    }

    func testDebugRejectsLookalikesAndJunk() {
        let rejected = [
            "http://127.0.0.1.example.com", "http://localhost.example.com", "http://128.0.0.1",
            "http://127.0.0.256", "http://[::2]", "ftp://127.0.0.1", "https://", "not a url", "",
        ]
        for value in rejected {
            let endpoints = ShellXEndpoints(debugBuild: true, environment: [key: value])
            XCTAssertEqual(endpoints.apiBase, ShellXEndpoints.production, value)
        }
    }

    func testDebugDefaultsToProduction() {
        let endpoints = ShellXEndpoints(debugBuild: true, environment: [:])
        XCTAssertEqual(endpoints.apiBase, ShellXEndpoints.production)
        XCTAssertEqual(ShellXEndpoints.production, URL(string: "https://relay.shellx.pro")!)
    }
}
