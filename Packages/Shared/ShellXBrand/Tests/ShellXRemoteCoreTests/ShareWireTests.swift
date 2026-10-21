import CryptoKit
import Foundation
import XCTest
@testable import ShellXRemoteCore

final class ShareWireTests: XCTestCase {
    private static let secretB64 = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"
    private static let shareID = "k7f29qd1"
    private static let circuit = "circuit-b3-vector"
    private static let viewerNonce = Data((0..<16).map { UInt8(0x10 + $0) })
    private static let hostNonce = Data((0..<16).map { UInt8(0x30 + $0) })

    private static var vectorsURL: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("web/tests/fixtures/share-vectors.json")
    }

    private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
    private static func hex(_ key: SymmetricKey) -> String { hex(key.withUnsafeBytes { Data($0) }) }
    private static func unhex(_ s: String) -> Data {
        var d = Data(); var i = s.startIndex
        while i < s.endIndex { let j = s.index(i, offsetBy: 2); d.append(UInt8(s[i..<j], radix: 16)!); i = j }
        return d
    }

    private static let hello = ShareMessage.hello(nonce: viewerNonce, label: "Safari · iPhone")
    private static let welcome = ShareMessage.welcome(nonce: hostNonce, perm: .type, expiresAt: 1_800_000_000,
        panes: [SharePane(id: "p1", title: "zsh", kind: .terminal, cols: 80, rows: 24)], active: "p1")
    private static let out = ShareMessage.out(pane: "p1", data: Data("hi".utf8))
    private static let input = ShareMessage.input(pane: "p1", data: Data("ls\r".utf8))

    /// (key name, message, fixed nonce first byte, stage-aad suffix)
    private static var plan: [(String, ShareMessage, UInt8)] {
        [("viewer_to_host", hello, 0xB0), ("host_to_viewer", welcome, 0xA0),
         ("host_to_viewer", out, 0xA1), ("viewer_to_host", input, 0xB1)]
    }

    private func vectors() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.vectorsURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private struct Pair {
        var host: ShareCipher
        var viewer: ShareCipher
    }

    private func randomPair(circuit: String = "c1") -> Pair {
        let a = SymmetricKey(size: .bits256), b = SymmetricKey(size: .bits256)
        return Pair(host: ShareCipher(sendKey: a, receiveKey: b, circuit: circuit),
                    viewer: ShareCipher(sendKey: b, receiveKey: a, circuit: circuit))
    }

    /// Runs the full A1 handshake on a pair and returns it in stage 3.
    private func staged() throws -> Pair {
        var p = randomPair()
        let h = try p.viewer.seal(Self.hello)
        XCTAssertEqual(p.host.open(h), Self.hello)
        p.host.setViewerNonce(Self.viewerNonce); p.viewer.setViewerNonce(Self.viewerNonce)
        let w = try p.host.seal(Self.welcome)
        XCTAssertEqual(p.viewer.open(w), Self.welcome)
        p.host.setHostNonce(Self.hostNonce); p.viewer.setHostNonce(Self.hostNonce)
        return p
    }

    /// Run once with SHARE_VECTORS_WRITE=1 to (re)generate the committed file.
    func testWriteVectorsWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["SHARE_VECTORS_WRITE"] == "1" else {
            throw XCTSkip("set SHARE_VECTORS_WRITE=1 to regenerate share-vectors.json")
        }
        let keys = try XCTUnwrap(ShareSecret(base64url: Self.secretB64)).keys(shareID: Self.shareID)
        var host = ShareCipher(sendKey: keys.hostToViewer, receiveKey: keys.viewerToHost, circuit: Self.circuit)
        var viewer = ShareCipher(sendKey: keys.viewerToHost, receiveKey: keys.hostToViewer, circuit: Self.circuit)
        var frames: [[String: Any]] = []
        for (i, (name, msg, first)) in Self.plan.enumerated() {
            let nonce = Data((0..<12).map { first &+ UInt8($0) })
            let aad: String
            let f: Data
            if name == "viewer_to_host" {
                viewer.fixedNonce = try AES.GCM.Nonce(data: nonce); aad = String(decoding: viewer.aad, as: UTF8.self)
                f = try viewer.seal(msg)
            } else {
                host.fixedNonce = try AES.GCM.Nonce(data: nonce); aad = String(decoding: host.aad, as: UTF8.self)
                f = try host.seal(msg)
            }
            let seq = (i + 2) / 2   // each direction counts 1, 2
            frames.append(["circuit": Self.circuit, "key": name, "nonce_hex": Self.hex(nonce), "aad": aad,
                           "plaintext": String(decoding: msg.wireJSON(seq: seq), as: UTF8.self), "frame_hex": Self.hex(f)])
            if i == 0 { host.setViewerNonce(Self.viewerNonce); viewer.setViewerNonce(Self.viewerNonce) }
            if i == 1 { host.setHostNonce(Self.hostNonce); viewer.setHostNonce(Self.hostNonce) }
        }
        let obj: [String: Any] = [
            "secret": Self.secretB64, "share_id": Self.shareID,
            "viewer_nonce_b64": Self.viewerNonce.base64EncodedString(),
            "host_nonce_b64": Self.hostNonce.base64EncodedString(),
            "keys": ["host_to_viewer_hex": Self.hex(keys.hostToViewer),
                     "viewer_to_host_hex": Self.hex(keys.viewerToHost), "access": keys.access],
            "frames": frames,
        ]
        var out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        out.append(0x0A)
        try out.write(to: Self.vectorsURL)
    }

    func testKeysMatchVectors() throws {
        let v = try vectors()
        let secret = try XCTUnwrap(ShareSecret(base64url: v["secret"] as! String))
        let expected = v["keys"] as! [String: String]
        for id in [v["share_id"] as! String, "k7f2-9qd1"] {
            let keys = secret.keys(shareID: id)
            XCTAssertEqual(Self.hex(keys.hostToViewer), expected["host_to_viewer_hex"])
            XCTAssertEqual(Self.hex(keys.viewerToHost), expected["viewer_to_host_hex"])
            XCTAssertEqual(keys.access, expected["access"])
        }
    }

    func testSealWithFixedNonceMatchesVectorFrame() throws {
        let v = try vectors()
        XCTAssertEqual(v["viewer_nonce_b64"] as? String, Self.viewerNonce.base64EncodedString())
        XCTAssertEqual(v["host_nonce_b64"] as? String, Self.hostNonce.base64EncodedString())
        let keys = try XCTUnwrap(ShareSecret(base64url: v["secret"] as! String)).keys(shareID: v["share_id"] as! String)
        var host = ShareCipher(sendKey: keys.hostToViewer, receiveKey: keys.viewerToHost, circuit: Self.circuit)
        var viewer = ShareCipher(sendKey: keys.viewerToHost, receiveKey: keys.hostToViewer, circuit: Self.circuit)
        let frames = v["frames"] as! [[String: String]]
        XCTAssertEqual(frames.count, 4)
        for (i, f) in frames.enumerated() {
            let (name, msg, _) = Self.plan[i]
            XCTAssertEqual(f["key"], name)
            let fromViewer = name == "viewer_to_host"
            if fromViewer { viewer.fixedNonce = try AES.GCM.Nonce(data: Self.unhex(f["nonce_hex"]!)) }
            else { host.fixedNonce = try AES.GCM.Nonce(data: Self.unhex(f["nonce_hex"]!)) }
            XCTAssertEqual(String(decoding: (fromViewer ? viewer : host).aad, as: UTF8.self), f["aad"])
            let sealed = try (fromViewer ? viewer.seal(msg) : host.seal(msg))
            XCTAssertEqual(Self.hex(sealed), f["frame_hex"])
            XCTAssertEqual(String(decoding: msg.wireJSON(seq: (i + 2) / 2), as: UTF8.self), f["plaintext"])
            // the opposite side opens the committed frame bytes
            let opened = fromViewer ? host.open(Self.unhex(f["frame_hex"]!)) : viewer.open(Self.unhex(f["frame_hex"]!))
            XCTAssertEqual(opened, msg)
            if i == 0 { host.setViewerNonce(Self.viewerNonce); viewer.setViewerNonce(Self.viewerNonce) }
            if i == 1 { host.setHostNonce(Self.hostNonce); viewer.setHostNonce(Self.hostNonce) }
        }
    }

    func testOpenRejectsReplayedSeq() throws {
        var p = randomPair()
        let f = try p.host.seal(.out(pane: "p", data: Data("a".utf8)))
        XCTAssertNotNil(p.viewer.open(f))
        XCTAssertNil(p.viewer.open(f))
        XCTAssertEqual(p.viewer.dropped, 1)
        XCTAssertNotNil(p.viewer.open(try p.host.seal(.out(pane: "p", data: Data("b".utf8)))))
    }

    func testLowerSeqAfterHigherIsDropped() throws {
        var p = randomPair()
        let f1 = try p.host.seal(.select(pane: "a")), f2 = try p.host.seal(.select(pane: "b"))
        XCTAssertNotNil(p.viewer.open(f2))
        XCTAssertNil(p.viewer.open(f1))
        XCTAssertEqual(p.viewer.dropped, 1)
    }

    func testTamperedFrameDoesNotAdvanceSeq() throws {
        var p = randomPair()
        let f = try p.host.seal(.select(pane: "a"))
        var bad = f; bad[bad.count - 1] ^= 1
        XCTAssertNil(p.viewer.open(bad))
        XCTAssertEqual(p.viewer.dropped, 1)
        XCTAssertEqual(p.viewer.open(f), .select(pane: "a"))   // genuine seq 1 still accepted
    }

    private func rawFrame(_ json: String, key: SymmetricKey, circuit: String = "c1") throws -> Data {
        let n = AES.GCM.Nonce()
        let box = try AES.GCM.seal(Data(json.utf8), using: key, nonce: n, authenticating: Data("shellx-share/1|\(circuit)".utf8))
        return Data(n) + box.ciphertext + box.tag
    }

    func testUndecodableAuthenticPlaintextIsDroppedAndDoesNotAdvanceSeq() throws {
        let a = SymmetricKey(size: .bits256)
        var viewer = ShareCipher(sendKey: a, receiveKey: a, circuit: "c1")
        let bads = [#"{"t":"zzz","seq":5}"#, #"{"t":"select","seq":5,"pane":7}"#, #"{"t":"out","seq":5,"pane":"p","data":"!!"}"#,
                    #"{"t":"select","seq":true,"pane":"p"}"#, #"{"t":"select","seq":2.0,"pane":"p"}"#,
                    #"{"t":"select","seq":"2","pane":"p"}"#, #"{"t":"select","pane":"p"}"#, "not json",
                    #"{"t":"hello","seq":5,"nonce":"AAAA","label":"x"}"#]
        for (i, j) in bads.enumerated() {
            XCTAssertNil(viewer.open(try rawFrame(j, key: a)), j)
            XCTAssertEqual(viewer.dropped, i + 1, j)
        }
        XCTAssertNotNil(viewer.open(try rawFrame(#"{"t":"select","seq":1,"pane":"p"}"#, key: a)))
    }

    func testOpenRejectsOtherCircuitAndShortFrame() throws {
        let k = SymmetricKey(size: .bits256)
        var a = ShareCipher(sendKey: k, receiveKey: k, circuit: "one")
        var b = ShareCipher(sendKey: k, receiveKey: k, circuit: "two")
        XCTAssertNil(b.open(try a.seal(.select(pane: "p"))))
        XCTAssertEqual(b.dropped, 1)
        XCTAssertNil(b.open(Data([1, 2, 3])))
        XCTAssertEqual(b.dropped, 2)
    }

    func testOversizeFrameDroppedBeforeDecrypt() throws {
        var p = randomPair()
        XCTAssertNil(p.viewer.open(Data(count: ShareCipher.maxFrameBytes + 1)))
        XCTAssertEqual(p.viewer.dropped, 1)
        XCTAssertThrowsError(try p.host.seal(.out(pane: "p", data: Data(count: 70_000))))
        // exactly-at-limit frames are not rejected by the size gate (they fail auth instead)
        XCTAssertNil(p.viewer.open(Data(count: ShareCipher.maxFrameBytes)))
        XCTAssertEqual(p.viewer.dropped, 2)
    }

    /// Each AAD-stage mismatch (sender stage vs receiver stage) is dropped and counted.
    func testStageMismatchMatrix() throws {
        // sender in stage s, receiver in stage r; only s == r opens.
        for s in 1...3 { for r in 1...3 {
            var p = randomPair()
            func advance(_ c: inout ShareCipher, to n: Int) {
                if n >= 2 { c.setViewerNonce(Self.viewerNonce) }
                if n >= 3 { c.setHostNonce(Self.hostNonce) }
            }
            advance(&p.host, to: s); advance(&p.viewer, to: r)
            let f = try p.host.seal(.select(pane: "p"))
            if s == r { XCTAssertNotNil(p.viewer.open(f), "s=\(s) r=\(r)") }
            else { XCTAssertNil(p.viewer.open(f), "s=\(s) r=\(r)"); XCTAssertEqual(p.viewer.dropped, 1) }
        } }
        // different nonce values within the same stage also fail
        var p = randomPair()
        p.host.setViewerNonce(Self.viewerNonce); p.viewer.setViewerNonce(Data(count: 16))
        XCTAssertNil(p.viewer.open(try p.host.seal(.select(pane: "p"))))
        // host nonce is ignored before the viewer nonce is set
        var q = randomPair()
        q.host.setHostNonce(Self.hostNonce)
        XCTAssertNotNil(q.viewer.open(try q.host.seal(.select(pane: "p"))))
    }

    func testFullStagedHandshakeAndLaterFrames() throws {
        var p = try staged()
        XCTAssertEqual(p.viewer.open(try p.host.seal(Self.out)), Self.out)
        XCTAssertEqual(p.host.open(try p.viewer.seal(Self.input)), Self.input)
    }

    func testMessageJSONKeys() throws {
        let m = ShareMessage.input(pane: "p", data: Data("hi".utf8))
        XCTAssertEqual(String(decoding: m.wireJSON(seq: 1), as: UTF8.self),
                       #"{"t":"in","seq":1,"pane":"p","data":"aGk="}"#)
        let n = Data(repeating: 0, count: 16)   // AAAAAAAAAAAAAAAAAAAAAA==
        let w = ShareMessage.welcome(nonce: n, perm: .view, expiresAt: nil,
            panes: [SharePane(id: "p", title: "zsh", kind: .terminal, cols: 80, rows: 24)], active: "p")
        XCTAssertEqual(String(decoding: w.wireJSON(seq: 2), as: UTF8.self),
            #"{"t":"welcome","seq":2,"nonce":"AAAAAAAAAAAAAAAAAAAAAA==","perm":"view","expires_at_unix":null,"panes":[{"id":"p","title":"zsh","kind":"terminal","cols":80,"rows":24}],"active":"p"}"#)
        XCTAssertEqual(String(decoding: ShareMessage.hello(nonce: n, label: "L").wireJSON(seq: 1), as: UTF8.self),
                       #"{"t":"hello","seq":1,"nonce":"AAAAAAAAAAAAAAAAAAAAAA==","label":"L"}"#)
        XCTAssertEqual(String(decoding: ShareMessage.bye(.hostQuit).wireJSON(seq: 3), as: UTF8.self),
                       #"{"t":"bye","seq":3,"reason":"host_quit"}"#)
    }

    func testMessageRoundTripAllKinds() throws {
        let panes = [SharePane(id: "p", title: "t", kind: .agent, cols: 1, rows: 2)]
        let n = Data((0..<16).map { UInt8($0) })
        let all: [ShareMessage] = [
            .welcome(nonce: n, perm: .type, expiresAt: 99, panes: panes, active: "p"), .panes(panes, active: "p"),
            .replay(pane: "p", cols: 3, rows: 4, data: Data([0, 255])), .out(pane: "p", data: Data()),
            .size(pane: "p", cols: 5, rows: 6), .bye(.revoked), .bye(.expired), .hello(nonce: n, label: "Safari"),
            .select(pane: "p"), .input(pane: "p", data: Data("x".utf8)),
        ]
        for m in all {
            XCTAssertEqual(try JSONDecoder().decode(ShareEnvelope.self, from: m.wireJSON(seq: 7)).message, m)
        }
    }

    func testSecretRoundTripIs43Chars() throws {
        let s = ShareSecret.random()
        XCTAssertEqual(s.base64url.count, 43)
        XCTAssertEqual(ShareSecret(base64url: s.base64url)?.base64url, s.base64url)
    }

    func testSecretParsingIsStrict() {
        let ok = Self.secretB64
        XCTAssertNotNil(ShareSecret(base64url: ok))
        XCTAssertNil(ShareSecret(base64url: "short"))
        XCTAssertNil(ShareSecret(base64url: ok + "="))                       // padding
        XCTAssertNil(ShareSecret(base64url: String(ok.dropLast()) + "+"))    // std alphabet
        XCTAssertNil(ShareSecret(base64url: String(ok.dropLast()) + "/"))
        XCTAssertNil(ShareSecret(base64url: ok + "A"))                       // 44 chars
        // non-canonical trailing bits: last char of a 43-char string must have its low 4 bits zero
        XCTAssertEqual(ok.last, "8")
        XCTAssertNil(ShareSecret(base64url: String(ok.dropLast()) + "9"))
    }
}
