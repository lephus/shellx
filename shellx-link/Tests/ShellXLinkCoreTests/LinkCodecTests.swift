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
        XCTAssertEqual(m, .unknown(type: "future.thing", callId: nil))
    }

    /// A call of a later version keeps its `call_id`, so the host can answer it `unsupported` (PROTOCOL.md 3);
    /// an invalid one is dropped, never `bad_json`.
    func testUnknownTypeKeepsAValidCallId() throws {
        func decode(_ text: String) throws -> LinkMessage { try LinkCodec.decode(Data(text.utf8)) }
        XCTAssertEqual(try decode(#"{"v":1,"t":"future.call","call_id":"c1","x":{}}"#),
                       .unknown(type: "future.call", callId: "c1"))
        let tooLong = String(repeating: "c", count: LinkCodec.maxCallIdBytes + 1)
        for bad in [#""""#, #""\#(tooLong)""#, "7", "null", "[\"c1\"]"] {
            XCTAssertEqual(try decode(#"{"v":1,"t":"future.call","call_id":\#(bad)}"#),
                           .unknown(type: "future.call", callId: nil), bad)
        }
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
        XCTAssertThrowsError(try LinkCodec.encode(.unknown(type: "x", callId: "c1"))) {
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

    func testChatEntryTextTruncated() throws {
        // 2 MB of multi-byte text: the cut lands on a scalar boundary and says so.
        let big = String(repeating: "\u{1F600}x\u{00E9}", count: 2_000_000 / 7)
        XCTAssertGreaterThan(big.utf8.count, 1_900_000)
        let cut = ChatEntry.cut(big)
        XCTAssertTrue(cut.truncated)
        XCTAssertLessThanOrEqual(cut.text.utf8.count, ChatEntry.maxTextBytes)
        XCTAssertGreaterThan(cut.text.utf8.count, ChatEntry.maxTextBytes - 4)
        XCTAssertNotNil(String(data: Data(cut.text.utf8), encoding: .utf8))
        XCTAssertTrue(big.hasPrefix(cut.text))

        let short = ChatEntry.cut("hello")
        XCTAssertEqual(short.text, "hello")
        XCTAssertFalse(short.truncated)
        let exact = String(repeating: "a", count: ChatEntry.maxTextBytes)
        XCTAssertEqual(ChatEntry.cut(exact).text, exact)
        XCTAssertFalse(ChatEntry.cut(exact).truncated)
    }

    func testNewerEntryRevisionWins() {
        let old = ChatEntry(id: "e", rev: 1, seq: 1, role: .agent, kind: .prose, text: "old", tsMs: 1)
        var fresh = old
        fresh.rev = 2
        fresh.text = "new"
        // A stale history entry applied after a newer pushed one, and the other way round.
        XCTAssertEqual(ChatEntry.newer(fresh, old).text, "new")
        XCTAssertEqual(ChatEntry.newer(old, fresh).text, "new")
        XCTAssertEqual(ChatEntry.newer(old, old), old)
    }

    func testChatEntryNeedsRev() {
        let json = Data(#"{"v":1,"t":"chat.entries","session_id":"s","entries":[{"id":"e","seq":1,"role":"user","kind":"prose","text":"x","ts_ms":1}]}"#.utf8)
        XCTAssertThrowsError(try LinkCodec.decode(json)) { XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil)) }
    }

    func testChatMessagesNeedValidCallIds() throws {
        let long = String(repeating: "c", count: 65)
        XCTAssertThrowsError(try LinkCodec.encode(.chatSend(callId: long, sessionId: "s", text: "x", attachments: [])))
        XCTAssertThrowsError(try LinkCodec.encode(.sessionsGet(callId: "")))
        let json = Data(#"{"v":1,"t":"chat.history.get","session_id":"s","limit":5}"#.utf8)
        XCTAssertThrowsError(try LinkCodec.decode(json)) { XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil)) }
    }

    // MARK: - Attachments (PROTOCOL.md section 5, "Attachments")

    private static let digest = Data((0..<32).map { UInt8($0) })

    func testAttachmentFramesRoundTrip() throws {
        let chunk = Data("hello world".utf8)
        let messages: [LinkMessage] = [
            .welcome(protocolVersion: 1, hostVersion: "1.5.0", machineName: "Mac", features: [ShellXLink.attachmentsFeature]),
            .chatSend(callId: "c1", sessionId: "s-1", text: "fix this", attachments: ["a1", "a2"]),
            .chatSend(callId: "c2", sessionId: "s-1", text: "", attachments: ["a1"]),
            .attachBegin(callId: "c3", kind: .image, name: "shot.jpg", size: 1_234),
            .attachBegin(callId: "c3", kind: .file, name: "notes.txt", size: ShellXLink.maxAttachmentBytes),
            .attachBegin(callId: "c3", kind: .other("audio"), name: "memo.m4a", size: 1),
            .attachReady(callId: "c3", attachmentId: "a1"),
            .attachChunk(callId: "c4", attachmentId: "a1", offset: 0, data: chunk),
            .attachChunk(callId: "c4", attachmentId: "a1", offset: 11, data: Data("A".utf8)),
            .attachChunkResult(callId: "c4", attachmentId: "a1", received: 12),
            .attachEnd(callId: "c5", attachmentId: "a1", sha256: Self.digest),
            .attachEndResult(callId: "c5", attachmentId: "a1"),
        ]
        for message in messages {
            XCTAssertEqual(try LinkCodec.decode(try LinkCodec.encode(message)), message, "\(message)")
        }
    }

    func testAttachmentWireForms() throws {
        func object(_ m: LinkMessage) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: try LinkCodec.encode(m)) as? [String: Any])
        }
        let chunk = try object(.attachChunk(callId: "c1", attachmentId: "a1", offset: 0, data: Data([0x41])))
        XCTAssertEqual(chunk["t"] as? String, "attach.chunk")
        XCTAssertEqual(chunk["data"] as? String, "QQ==", "standard base64 with padding")
        let end = try object(.attachEnd(callId: "c1", attachmentId: "a1", sha256: Self.digest))
        XCTAssertEqual(end["sha256"] as? String, "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
                       "64 lowercase hex characters")
        let begin = try object(.attachBegin(callId: "c1", kind: .image, name: "a.jpg", size: 3))
        XCTAssertEqual(begin["kind"] as? String, "image")
        XCTAssertEqual(AttachmentKind(wire: "file"), .file)
        XCTAssertEqual(AttachmentKind(wire: "hologram"), .other("hologram"))
        XCTAssertEqual(AttachmentKind.other("hologram").wire, "hologram")
    }

    func testWelcomeAndSendWithoutNewFieldsStillDecode() throws {
        func decode(_ text: String) throws -> LinkMessage { try LinkCodec.decode(Data(text.utf8)) }
        XCTAssertEqual(
            try decode(#"{"v":1,"t":"welcome","protocol_version":1,"host_version":"1","machine_name":"Mac"}"#),
            .welcome(protocolVersion: 1, hostVersion: "1", machineName: "Mac", features: []))
        XCTAssertEqual(
            try decode(#"{"v":1,"t":"chat.send","call_id":"c1","session_id":"s","text":"x"}"#),
            .chatSend(callId: "c1", sessionId: "s", text: "x", attachments: []))
        // Empty arrays are not written.
        func keys(_ m: LinkMessage) throws -> Set<String> {
            Set(try XCTUnwrap(JSONSerialization.jsonObject(with: try LinkCodec.encode(m)) as? [String: Any]).keys)
        }
        XCTAssertEqual(try keys(.welcome(protocolVersion: 1, hostVersion: "1", machineName: "Mac", features: [])),
                       ["v", "t", "protocol_version", "host_version", "machine_name"])
        XCTAssertEqual(try keys(.chatSend(callId: "c1", sessionId: "s", text: "x", attachments: [])),
                       ["v", "t", "call_id", "session_id", "text"])
        XCTAssertTrue(try keys(.welcome(protocolVersion: 1, hostVersion: "1", machineName: "Mac", features: ["attachments"]))
            .contains("features"))
        XCTAssertTrue(try keys(.chatSend(callId: "c1", sessionId: "s", text: "x", attachments: ["a1"])).contains("attachments"))
    }

    func testFullChunkFitsAFrame() throws {
        let id = String(repeating: "i", count: LinkCodec.maxCallIdBytes)
        let data = Data((0..<ShellXLink.maxAttachmentChunkBytes).map { UInt8(truncatingIfNeeded: $0) })
        let message = LinkMessage.attachChunk(
            callId: id, attachmentId: id, offset: ShellXLink.maxAttachmentBytes, data: data)
        let frame = try LinkCodec.encode(message)
        XCTAssertLessThanOrEqual(frame.count, LinkCodec.maxFrameBytes)
        XCTAssertEqual(try LinkCodec.decode(frame), message)
    }

    func testChunkDataMustBeBase64() {
        func failure(_ data: String) -> LinkCodecError? {
            let text = #"{"v":1,"t":"attach.chunk","call_id":"c1","attachment_id":"a1","offset":0,"data":"\#(data)"}"#
            do { _ = try LinkCodec.decode(Data(text.utf8)); return nil } catch { return error as? LinkCodecError }
        }
        for bad in ["%%%", "QQ", "QQ=", "Q Q==", "QQ==\\n", "-_8=", "QR=="] {
            XCTAssertEqual(failure(bad), .badJSON(callId: "c1"), bad)
        }
        XCTAssertNil(failure("QQ=="))
        XCTAssertNil(failure(""), "an empty chunk is a rule of the host (section 5), not of the codec")
        // A data field that is not a string at all.
        let number = Data(#"{"v":1,"t":"attach.chunk","call_id":"c1","attachment_id":"a1","offset":0,"data":7}"#.utf8)
        XCTAssertThrowsError(try LinkCodec.decode(number)) { XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: "c1")) }
    }

    func testEndDigestMustBe64LowercaseHex() {
        func failure(_ sha: String) -> LinkCodecError? {
            let text = #"{"v":1,"t":"attach.end","call_id":"c1","attachment_id":"a1","sha256":"\#(sha)"}"#
            do { _ = try LinkCodec.decode(Data(text.utf8)); return nil } catch { return error as? LinkCodecError }
        }
        let good = String(repeating: "ab", count: 32)
        XCTAssertNil(failure(good))
        for bad in [String(good.dropLast()), good + "0", good.uppercased(), String(repeating: "zz", count: 32), ""] {
            XCTAssertEqual(failure(bad), .badJSON(callId: "c1"), bad)
        }
        // A digest that is not 32 bytes cannot be encoded.
        XCTAssertThrowsError(try LinkCodec.encode(.attachEnd(callId: "c1", attachmentId: "a1", sha256: Data(count: 31)))) {
            XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil))
        }
    }

    func testAttachmentCallsNeedValidCallIds() {
        let long = String(repeating: "c", count: LinkCodec.maxCallIdBytes + 1)
        XCTAssertThrowsError(try LinkCodec.encode(.attachBegin(callId: long, kind: .file, name: "n", size: 1)))
        XCTAssertThrowsError(try LinkCodec.encode(.attachReady(callId: "", attachmentId: "a1")))
        let json = Data(#"{"v":1,"t":"attach.chunk.result","attachment_id":"a1","received":1}"#.utf8)
        XCTAssertThrowsError(try LinkCodec.decode(json)) { XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil)) }
        let noId = Data(#"{"v":1,"t":"attach.ready","call_id":"c1"}"#.utf8)
        XCTAssertThrowsError(try LinkCodec.decode(noId)) { XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: "c1")) }
    }

    func testAttachmentConstants() {
        XCTAssertEqual(ShellXLink.maxAttachmentBytes, 10_485_760)
        XCTAssertEqual(ShellXLink.maxAttachmentsPerMessage, 5)
        XCTAssertEqual(ShellXLink.maxPendingUploads, 5)
        XCTAssertEqual(ShellXLink.unsentUploadLifetime, .seconds(300))
        XCTAssertEqual(ShellXLink.maxAttachmentChunkBytes, 45_000)
        XCTAssertEqual(ShellXLink.attachmentsFeature, "attachments")
    }

    // MARK: - workspaces

    private static let workspaceA = LinkWorkspace(
        workspaceId: "w-1", title: "shellx", order: 0, directory: "~/Documents/myProjects/shellx", branch: "main",
        ports: [3000, 5173],
        terminals: [
            LinkTerminal(terminalId: "t-1", title: "claude", order: 0, selected: true, sessionId: "s-1"),
            LinkTerminal(terminalId: "t-2", title: "zsh", order: 1, selected: false),
        ])
    private static let workspaceB = LinkWorkspace(
        workspaceId: "w-2", title: "notes", order: 1,
        terminals: [LinkTerminal(terminalId: "t-3", title: "zsh", order: 0, selected: true)])

    private static func jsonObject(_ m: LinkMessage) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: try LinkCodec.encode(m)) as? [String: Any])
    }

    func testWorkspaceListRoundTrip() throws {
        let list = LinkMessage.workspaces(callId: "c1", revision: 7, workspaces: [Self.workspaceA, Self.workspaceB])
        XCTAssertEqual(try LinkCodec.decode(try LinkCodec.encode(list)), list)
        XCTAssertEqual(try LinkCodec.decode(try LinkCodec.encode(.workspacesGet(callId: "c0"))), .workspacesGet(callId: "c0"))
        // Optional fields are omitted, not null, on a record that has none.
        let object = try Self.jsonObject(list)
        XCTAssertEqual(object["t"] as? String, "workspace.list")
        let records = try XCTUnwrap(object["workspaces"] as? [[String: Any]])
        XCTAssertEqual(records[0]["workspace_id"] as? String, "w-1")
        XCTAssertEqual(records[0]["branch"] as? String, "main")
        XCTAssertEqual(records[0]["directory"] as? String, "~/Documents/myProjects/shellx")
        XCTAssertEqual(records[0]["ports"] as? [Int], [3000, 5173])
        let withSession = try XCTUnwrap((records[0]["terminals"] as? [[String: Any]])?[0])
        XCTAssertEqual(withSession["terminal_id"] as? String, "t-1")
        XCTAssertEqual(withSession["session_id"] as? String, "s-1")
        XCTAssertEqual(withSession["selected"] as? Bool, true)
        let bare = records[1]
        for key in ["ports", "branch", "directory"] {
            XCTAssertNil(bare[key], "\(key) must be omitted when nil")
        }
        XCTAssertEqual(bare["order"] as? Int, 1)
        let bareTerminal = try XCTUnwrap((bare["terminals"] as? [[String: Any]])?[0])
        XCTAssertNil(bareTerminal["session_id"], "session_id must be omitted when nil")
        XCTAssertEqual(bareTerminal["title"] as? String, "zsh")
    }

    func testWorkspaceChangedRoundTrip() throws {
        let changed = LinkMessage.workspacesChanged(revision: 8, upserted: [Self.workspaceB], removed: ["w-1", "w-9"])
        XCTAssertEqual(try LinkCodec.decode(try LinkCodec.encode(changed)), changed)
        let empty = LinkMessage.workspacesChanged(revision: 9, upserted: [], removed: [])
        XCTAssertEqual(try LinkCodec.decode(try LinkCodec.encode(empty)), empty)
        let object = try Self.jsonObject(changed)
        XCTAssertEqual(object["t"] as? String, "workspace.changed")
        XCTAssertEqual(object["revision"] as? Int, 8)
        XCTAssertEqual(object["removed"] as? [String], ["w-1", "w-9"])
        XCTAssertEqual((object["upserted"] as? [[String: Any]])?.count, 1)
        // A workspace without `terminals` is bad_json.
        XCTAssertThrowsError(try LinkCodec.decode(Data(
            #"{"v":1,"t":"workspace.changed","revision":1,"upserted":[{"workspace_id":"w","title":"t","order":0}],"removed":[]}"#
                .utf8))) { XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil)) }
    }

    func testWorkspaceControlRoundTrip() throws {
        let messages: [LinkMessage] = [
            .workspaceCreate(callId: "c1"),
            .workspaceCreateResult(callId: "c1", outcome: .ok, workspaceId: "w-new"),
            .workspaceCreateResult(callId: "c1", outcome: .refused, workspaceId: nil),
            .workspaceRename(callId: "c2", workspaceId: "w-1", title: "Tên mới"),
            .workspaceRenameResult(callId: "c2", outcome: .notFound),
            .workspaceClose(callId: "c3", workspaceId: "w-1"),
            .workspaceCloseResult(callId: "c3", outcome: .failed),
        ]
        for message in messages {
            XCTAssertEqual(try LinkCodec.decode(try LinkCodec.encode(message)), message, "\(message)")
        }
        let wireTypes: [(LinkMessage, String)] = [
            (messages[0], "workspace.create"), (messages[1], "workspace.create.result"),
            (messages[3], "workspace.rename"), (messages[4], "workspace.rename.result"),
            (messages[5], "workspace.close"), (messages[6], "workspace.close.result"),
        ]
        for (message, type) in wireTypes {
            XCTAssertEqual(try Self.jsonObject(message)["t"] as? String, type)
        }
        let ok = try Self.jsonObject(messages[1])
        XCTAssertEqual(ok["outcome"] as? String, "ok")
        XCTAssertEqual(ok["workspace_id"] as? String, "w-new")
        let refused = try Self.jsonObject(messages[2])
        XCTAssertEqual(refused["outcome"] as? String, "refused")
        XCTAssertNil(refused["workspace_id"], "workspace_id is present only when the outcome is ok")
        XCTAssertEqual(try Self.jsonObject(messages[4])["outcome"] as? String, "not_found")
        // Every control call needs a valid call_id.
        XCTAssertThrowsError(try LinkCodec.encode(.workspaceCreate(callId: ""))) {
            XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil))
        }
        XCTAssertThrowsError(try LinkCodec.decode(Data(#"{"v":1,"t":"workspace.close","workspace_id":"w"}"#.utf8))) {
            XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil))
        }
    }

    func testAgentCloseRoundTrip() throws {
        let messages: [LinkMessage] = [
            .agentClose(callId: "c1", sessionId: "sess-1"),
            .agentCloseResult(callId: "c1", outcome: .ok),
            .agentCloseResult(callId: "c2", outcome: .notFound),
            .agentCloseResult(callId: "c3", outcome: .other("busy")),
        ]
        for message in messages {
            XCTAssertEqual(try LinkCodec.decode(try LinkCodec.encode(message)), message, "\(message)")
        }
        let close = try Self.jsonObject(messages[0])
        XCTAssertEqual(close["t"] as? String, "agent.close")
        XCTAssertEqual(close["call_id"] as? String, "c1")
        XCTAssertEqual(close["session_id"] as? String, "sess-1")
        let ok = try Self.jsonObject(messages[1])
        XCTAssertEqual(ok["t"] as? String, "agent.close.result")
        XCTAssertEqual(ok["outcome"] as? String, "ok")
        XCTAssertEqual(try Self.jsonObject(messages[2])["outcome"] as? String, "not_found")
        XCTAssertEqual(try Self.jsonObject(messages[3])["outcome"] as? String, "busy")
        // Both messages need a valid call_id: encoding without one, and decoding a frame that lacks it, are errors.
        XCTAssertThrowsError(try LinkCodec.encode(.agentClose(callId: "", sessionId: "sess-1"))) {
            XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil))
        }
        XCTAssertThrowsError(try LinkCodec.encode(.agentCloseResult(callId: "", outcome: .ok))) {
            XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil))
        }
        XCTAssertThrowsError(try LinkCodec.decode(Data(#"{"v":1,"t":"agent.close","session_id":"sess-1"}"#.utf8))) {
            XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil))
        }
        XCTAssertThrowsError(try LinkCodec.decode(Data(#"{"v":1,"t":"agent.close.result","outcome":"ok"}"#.utf8))) {
            XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil))
        }
        // A close without a session_id is bad_json too, and keeps its call_id for the error answer.
        XCTAssertThrowsError(try LinkCodec.decode(Data(#"{"v":1,"t":"agent.close","call_id":"c9"}"#.utf8))) {
            XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: "c9"))
        }
    }

    func testTerminalCloseRoundTrip() throws {
        let messages: [LinkMessage] = [
            .terminalClose(callId: "c1", workspaceId: "ws-1", terminalId: "t-1"),
            .terminalCloseResult(callId: "c1", outcome: .ok),
            .terminalCloseResult(callId: "c2", outcome: .notFound),
            .terminalCloseResult(callId: "c3", outcome: .other("busy")),
        ]
        for message in messages {
            XCTAssertEqual(try LinkCodec.decode(try LinkCodec.encode(message)), message, "\(message)")
        }
        let close = try Self.jsonObject(messages[0])
        XCTAssertEqual(close["t"] as? String, "terminal.close")
        XCTAssertEqual(close["call_id"] as? String, "c1")
        XCTAssertEqual(close["workspace_id"] as? String, "ws-1")
        XCTAssertEqual(close["terminal_id"] as? String, "t-1")
        let ok = try Self.jsonObject(messages[1])
        XCTAssertEqual(ok["t"] as? String, "terminal.close.result")
        XCTAssertEqual(ok["outcome"] as? String, "ok")
        XCTAssertEqual(try Self.jsonObject(messages[2])["outcome"] as? String, "not_found")
        XCTAssertEqual(try Self.jsonObject(messages[3])["outcome"] as? String, "busy")
        // Both messages need a valid call_id: encoding without one, and decoding a frame that lacks it, are errors.
        XCTAssertThrowsError(try LinkCodec.encode(.terminalClose(callId: "", workspaceId: "ws-1", terminalId: "t-1"))) {
            XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil))
        }
        XCTAssertThrowsError(try LinkCodec.encode(.terminalCloseResult(callId: "", outcome: .ok))) {
            XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil))
        }
        XCTAssertThrowsError(try LinkCodec.decode(Data(
            #"{"v":1,"t":"terminal.close","workspace_id":"ws-1","terminal_id":"t-1"}"#.utf8))) {
            XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil))
        }
        XCTAssertThrowsError(try LinkCodec.decode(Data(#"{"v":1,"t":"terminal.close.result","outcome":"ok"}"#.utf8))) {
            XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil))
        }
        // A close missing either id is bad_json too, and keeps its call_id for the error answer.
        XCTAssertThrowsError(try LinkCodec.decode(Data(
            #"{"v":1,"t":"terminal.close","call_id":"c9","workspace_id":"ws-1"}"#.utf8))) {
            XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: "c9"))
        }
        XCTAssertThrowsError(try LinkCodec.decode(Data(
            #"{"v":1,"t":"terminal.close","call_id":"c9","terminal_id":"t-1"}"#.utf8))) {
            XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: "c9"))
        }
    }

    func testUnknownOutcomeKeepsWire() throws {
        let decoded = try LinkCodec.decode(Data(
            #"{"v":1,"t":"workspace.rename.result","call_id":"c1","outcome":"busy"}"#.utf8))
        XCTAssertEqual(decoded, .workspaceRenameResult(callId: "c1", outcome: .other("busy")))
        XCTAssertEqual(try Self.jsonObject(decoded)["outcome"] as? String, "busy")
        XCTAssertEqual(WorkspaceControlOutcome(wire: "not_found"), .notFound)
        XCTAssertEqual(WorkspaceControlOutcome.notFound.wire, "not_found")
        XCTAssertEqual(WorkspaceControlOutcome(wire: "refused"), .refused)
        XCTAssertEqual(WorkspaceControlOutcome(wire: "hologram").wire, "hologram")
    }

    /// The codec does not cap a rename title: the host checks `ShellXLink.maxWorkspaceTitleBytes` itself.
    func testRenameTitleCap() throws {
        let title = String(repeating: "a", count: ShellXLink.maxWorkspaceTitleBytes + 1)
        XCTAssertEqual(title.utf8.count, 513)
        let frame = Data(#"{"v":1,"t":"workspace.rename","call_id":"c1","workspace_id":"w-1","title":"\#(title)"}"#.utf8)
        XCTAssertEqual(try LinkCodec.decode(frame), .workspaceRename(callId: "c1", workspaceId: "w-1", title: title))
    }

    func testWorkspaceConstants() {
        XCTAssertEqual(ShellXLink.workspacesFeature, "workspaces")
        XCTAssertEqual(ShellXLink.workspaceControlFeature, "workspace_control")
        XCTAssertEqual(ShellXLink.maxWorkspaceTitleBytes, 512)
    }

    func testAgentCloseFeature() {
        XCTAssertEqual(ShellXLink.agentCloseFeature, "agent_close")
    }

    func testTerminalCloseFeature() {
        XCTAssertEqual(ShellXLink.terminalCloseFeature, "terminal_close")
    }

    func testWorkspaceShrinkOrder() throws {
        let full = Self.workspaceA
        let one = try XCTUnwrap(full.shrunk(step: 1))
        XCTAssertNil(one.ports)
        XCTAssertEqual(one.directory, full.directory)
        XCTAssertEqual(one.branch, full.branch)
        let two = try XCTUnwrap(full.shrunk(step: 2))
        XCTAssertNil(two.ports)
        XCTAssertNil(two.directory)
        XCTAssertEqual(two.branch, "main")
        let three = try XCTUnwrap(full.shrunk(step: 3))
        XCTAssertNil(three.branch)
        XCTAssertEqual(three.terminals.map(\.title), ["claude", "zsh"])
        let four = try XCTUnwrap(full.shrunk(step: 4))
        XCTAssertNil(four.ports)
        XCTAssertNil(four.directory)
        XCTAssertNil(four.branch)
        XCTAssertEqual(four.title, "shellx", "the workspace title is never dropped")
        XCTAssertEqual(four.terminals.map(\.title), ["", ""])
        XCTAssertEqual(four.terminals.map(\.terminalId), ["t-1", "t-2"])
        XCTAssertEqual(four.terminals.map(\.sessionId), ["s-1", nil], "only titles are dropped from a terminal")
        XCTAssertEqual(four.workspaceId, "w-1")
        XCTAssertNil(full.shrunk(step: 0))
        XCTAssertNil(full.shrunk(step: 5))
        XCTAssertNil(full.shrunk(step: -1))
        // A shrunk workspace is smaller on the wire than the full one.
        let fullSize = try LinkCodec.encode(.workspaces(callId: "c", revision: 1, workspaces: [full])).count
        let smallSize = try LinkCodec.encode(.workspaces(callId: "c", revision: 1, workspaces: [four])).count
        XCTAssertLessThan(smallSize, fullSize)
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

    static func sessions(_ o: Any?) throws -> [AgentSession] {
        try XCTUnwrap(o as? [[String: Any]]).map { d in
            AgentSession(
                sessionId: try XCTUnwrap(d["session_id"] as? String), agent: try XCTUnwrap(d["agent"] as? String),
                workspaceId: try XCTUnwrap(d["workspace_id"] as? String),
                workspaceTitle: try XCTUnwrap(d["workspace_title"] as? String), title: d["title"] as? String,
                state: AgentState(wire: try XCTUnwrap(d["state"] as? String)),
                stateSinceMs: (d["state_since_ms"] as? NSNumber)?.int64Value,
                lastActivityMs: (d["last_activity_ms"] as? NSNumber)?.int64Value)
        }
    }

    static func workspaces(_ o: Any?) throws -> [LinkWorkspace] {
        try XCTUnwrap(o as? [[String: Any]]).map { d in
            LinkWorkspace(
                workspaceId: try XCTUnwrap(d["workspace_id"] as? String), title: try XCTUnwrap(d["title"] as? String),
                order: try XCTUnwrap((d["order"] as? NSNumber)?.intValue), directory: d["directory"] as? String,
                branch: d["branch"] as? String, ports: (d["ports"] as? [NSNumber])?.map(\.intValue),
                terminals: try XCTUnwrap(d["terminals"] as? [[String: Any]]).map { t in
                    LinkTerminal(
                        terminalId: try XCTUnwrap(t["terminal_id"] as? String), title: try XCTUnwrap(t["title"] as? String),
                        order: try XCTUnwrap((t["order"] as? NSNumber)?.intValue),
                        selected: try XCTUnwrap(t["selected"] as? Bool), sessionId: t["session_id"] as? String)
                })
        }
    }

    static func entries(_ o: Any?) throws -> [ChatEntry] {
        try XCTUnwrap(o as? [[String: Any]]).map { d in
            ChatEntry(
                id: try XCTUnwrap(d["id"] as? String), rev: try XCTUnwrap((d["rev"] as? NSNumber)?.intValue),
                seq: try XCTUnwrap((d["seq"] as? NSNumber)?.intValue),
                role: ChatEntryRole(wire: try XCTUnwrap(d["role"] as? String)),
                kind: ChatEntryKind(wire: try XCTUnwrap(d["kind"] as? String)),
                text: try XCTUnwrap(d["text"] as? String), truncated: d["truncated"] as? Bool,
                toolName: d["tool_name"] as? String, tsMs: try XCTUnwrap((d["ts_ms"] as? NSNumber)?.int64Value))
        }
    }

    static func hexData(_ hex: String) -> Data? {
        guard hex.utf8.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    static func message(from m: [String: Any], _ name: String) throws -> LinkMessage {
        func s(_ k: String) throws -> String { try XCTUnwrap(m[k] as? String, "\(name).\(k)") }
        func n(_ k: String) throws -> NSNumber { try XCTUnwrap(m[k] as? NSNumber, "\(name).\(k)") }
        switch try s("case") {
        case "hello": return .hello(clientVersion: try s("client_version"), deviceName: try s("device_name"))
        case "welcome":
            return .welcome(protocolVersion: try n("protocol_version").intValue, hostVersion: try s("host_version"),
                            machineName: try s("machine_name"), features: m["features"] as? [String] ?? [])
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
        case "unknown": return .unknown(type: try s("type"), callId: m["call_id"] as? String)
        case "sessions_get": return .sessionsGet(callId: try s("call_id"))
        case "sessions":
            return .sessions(callId: try s("call_id"), revision: try n("revision").intValue, sessions: try sessions(m["sessions"]))
        case "sessions_changed":
            return .sessionsChanged(
                revision: try n("revision").intValue, upserted: try sessions(m["upserted"]),
                removed: try XCTUnwrap(m["removed"] as? [String]))
        case "chat_history_get":
            return .chatHistoryGet(
                callId: try s("call_id"), sessionId: try s("session_id"),
                beforeSeq: (m["before_seq"] as? NSNumber)?.intValue, limit: try n("limit").intValue)
        case "chat_history":
            return .chatHistory(
                callId: try s("call_id"), sessionId: try s("session_id"), entries: try entries(m["entries"]),
                hasMore: try XCTUnwrap(m["has_more"] as? Bool))
        case "chat_entries": return .chatEntries(sessionId: try s("session_id"), entries: try entries(m["entries"]))
        case "chat_reset": return .chatReset(sessionId: try s("session_id"))
        case "chat_send":
            return .chatSend(
                callId: try s("call_id"), sessionId: try s("session_id"), text: try s("text"),
                attachments: m["attachments"] as? [String] ?? [])
        case "chat_send_result": return .chatSendResult(callId: try s("call_id"), outcome: ChatSendOutcome(wire: try s("outcome")))
        case "chat_interrupt":
            return .chatInterrupt(
                callId: try s("call_id"), sessionId: try s("session_id"), hard: try XCTUnwrap(m["hard"] as? Bool))
        case "chat_interrupt_result":
            return .chatInterruptResult(callId: try s("call_id"), outcome: ChatInterruptOutcome(wire: try s("outcome")))
        case "attach_begin":
            return .attachBegin(
                callId: try s("call_id"), kind: AttachmentKind(wire: try s("kind")), name: try s("name"),
                size: try n("size").intValue)
        case "attach_ready": return .attachReady(callId: try s("call_id"), attachmentId: try s("attachment_id"))
        case "attach_chunk":
            return .attachChunk(
                callId: try s("call_id"), attachmentId: try s("attachment_id"), offset: try n("offset").intValue,
                data: try XCTUnwrap(Data(base64Encoded: try s("data")), "\(name).data"))
        case "attach_chunk_result":
            return .attachChunkResult(
                callId: try s("call_id"), attachmentId: try s("attachment_id"), received: try n("received").intValue)
        case "attach_end":
            return .attachEnd(
                callId: try s("call_id"), attachmentId: try s("attachment_id"),
                sha256: try XCTUnwrap(hexData(try s("sha256")), "\(name).sha256"))
        case "attach_end_result":
            return .attachEndResult(callId: try s("call_id"), attachmentId: try s("attachment_id"))
        case "workspaces_get": return .workspacesGet(callId: try s("call_id"))
        case "workspaces":
            return .workspaces(
                callId: try s("call_id"), revision: try n("revision").intValue, workspaces: try workspaces(m["workspaces"]))
        case "workspaces_changed":
            return .workspacesChanged(
                revision: try n("revision").intValue, upserted: try workspaces(m["upserted"]),
                removed: try XCTUnwrap(m["removed"] as? [String]))
        case "workspace_create": return .workspaceCreate(callId: try s("call_id"))
        case "workspace_create_result":
            return .workspaceCreateResult(
                callId: try s("call_id"), outcome: WorkspaceControlOutcome(wire: try s("outcome")),
                workspaceId: m["workspace_id"] as? String)
        case "workspace_rename":
            return .workspaceRename(callId: try s("call_id"), workspaceId: try s("workspace_id"), title: try s("title"))
        case "workspace_rename_result":
            return .workspaceRenameResult(callId: try s("call_id"), outcome: WorkspaceControlOutcome(wire: try s("outcome")))
        case "workspace_close": return .workspaceClose(callId: try s("call_id"), workspaceId: try s("workspace_id"))
        case "workspace_close_result":
            return .workspaceCloseResult(callId: try s("call_id"), outcome: WorkspaceControlOutcome(wire: try s("outcome")))
        case "agent_close": return .agentClose(callId: try s("call_id"), sessionId: try s("session_id"))
        case "agent_close_result":
            return .agentCloseResult(callId: try s("call_id"), outcome: WorkspaceControlOutcome(wire: try s("outcome")))
        case "terminal_close":
            return .terminalClose(
                callId: try s("call_id"), workspaceId: try s("workspace_id"), terminalId: try s("terminal_id"))
        case "terminal_close_result":
            return .terminalCloseResult(callId: try s("call_id"), outcome: WorkspaceControlOutcome(wire: try s("outcome")))
        default:
            XCTFail("unknown vector case in \(name)")
            throw LinkCodecError.badJSON(callId: nil)
        }
    }
}
