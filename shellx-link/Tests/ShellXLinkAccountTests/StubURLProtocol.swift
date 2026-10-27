import Foundation
import ShellXLinkRelay

/// A request as the stub saw it (the body is read from the body stream).
struct StubRequest: Sendable {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
    var json: [String: Any]? { try? JSONSerialization.jsonObject(with: body) as? [String: Any] }
}

struct StubResponse: Sendable {
    var status: Int
    var body: Data
    init(_ status: Int, _ json: Any? = nil) {
        self.status = status
        self.body = json.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
    }
}

/// Serves canned answers to a `URLSession` without a network. One handler at a time: tests in
/// this target run serially.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (StubRequest) -> StubResponse)?
    nonisolated(unsafe) private static var seen: [StubRequest] = []

    static func install(_ handler: @escaping @Sendable (StubRequest) -> StubResponse) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
        seen = []
    }

    static var requests: [StubRequest] {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            stream.close()
        }
        let seenRequest = StubRequest(
            method: request.httpMethod ?? "GET", path: request.url?.path ?? "",
            headers: request.allHTTPHeaderFields ?? [:], body: body)
        Self.lock.lock()
        Self.seen.append(seenRequest)
        let handler = Self.handler
        Self.lock.unlock()
        let response = handler?(seenRequest) ?? StubResponse(500)
        let http = HTTPURLResponse(
            url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A ticket shaped like the relay's: `v2.<base64url claims>.<signature>`.
func stubTicket(slot: String, permission: String = "connect", role: String = "client") -> String {
    let claims: [String: Any] = [
        "slot": slot, "permission": permission, "role": role, "expires_at_unix": 1_900_000_000,
    ]
    let data = try! JSONSerialization.data(withJSONObject: claims)
    let payload = data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "v2.\(payload).c2ln"
}
