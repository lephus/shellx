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
            let json: Data
            if let text = v["json_text"] as? String {
                json = Data(text.utf8)
            } else {
                json = try JSONSerialization.data(withJSONObject: try XCTUnwrap(v["json"]))
            }
            let expected: LinkCodecError
            switch v["error"] as? String {
            case "wrong_version": expected = .wrongVersion
            case "bad_json": expected = .badJSON(callId: v["call_id"] as? String)
            case "frame_too_large": expected = .frameTooLarge
            default: XCTFail("unknown error name in vector \(name)"); continue
            }
            XCTAssertThrowsError(try LinkCodec.decode(json), name) { XCTAssertEqual($0 as? LinkCodecError, expected, name) }
        }
    }

    func testBoundaryFrames() throws {
        let b = try XCTUnwrap(try Self.loadVectors()["boundary_frames"] as? [String: Any])
        let prefix = try XCTUnwrap(b["prefix"] as? String), suffix = try XCTUnwrap(b["suffix"] as? String)
        let cases = try XCTUnwrap(b["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 4)
        for c in cases {
            let name = c["name"] as? String ?? "?"
            var filler = ""
            var message = ""
            for f in try XCTUnwrap(c["filler"] as? [[String: Any]]) {
                let piece = String(repeating: try XCTUnwrap(f["text"] as? String), count: try XCTUnwrap(f["count"] as? Int))
                filler += piece; message += piece
            }
            let text = prefix + filler + suffix
            XCTAssertEqual(text.utf8.count, c["bytes"] as? Int, name)
            if let chars = c["chars"] as? Int { XCTAssertEqual(text.count, chars, name); XCTAssertLessThan(chars, LinkCodec.maxFrameBytes, name) }
            switch c["result"] as? String {
            case "ok":
                XCTAssertEqual(try LinkCodec.decode(Data(text.utf8)), .error(code: "x", message: message, callId: nil), name)
                XCTAssertEqual(try LinkCodec.encode(.error(code: "x", message: message, callId: nil)).count, text.utf8.count, name)
            case "frame_too_large":
                XCTAssertThrowsError(try LinkCodec.decode(Data(text.utf8)), name) { XCTAssertEqual($0 as? LinkCodecError, .frameTooLarge, name) }
                XCTAssertThrowsError(try LinkCodec.encode(.error(code: "x", message: message, callId: nil)), name) { XCTAssertEqual($0 as? LinkCodecError, .frameTooLarge, name) }
            default: XCTFail("unknown result in \(name)")
            }
        }
    }

    func testMultiByteCountsBytesNotCharacters() {
        // 40_000 two-byte characters: 40_000 characters < limit, 80_000 bytes > limit.
        let m = LinkMessage.error(code: "x", message: String(repeating: "\u{00E9}", count: 40_000), callId: nil)
        XCTAssertThrowsError(try LinkCodec.encode(m)) { XCTAssertEqual($0 as? LinkCodecError, .frameTooLarge) }
    }

    func testWithPreviewLimit() {
        let item = Self.item(preview: String(repeating: "\u{1F680}", count: 1_000)) // 4000 bytes
        XCTAssertEqual(item.withPreviewLimit(8192), item)
        let cut = item.withPreviewLimit(1022)
        XCTAssertEqual(cut.toolInputPreview?.utf8.count, 1020) // scalar boundary
        XCTAssertNil(item.withPreviewLimit(nil).toolInputPreview)
        XCTAssertEqual(item.withPreviewLimit(nil).requestId, item.requestId)
        XCTAssertNil(Self.item(preview: "x").withPreviewLimit(nil).toolInputPreview)
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
            XCTAssertThrowsError(try LinkCodec.decode(Data(s.utf8)), s) { XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil), s) }
        }
    }

    func testUnknownEnumValuesDecodeToOther() throws {
        let reply = try LinkCodec.decode(Data(
            #"{"v":1,"t":"agent.reply","call_id":"c1","request_id":"r","decision":{"kind":"permission","mode":"bypass2"}}"#.utf8))
        XCTAssertEqual(reply, .reply(callId: "c1", requestId: "r", decision: .permission(.other("bypass2"))))
        let plan = try LinkCodec.decode(Data(
            #"{"v":1,"t":"agent.reply","call_id":"c1","request_id":"r","decision":{"kind":"exit_plan","mode":"later"}}"#.utf8))
        XCTAssertEqual(plan, .reply(callId: "c1", requestId: "r", decision: .exitPlan(.other("later"), feedback: nil)))
        let kind = try LinkCodec.decode(Data(
            #"{"v":1,"t":"agent.reply","call_id":"c1","request_id":"r","decision":{"kind":"teleport"}}"#.utf8))
        XCTAssertEqual(kind, .reply(callId: "c1", requestId: "r", decision: .other(kind: "teleport")))
        let result = try LinkCodec.decode(Data(
            #"{"v":1,"t":"agent.reply.result","call_id":"c1","request_id":"r","outcome":"later"}"#.utf8))
        XCTAssertEqual(result, .replyResult(callId: "c1", requestId: "r", outcome: .other("later")))
        // Known strings still map to the named cases, and unknown ones keep their text on the wire.
        XCTAssertEqual(PermissionMode(wire: "once"), .once)
        XCTAssertEqual(ExitPlanMode(wire: "auto_accept"), .autoAccept)
        XCTAssertEqual(ReplyOutcome(wire: "already_handled"), .alreadyHandled)
        XCTAssertEqual(PendingItem.Kind(wire: "exit_plan"), .exitPlan)
        XCTAssertEqual(PendingItem.Kind(wire: "hologram").wire, "hologram")
    }

    func testBadJSONCarriesCallId() {
        func failure(_ text: String) -> LinkCodecError? {
            do { _ = try LinkCodec.decode(Data(text.utf8)); return nil } catch { return error as? LinkCodecError }
        }
        XCTAssertEqual(failure(#"{"v":1,"t":"agent.reply","call_id":"c1","decision":{"kind":"permission","mode":"once"}}"#),
                       .badJSON(callId: "c1"))
        XCTAssertEqual(failure(#"{"v":1,"t":"agent.reply","request_id":"r","decision":{"kind":"permission","mode":"once"}}"#),
                       .badJSON(callId: nil))
        XCTAssertEqual(failure(#"{"v":1,"t":"agent.snapshot.get","call_id":""}"#), .badJSON(callId: nil))
        let long = String(repeating: "c", count: LinkCodec.maxCallIdBytes + 1)
        XCTAssertEqual(failure(#"{"v":1,"t":"agent.snapshot.get","call_id":"\#(long)"}"#), .badJSON(callId: nil))
        let ok = String(repeating: "c", count: LinkCodec.maxCallIdBytes)
        XCTAssertNil(failure(#"{"v":1,"t":"agent.snapshot.get","call_id":"\#(ok)"}"#))
        // Encoding refuses a call id outside 1-64 bytes.
        XCTAssertThrowsError(try LinkCodec.encode(.snapshotGet(callId: long))) {
            XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil))
        }
    }

    func testPlanPreviewShrinksLikeToolInput() {
        let item = PendingItem(
            requestId: "r", kind: .exitPlan, agent: "claude", workspaceId: "w", workspaceTitle: "t",
            toolInputPreview: String(repeating: "\u{1F680}", count: 1_000),
            createdAtMs: 1, modes: ["manual"], planPreview: String(repeating: "\u{1F680}", count: 1_000))
        XCTAssertEqual(item.withPreviewLimit(8192), item)
        let cut = item.withPreviewLimit(1022)
        XCTAssertEqual(cut.toolInputPreview?.utf8.count, 1020)
        XCTAssertEqual(cut.planPreview?.utf8.count, 1020)
        let none = item.withPreviewLimit(nil)
        XCTAssertNil(none.toolInputPreview)
        XCTAssertNil(none.planPreview)
        XCTAssertEqual(none.modes, ["manual"], "only the previews are dropped")
        // The host's shrink steps apply to plan previews too.
        let plans = (0..<10).map { i in
            PendingItem(
                requestId: "r\(i)", kind: .exitPlan, agent: "claude", workspaceId: "w", workspaceTitle: "t",
                createdAtMs: 1, modes: ["manual"], planPreview: String(repeating: "a", count: 8_192))
        }
        XCTAssertThrowsError(try LinkCodec.encode(.snapshot(callId: "c1", revision: 1, pending: plans))) {
            XCTAssertEqual($0 as? LinkCodecError, .frameTooLarge)
        }
        XCTAssertNoThrow(try LinkCodec.encode(.snapshot(callId: "c1", revision: 1, pending: plans.map { $0.withPreviewLimit(1024) })))
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
        XCTAssertThrowsError(try LinkCodec.encode(.snapshot(callId: "c1", revision: 1, pending: [big]))) {
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
            if (try? LinkCodec.encode(.snapshot(callId: "c1", revision: 1, pending: [Self.item(preview: String(repeating: "a", count: mid))]))) != nil {
                lo = mid
            } else { hi = mid - 1 }
        }
        let data = try LinkCodec.encode(.snapshot(callId: "c1", revision: 1, pending: [Self.item(preview: String(repeating: "a", count: lo))]))
        XCTAssertEqual(data.count, LinkCodec.maxFrameBytes)
        XCTAssertEqual(try LinkCodec.decode(data), .snapshot(callId: "c1", revision: 1, pending: [Self.item(preview: String(repeating: "a", count: lo))]))
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
                kind: try XCTUnwrap(PendingItem.Kind(wire: try XCTUnwrap(d["kind"] as? String))),
                agent: try XCTUnwrap(d["agent"] as? String),
                workspaceId: try XCTUnwrap(d["workspace_id"] as? String),
                workspaceTitle: try XCTUnwrap(d["workspace_title"] as? String),
                toolName: d["tool_name"] as? String,
                toolInputPreview: d["tool_input_preview"] as? String,
                createdAtMs: try XCTUnwrap((d["created_at_ms"] as? NSNumber)?.int64Value),
                modes: try XCTUnwrap(d["modes"] as? [String]),
                questions: try (d["questions"] as? [[String: Any]])?.map(question),
                planPreview: d["plan_preview"] as? String)
        }
    }

    static func question(_ d: [String: Any]) throws -> PendingQuestion {
        PendingQuestion(
            id: try XCTUnwrap(d["id"] as? String),
            header: d["header"] as? String,
            prompt: try XCTUnwrap(d["prompt"] as? String),
            multiSelect: try XCTUnwrap(d["multi_select"] as? Bool),
            options: try XCTUnwrap(d["options"] as? [[String: Any]]).map {
                PendingQuestionOption(
                    id: try XCTUnwrap($0["id"] as? String), label: try XCTUnwrap($0["label"] as? String),
                    description: $0["description"] as? String)
            })
    }

    static func decision(_ d: [String: Any]) throws -> LinkDecision {
        let kind = try XCTUnwrap(d["kind"] as? String)
        switch kind {
        case "permission": return .permission(PermissionMode(wire: try XCTUnwrap(d["mode"] as? String)))
        case "question": return .question(selections: try XCTUnwrap(d["selections"] as? [String]))
        case "exit_plan":
            return .exitPlan(ExitPlanMode(wire: try XCTUnwrap(d["mode"] as? String)), feedback: d["feedback"] as? String)
        default: return .other(kind: kind)
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
        case "error": return .error(code: try s("code"), message: try s("message"), callId: m["call_id"] as? String)
        case "snapshot_get": return .snapshotGet(callId: try s("call_id"))
        case "snapshot":
            return .snapshot(callId: try s("call_id"), revision: try n("revision").intValue, pending: try pending(m["pending"]))
        case "changed":
            return .changed(revision: try n("revision").intValue, added: try pending(m["added"]),
                            resolved: try XCTUnwrap(m["resolved"] as? [String]))
        case "reply":
            return .reply(
                callId: try s("call_id"), requestId: try s("request_id"),
                decision: try decision(try XCTUnwrap(m["decision"] as? [String: Any], name)))
        case "reply_result":
            return .replyResult(callId: try s("call_id"), requestId: try s("request_id"), outcome: ReplyOutcome(wire: try s("outcome")))
        case "ping": return .ping(nonce: try n("nonce").uint64Value)
        case "pong": return .pong(nonce: try n("nonce").uint64Value)
        case "unknown": return .unknown(type: try s("type"))
        default:
            XCTFail("unknown vector case in \(name)")
            throw LinkCodecError.badJSON(callId: nil)
        }
    }
}
