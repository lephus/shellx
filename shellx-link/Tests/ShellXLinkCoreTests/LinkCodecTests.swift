import Foundation
import ShellXLinkCore
import XCTest

final class LinkCodecTests: XCTestCase {
    func testGoldenVectorsRoundTrip() throws {
        let file = try Self.loadVectors()
        let vectors = try XCTUnwrap(file["vectors"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(vectors.count, 10)
        for v in vectors {
            let name = v["name"] as? String ?? "?"
            let message = try Self.message(from: try XCTUnwrap(v["message"] as? [String: Any]), name)
            let json = try JSONSerialization.data(withJSONObject: try XCTUnwrap(v["json"]))
            XCTAssertEqual(try LinkCodec.decode(json), message, name)
            let encoded = try LinkCodec.encode(message)
            let a = try JSONSerialization.jsonObject(with: encoded) as? NSDictionary
            let b = try JSONSerialization.jsonObject(with: json) as? NSDictionary
            XCTAssertEqual(a, b, name)
        }
    }

    func testGoldenDecodeOnlyAndErrors() throws {
        let file = try Self.loadVectors()
        for v in try XCTUnwrap(file["decode_only"] as? [[String: Any]]) {
            let name = v["name"] as? String ?? "?"
            let message = try Self.message(from: try XCTUnwrap(v["message"] as? [String: Any]), name)
            let json = try JSONSerialization.data(withJSONObject: try XCTUnwrap(v["json"]))
            XCTAssertEqual(try LinkCodec.decode(json), message, name)
        }
        for v in try XCTUnwrap(file["decode_errors"] as? [[String: Any]]) {
            let name = v["name"] as? String ?? "?"
            let json = try JSONSerialization.data(withJSONObject: try XCTUnwrap(v["json"]))
            let expected: LinkCodecError = (v["error"] as? String) == "wrong_version" ? .wrongVersion : .badJSON
            XCTAssertThrowsError(try LinkCodec.decode(json), name) { XCTAssertEqual($0 as? LinkCodecError, expected, name) }
        }
    }

    func testUnknownTypeDecodesAsUnknown() throws {
        let m = try LinkCodec.decode(Data(#"{"v":1,"t":"future.thing"}"#.utf8))
        XCTAssertEqual(m, .unknown(type: "future.thing"))
    }

    func testWrongVersionThrows() {
        XCTAssertThrowsError(try LinkCodec.decode(Data(#"{"v":2,"t":"ping","nonce":1}"#.utf8))) {
            XCTAssertEqual($0 as? LinkCodecError, .wrongVersion)
        }
    }

    func testGarbageThrowsBadJSON() {
        for s in ["", "nope", "[1]", "{\"v\":\"1\",\"t\":\"ping\"}"] {
            XCTAssertThrowsError(try LinkCodec.decode(Data(s.utf8)), s) { XCTAssertEqual($0 as? LinkCodecError, .badJSON, s) }
        }
    }

    func testEncodingUnknownThrows() {
        XCTAssertThrowsError(try LinkCodec.encode(.unknown(type: "x"))) {
            XCTAssertEqual($0 as? LinkCodecError, .cannotEncodeUnknown)
        }
    }

    func testOversizeFrameRejected() throws {
        XCTAssertEqual(LinkCodec.maxFrameBytes, 65_519)
        let big = PendingItem(
            requestId: "r", kind: .permission, agent: "claude", workspaceId: "w", workspaceTitle: "t",
            toolName: "Bash", toolInputPreview: String(repeating: "a", count: 70_000), createdAtMs: 1)
        XCTAssertThrowsError(try LinkCodec.encode(.snapshot(revision: 1, pending: [big]))) {
            XCTAssertEqual($0 as? LinkCodecError, .frameTooLarge)
        }
        XCTAssertThrowsError(try LinkCodec.decode(Data(repeating: 0x20, count: 70_000))) {
            XCTAssertEqual($0 as? LinkCodecError, .frameTooLarge)
        }
    }

    func testFrameAtLimitIsAccepted() throws {
        var lo = 0, hi = 70_000
        // Find the largest preview that still fits.
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if (try? LinkCodec.encode(.snapshot(revision: 1, pending: [Self.item(preview: String(repeating: "a", count: mid))]))) != nil {
                lo = mid
            } else { hi = mid - 1 }
        }
        let data = try LinkCodec.encode(.snapshot(revision: 1, pending: [Self.item(preview: String(repeating: "a", count: lo))]))
        XCTAssertEqual(data.count, LinkCodec.maxFrameBytes)
        XCTAssertEqual(try LinkCodec.decode(data), .snapshot(revision: 1, pending: [Self.item(preview: String(repeating: "a", count: lo))]))
    }

    func testPreviewTruncationIsUTF8Safe() {
        let s = String(repeating: "\u{1F680}", count: 3_000) // 4 bytes each
        let t = PendingItem.truncatedPreview(s)
        XCTAssertLessThanOrEqual(t.utf8.count, PendingItem.maxPreviewBytes)
        XCTAssertEqual(t.utf8.count, 8192)
        XCTAssertEqual(PendingItem.truncatedPreview("short"), "short")
        let odd = "a" + String(repeating: "\u{00E9}", count: 5_000) // 1 + 2 bytes each
        let u = PendingItem.truncatedPreview(odd)
        XCTAssertLessThanOrEqual(u.utf8.count, 8192)
        XCTAssertTrue(odd.hasPrefix(u))
    }

    // MARK: - helpers

    static func item(preview: String) -> PendingItem {
        PendingItem(requestId: "r", kind: .permission, agent: "claude", workspaceId: "w", workspaceTitle: "t",
                    toolName: "Bash", toolInputPreview: preview, createdAtMs: 1)
    }

    static func loadVectors() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("spec/vectors/messages.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    static func pending(_ o: Any?) throws -> [PendingItem] {
        let arr = try XCTUnwrap(o as? [[String: Any]])
        return try arr.map { d in
            PendingItem(
                requestId: try XCTUnwrap(d["request_id"] as? String),
                kind: try XCTUnwrap(PendingItem.Kind(rawValue: try XCTUnwrap(d["kind"] as? String))),
                agent: try XCTUnwrap(d["agent"] as? String),
                workspaceId: try XCTUnwrap(d["workspace_id"] as? String),
                workspaceTitle: try XCTUnwrap(d["workspace_title"] as? String),
                toolName: d["tool_name"] as? String,
                toolInputPreview: d["tool_input_preview"] as? String,
                createdAtMs: try XCTUnwrap((d["created_at_ms"] as? NSNumber)?.int64Value))
        }
    }

    static func message(from m: [String: Any], _ name: String) throws -> LinkMessage {
        func s(_ k: String) throws -> String { try XCTUnwrap(m[k] as? String, "\(name).\(k)") }
        func n(_ k: String) throws -> NSNumber { try XCTUnwrap(m[k] as? NSNumber, "\(name).\(k)") }
        switch try s("case") {
        case "hello": return .hello(clientVersion: try s("client_version"), deviceName: try s("device_name"))
        case "welcome":
            return .welcome(protocolVersion: try n("protocol_version").intValue, hostVersion: try s("host_version"),
                            machineName: try s("machine_name"))
        case "error": return .error(code: try s("code"), message: try s("message"))
        case "snapshot_get": return .snapshotGet
        case "snapshot": return .snapshot(revision: try n("revision").intValue, pending: try pending(m["pending"]))
        case "changed":
            return .changed(revision: try n("revision").intValue, added: try pending(m["added"]),
                            resolved: try XCTUnwrap(m["resolved"] as? [String]))
        case "reply":
            return .reply(requestId: try s("request_id"), mode: try XCTUnwrap(PermissionMode(rawValue: try s("mode"))))
        case "reply_result":
            return .replyResult(requestId: try s("request_id"), outcome: try XCTUnwrap(ReplyOutcome(rawValue: try s("outcome"))))
        case "ping": return .ping(nonce: try n("nonce").uint64Value)
        case "pong": return .pong(nonce: try n("nonce").uint64Value)
        case "unknown": return .unknown(type: try s("type"))
        default: throw XCTSkip("unknown vector case in \(name)")
        }
    }
}
