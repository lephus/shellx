import CryptoKit
import Foundation
import XCTest
@testable import ShellXRemoteCore

final class ShareWireTests: XCTestCase {
    private static let secretB64 = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"
    private static let shareID = "k7f29qd1"
    private static let circuit = "circuit-b3-vector"

    private static var vectorsURL: URL {
        // .../Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests/<file> -> repo root
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

    private static let hostMessage = ShareMessage.out(pane: "p1", data: Data("hi".utf8))
    private static let viewerMessage = ShareMessage.input(pane: "p1", data: Data("ls\r".utf8))
    private static let hostNonce = Data((0..<12).map { UInt8(0xA0 + $0) })
    private static let viewerNonce = Data((0..<12).map { UInt8(0xB0 + $0) })

    private func vectors() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.vectorsURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Run once with SHARE_VECTORS_WRITE=1 to (re)generate the committed file.
    func testWriteVectorsWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["SHARE_VECTORS_WRITE"] == "1" else {
            throw XCTSkip("set SHARE_VECTORS_WRITE=1 to regenerate share-vectors.json")
        }
        let keys = try XCTUnwrap(ShareSecret(base64url: Self.secretB64)).keys(shareID: Self.shareID)
        func frame(_ key: SymmetricKey, _ keyName: String, _ nonce: Data, _ m: ShareMessage) throws -> [String: Any] {
            var c = ShareCipher(sendKey: key, receiveKey: key, circuit: Self.circuit)
            c.fixedNonce = try AES.GCM.Nonce(data: nonce)
            let f = try c.seal(m)
            return ["circuit": Self.circuit, "key": keyName, "nonce_hex": Self.hex(nonce),
                    "plaintext": String(decoding: m.wireJSON(seq: 1), as: UTF8.self), "frame_hex": Self.hex(f)]
        }
        let obj: [String: Any] = [
            "secret": Self.secretB64, "share_id": Self.shareID,
            "keys": ["host_to_viewer_hex": Self.hex(keys.hostToViewer),
                     "viewer_to_host_hex": Self.hex(keys.viewerToHost), "access": keys.access],
            "frames": [try frame(keys.hostToViewer, "host_to_viewer", Self.hostNonce, Self.hostMessage),
                       try frame(keys.viewerToHost, "viewer_to_host", Self.viewerNonce, Self.viewerMessage)],
        ]
        let out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
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
        let secret = try XCTUnwrap(ShareSecret(base64url: v["secret"] as! String))
        let keys = secret.keys(shareID: v["share_id"] as! String)
        let frames = v["frames"] as! [[String: String]]
        XCTAssertGreaterThanOrEqual(frames.count, 2)
        for f in frames {
            let key = f["key"] == "host_to_viewer" ? keys.hostToViewer : keys.viewerToHost
            let msg = f["key"] == "host_to_viewer" ? Self.hostMessage : Self.viewerMessage
            var c = ShareCipher(sendKey: key, receiveKey: key, circuit: f["circuit"]!)
            c.fixedNonce = try AES.GCM.Nonce(data: Self.unhex(f["nonce_hex"]!))
            XCTAssertEqual(Self.hex(try c.seal(msg)), f["frame_hex"])
            XCTAssertEqual(String(decoding: msg.wireJSON(seq: 1), as: UTF8.self), f["plaintext"])
            var r = ShareCipher(sendKey: key, receiveKey: key, circuit: f["circuit"]!)
            XCTAssertEqual(r.open(Self.unhex(f["frame_hex"]!)), msg)
        }
    }

    private func pair() -> (ShareCipher, ShareCipher) {
        let k = SymmetricKey(size: .bits256), k2 = SymmetricKey(size: .bits256)
        return (ShareCipher(sendKey: k, receiveKey: k2, circuit: "c1"),
                ShareCipher(sendKey: k2, receiveKey: k, circuit: "c1"))
    }

    func testOpenRejectsReplayedSeq() throws {
        var (host, viewer) = pair()
        let f = try host.seal(.out(pane: "p", data: Data("a".utf8)))
        XCTAssertNotNil(viewer.open(f))
        XCTAssertNil(viewer.open(f))
        XCTAssertEqual(viewer.dropped, 1)
        let f2 = try host.seal(.out(pane: "p", data: Data("b".utf8)))
        XCTAssertNotNil(viewer.open(f2))
    }

    func testOpenRejectsOtherCircuit() throws {
        let k = SymmetricKey(size: .bits256)
        var a = ShareCipher(sendKey: k, receiveKey: k, circuit: "one")
        var b = ShareCipher(sendKey: k, receiveKey: k, circuit: "two")
        XCTAssertNil(b.open(try a.seal(.select(pane: "p"))))
        XCTAssertEqual(b.dropped, 1)
        var short = pair().1
        XCTAssertNil(short.open(Data([1, 2, 3])))
    }

    func testMessageJSONKeys() throws {
        let m = ShareMessage.input(pane: "p", data: Data("hi".utf8))
        XCTAssertEqual(String(decoding: m.wireJSON(seq: 1), as: UTF8.self),
                       #"{"t":"in","seq":1,"pane":"p","data":"aGk="}"#)
        let w = ShareMessage.welcome(perm: .view, expiresAt: nil,
            panes: [SharePane(id: "p", title: "zsh", kind: .terminal, cols: 80, rows: 24)], active: "p")
        XCTAssertEqual(String(decoding: w.wireJSON(seq: 2), as: UTF8.self),
            #"{"t":"welcome","seq":2,"perm":"view","expires_at_unix":null,"panes":[{"id":"p","title":"zsh","kind":"terminal","cols":80,"rows":24}],"active":"p"}"#)
        XCTAssertEqual(String(decoding: ShareMessage.bye(.hostQuit).wireJSON(seq: 3), as: UTF8.self),
                       #"{"t":"bye","seq":3,"reason":"host_quit"}"#)
    }

    func testMessageRoundTripAllKinds() throws {
        let panes = [SharePane(id: "p", title: "t", kind: .agent, cols: 1, rows: 2)]
        let all: [ShareMessage] = [
            .welcome(perm: .type, expiresAt: 99, panes: panes, active: "p"), .panes(panes, active: "p"),
            .replay(pane: "p", cols: 3, rows: 4, data: Data([0, 255])), .out(pane: "p", data: Data()),
            .size(pane: "p", cols: 5, rows: 6), .bye(.revoked), .bye(.expired), .hello(label: "Safari"),
            .select(pane: "p"), .input(pane: "p", data: Data("x".utf8)),
        ]
        for m in all {
            XCTAssertEqual(try JSONDecoder().decode(ShareMessage.self, from: m.wireJSON(seq: 7)), m)
        }
    }

    func testSecretRoundTripIs43Chars() throws {
        let s = ShareSecret.random()
        XCTAssertEqual(s.base64url.count, 43)
        XCTAssertFalse(s.base64url.contains("="))
        XCTAssertEqual(ShareSecret(base64url: s.base64url)?.base64url, s.base64url)
        XCTAssertNil(ShareSecret(base64url: "short"))
    }
}
