import Darwin
import Foundation
import Testing
@testable import ShellXRemoteCore

// Task 11: the bridge server against a fake host over a real Unix socket. The tests are
// `@MainActor` (the host is), so every blocking socket read runs off the main thread.

@MainActor
final class FakeBridgeHost: ShellXBridgeHost {
    let surfaceID = UUID()
    let workspaceID = UUID()
    var mode = "attach"
    var refuseBind = false
    var gridValue: (cols: UInt16, rows: UInt16)? = (94, 37)
    var snapshotData: Data? = Data("\u{1b}[H\u{1b}[2Jsnapshot".utf8)
    /// Output the PTY "produces" while the snapshot is taken; must reach the daemon after it.
    var teeDuringSnapshot: Data?
    private(set) var hellos: [BridgeHello] = []
    private(set) var receivedInput = Data()
    private(set) var resizes: [[UInt16]] = []
    private(set) var unbound: [BridgeBinding] = []
    /// The host never closes a Mac surface on behalf of the daemon (D7); stays empty.
    private(set) var closedSurfaces: [UUID] = []

    func bind(hello: BridgeHello) -> BridgeBinding? {
        hellos.append(hello)
        if refuseBind { return nil }
        return BridgeBinding(connectionID: hello.connectionID, surfaceID: surfaceID, workspaceID: workspaceID, mode: mode)
    }

    func input(_ bytes: Data, binding: BridgeBinding) { receivedInput.append(bytes) }

    func remoteResize(cols: UInt16, rows: UInt16, binding: BridgeBinding) { resizes.append([cols, rows]) }

    func grid(binding: BridgeBinding) -> (cols: UInt16, rows: UInt16)? { gridValue }

    func snapshot(binding: BridgeBinding) -> Data? {
        if let teeDuringSnapshot {
            teeDuringSnapshot.withUnsafeBytes { raw in
                ShellXBridgeTee.consume(surfaceID: surfaceID, buffer: raw.bindMemory(to: UInt8.self))
            }
        }
        return snapshotData
    }

    func unbind(_ binding: BridgeBinding) { unbound.append(binding) }
}

/// A daemon stand-in: one blocking Unix-socket connection.
final class BridgeTestClient: @unchecked Sendable {
    private let fd: Int32
    private var decoder = BridgeFrameDecoder()
    private var pending: [BridgeFrame] = []
    private(set) var sawEOF = false

    init(path: String) throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in raw.copyBytes(from: bytes); raw[bytes.count] = 0 }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard rc == 0 else { close(fd); throw POSIXError(.ECONNREFUSED) }
    }

    deinit { close(fd) }

    func sendRaw(_ data: Data) {
        data.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: off), raw.count - off)
                if n <= 0 { return }
                off += n
            }
        }
    }

    func send(_ type: BridgeFrameType, _ payload: Data = Data()) {
        sendRaw(BridgeFrame(type: type, payload: payload).encoded())
    }

    func hello(protocolVersion: Int = 1, cols: Int = 80, rows: Int = 24, cwd: String? = "/tmp") {
        var object: [String: Any] = ["protocol": protocolVersion, "cols": cols, "rows": rows, "cwd": NSNull()]
        if let cwd { object["cwd"] = cwd }
        send(.hello, try! JSONSerialization.data(withJSONObject: object))
    }

    /// Next frame, or nil on EOF / timeout. Blocking: call through `next(_:)` from tests.
    func receiveBlocking(timeout: TimeInterval) -> BridgeFrame? {
        let deadline = Date().addingTimeInterval(timeout)
        var buf = [UInt8](repeating: 0, count: 65536)
        while pending.isEmpty {
            if sawEOF { return nil }
            let left = deadline.timeIntervalSinceNow
            if left <= 0 { return nil }
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let r = poll(&p, 1, Int32(max(1, left * 1000)))
            if r <= 0 { continue }
            let n = read(fd, &buf, buf.count)
            if n <= 0 { sawEOF = true; return nil }
            guard let frames = try? decoder.feed(Data(buf[0..<n])) else { sawEOF = true; return nil }
            pending += frames
        }
        return pending.removeFirst()
    }
}

extension BridgeTestClient {
    func next(timeout: TimeInterval = 3) async -> BridgeFrame? {
        await Task.detached { self.receiveBlocking(timeout: timeout) }.value
    }

    /// True when the server closes the connection (EOF) without sending another frame.
    func closedWithoutFrame(timeout: TimeInterval = 3) async -> Bool {
        let frame = await next(timeout: timeout)
        return frame == nil && sawEOF
    }

    /// Reads A, S and the snapshot O of a fresh attach.
    func handshake() async -> [BridgeFrame] {
        var frames: [BridgeFrame] = []
        for _ in 0..<3 { if let f = await next() { frames.append(f) } }
        return frames
    }
}

private struct ServerFixture {
    let dir: URL
    let socket: URL
    let server: ShellXBridgeServer

    func remove() {
        server.stop()
        try? FileManager.default.removeItem(at: dir)
    }
}

private func shortDir() -> URL {
    // sun_path is 104 bytes: keep the socket path short (not under $TMPDIR).
    URL(fileURLWithPath: "/tmp/sx-test-\(String(UInt32.random(in: .min ... .max), radix: 16))", isDirectory: true)
}

@MainActor
private func startServer(host: FakeBridgeHost, uid: @escaping () -> uid_t = getuid) throws -> ServerFixture {
    let dir = shortDir()
    let socket = dir.appendingPathComponent("bridge.sock")
    let server = ShellXBridgeServer(socket: socket, host: host, uid: uid)
    try server.start()
    return ServerFixture(dir: dir, socket: socket, server: server)
}

private func mode(_ path: String) -> mode_t {
    var st = stat()
    guard lstat(path, &st) == 0 else { return 0xFFFF }
    return st.st_mode & 0o777
}

@MainActor
private func eventually(_ timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
}

private func sizeOf(_ frame: BridgeFrame?) -> [UInt16]? {
    guard let frame, frame.type == .size, frame.payload.count == 4 else { return nil }
    let b = [UInt8](frame.payload)
    return [UInt16(b[0]) << 8 | UInt16(b[1]), UInt16(b[2]) << 8 | UInt16(b[3])]
}

@Suite(.serialized) @MainActor struct BridgeServerTests {
    @Test func socketAndDirAreOwnerOnly() throws {
        let host = FakeBridgeHost()
        let s = try startServer(host: host); defer { s.remove() }
        #expect(mode(s.socket.path) == 0o600)
        #expect(mode(s.dir.path) == 0o700)
        var st = stat()
        #expect(lstat(s.socket.path, &st) == 0 && st.st_mode & S_IFMT == S_IFSOCK)
        s.server.stop()
        #expect(lstat(s.socket.path, &st) != 0, "stop removes the socket file")
    }

    @Test func refusesForeignPeer() async throws {
        let host = FakeBridgeHost()
        let s = try startServer(host: host, uid: { getuid() + 1 }); defer { s.remove() }
        let client = try BridgeTestClient(path: s.socket.path)
        client.hello()
        #expect(await client.closedWithoutFrame())
        #expect(host.hellos.isEmpty)
    }

    @Test func refusesInsecureExistingDir() throws {
        let host = FakeBridgeHost()
        let dir = shortDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        chmod(dir.path, 0o755)
        let loose = ShellXBridgeServer(socket: dir.appendingPathComponent("bridge.sock"), host: host)
        #expect(throws: ShellXBridgeServer.StartError.self) { try loose.start() }
        chmod(dir.path, 0o701)
        #expect(throws: ShellXBridgeServer.StartError.self) { try loose.start() }

        // A symlink to a private dir is refused too.
        chmod(dir.path, 0o700)
        let link = shortDir()
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir)
        defer { unlink(link.path) }
        let linked = ShellXBridgeServer(socket: link.appendingPathComponent("bridge.sock"), host: host)
        #expect(throws: ShellXBridgeServer.StartError.self) { try linked.start() }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("bridge.sock").path))
    }

    @Test func refusesTooLongSocketPath() {
        let long = URL(fileURLWithPath: "/tmp/" + String(repeating: "x", count: 100) + "/bridge.sock")
        let server = ShellXBridgeServer(socket: long, host: FakeBridgeHost())
        #expect(throws: ShellXBridgeServer.StartError.pathTooLong) { try server.start() }
    }

    @Test func helloGetsAckSizeThenSnapshot() async throws {
        let host = FakeBridgeHost()
        host.teeDuringSnapshot = Data("during".utf8)
        let s = try startServer(host: host); defer { s.remove() }
        let client = try BridgeTestClient(path: s.socket.path)
        client.hello(cols: 100, rows: 30, cwd: "/Users/x")
        let frames = await client.handshake()
        try #require(frames.count == 3)
        #expect(frames[0].type == .ack)
        let ack = try #require(try JSONSerialization.jsonObject(with: frames[0].payload) as? [String: String])
        #expect(ack == ["mode": "attach", "surface_id": host.surfaceID.uuidString, "workspace_id": host.workspaceID.uuidString])
        #expect(sizeOf(frames[1]) == [94, 37])
        #expect(frames[2] == BridgeFrame(type: .output, payload: host.snapshotData!))
        // Output teed while the snapshot was taken was held and follows it.
        #expect(await client.next() == BridgeFrame(type: .output, payload: Data("during".utf8)))
        #expect(host.hellos == [BridgeHello(connectionID: host.hellos.first?.connectionID ?? -1,
                                            protocolVersion: 1, cols: 100, rows: 30, cwd: "/Users/x")])

        // Live tee output after the hold is streamed as O frames, byte exact.
        let live = Data([0x1b, 0x5b, 0x33, 0x31, 0x6d, 0xe1, 0xba])
        live.withUnsafeBytes { ShellXBridgeTee.consume(surfaceID: host.surfaceID, buffer: $0.bindMemory(to: UInt8.self)) }
        #expect(await client.next() == BridgeFrame(type: .output, payload: live))
    }

    @Test func inputReachesHostByteExact() async throws {                             // Review Focus 4
        let host = FakeBridgeHost()
        let s = try startServer(host: host); defer { s.remove() }
        let client = try BridgeTestClient(path: s.socket.path)
        client.hello()
        _ = await client.handshake()
        let bytes = Data("tiếng Việt\r".utf8)
        // Frame boundary inside "ế" (e1 ba | bf).
        client.send(.input, bytes.prefix(4))
        client.send(.input, bytes.dropFirst(4))
        #expect(await eventually { host.receivedInput == bytes })
        // One frame split across two socket writes, inside "ệ" (e1 bb | 87).
        let encoded = BridgeFrame(type: .input, payload: Data("Việt".utf8)).encoded()
        client.sendRaw(encoded.prefix(5 + 3))
        try? await Task.sleep(nanoseconds: 20_000_000)
        client.sendRaw(encoded.dropFirst(5 + 3))
        #expect(await eventually { host.receivedInput == bytes + Data("Việt".utf8) })
        #expect(Array(host.receivedInput.prefix(14)) == [0x74, 0x69, 0xe1, 0xba, 0xbf, 0x6e, 0x67, 0x20, 0x56, 0x69, 0xe1, 0xbb, 0x87, 0x74])
    }

    @Test func remoteResizeAlwaysEchoesHostGrid() async throws {
        let host = FakeBridgeHost()
        host.gridValue = (80, 24)
        let s = try startServer(host: host); defer { s.remove() }
        let client = try BridgeTestClient(path: s.socket.path)
        client.hello()
        _ = await client.handshake()
        client.send(.resize, Data([0, 120, 0, 40]))
        #expect(sizeOf(await client.next()) == [80, 24])
        #expect(host.resizes == [[120, 40]])
    }

    @Test func pollReportsChangedGrid() async throws {
        let host = FakeBridgeHost()
        let s = try startServer(host: host); defer { s.remove() }
        let client = try BridgeTestClient(path: s.socket.path)
        client.hello()
        _ = await client.handshake()
        host.gridValue = (132, 43)
        #expect(sizeOf(await client.next()) == [132, 43])
    }

    @Test func surfaceGoneSendsExit() async throws {
        let host = FakeBridgeHost()
        let s = try startServer(host: host); defer { s.remove() }
        let client = try BridgeTestClient(path: s.socket.path)
        client.hello()
        _ = await client.handshake()
        host.gridValue = nil
        #expect(await client.next()?.type == .exit)
        #expect(await client.closedWithoutFrame())
        #expect(await eventually { host.unbound.count == 1 })
        #expect(!ShellXBridgeTee.isBound(surfaceID: host.surfaceID))
    }

    @Test func killUnbindsWithoutClosingSurface() async throws {
        let host = FakeBridgeHost()
        let s = try startServer(host: host); defer { s.remove() }
        let client = try BridgeTestClient(path: s.socket.path)
        client.hello()
        _ = await client.handshake()
        #expect(ShellXBridgeTee.isBound(surfaceID: host.surfaceID))
        client.send(.kill)
        #expect(await eventually { host.unbound.count == 1 })
        #expect(host.closedSurfaces.isEmpty)
        #expect(await client.closedWithoutFrame())
        #expect(!ShellXBridgeTee.isBound(surfaceID: host.surfaceID))
    }

    @Test func eofUnbindsLikeKill() async throws {
        let host = FakeBridgeHost()
        let s = try startServer(host: host); defer { s.remove() }
        var client: BridgeTestClient? = try BridgeTestClient(path: s.socket.path)
        client?.hello()
        _ = await client?.handshake()
        client = nil
        #expect(await eventually { host.unbound.count == 1 })
        #expect(host.closedSurfaces.isEmpty)
    }

    @Test func stopUnbindsBoundConnections() async throws {
        let host = FakeBridgeHost()
        let s = try startServer(host: host); defer { s.remove() }
        let client = try BridgeTestClient(path: s.socket.path)
        client.hello()
        _ = await client.handshake()
        s.server.stop()
        #expect(await client.closedWithoutFrame())
        #expect(await eventually { host.unbound.count == 1 })
        #expect(host.closedSurfaces.isEmpty)
        #expect(!ShellXBridgeTee.isBound(surfaceID: host.surfaceID))
    }

    @Test func refusedBindAndBadHelloSendExit() async throws {
        let host = FakeBridgeHost()
        host.refuseBind = true
        let s = try startServer(host: host); defer { s.remove() }
        let refused = try BridgeTestClient(path: s.socket.path)
        refused.hello()
        #expect(await refused.next()?.type == .exit)
        #expect(await refused.closedWithoutFrame())

        let wrongProtocol = try BridgeTestClient(path: s.socket.path)
        wrongProtocol.hello(protocolVersion: 2)
        #expect(await wrongProtocol.next()?.type == .exit)

        let notHello = try BridgeTestClient(path: s.socket.path)
        notHello.send(.input, Data("ls\r".utf8))
        #expect(await notHello.next()?.type == .exit)
        #expect(host.hellos.count == 1, "only the well-formed hello reached the host")
        #expect(host.receivedInput.isEmpty)
    }

    @Test func oversizeFrameIsRefusedBeforeReadingPayload() async throws {
        let host = FakeBridgeHost()
        let s = try startServer(host: host); defer { s.remove() }
        let client = try BridgeTestClient(path: s.socket.path)
        let len = UInt32(BridgeFrameDecoder.maxPayload + 1)
        client.sendRaw(Data([BridgeFrameType.hello.rawValue, UInt8(len >> 24), UInt8((len >> 16) & 0xff),
                             UInt8((len >> 8) & 0xff), UInt8(len & 0xff)]))
        #expect(await client.closedWithoutFrame())
        #expect(host.hellos.isEmpty)
    }

    @Test func silentConnectionIsClosedAfterHelloDeadline() async throws {
        let host = FakeBridgeHost()
        let dir = shortDir()
        let server = ShellXBridgeServer(socket: dir.appendingPathComponent("bridge.sock"), host: host, helloTimeout: 0.2)
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: dir) }
        let silent = try BridgeTestClient(path: dir.appendingPathComponent("bridge.sock").path)
        #expect(await eventually { server.connectionCount == 1 })
        #expect(await silent.closedWithoutFrame())
        #expect(await eventually { server.connectionCount == 0 }, "the slot is freed")
        // A connection that says hello in time is not affected by the deadline.
        let talker = try BridgeTestClient(path: dir.appendingPathComponent("bridge.sock").path)
        talker.hello()
        #expect(await talker.next()?.type == .ack)
        try? await Task.sleep(nanoseconds: 400_000_000)
        #expect(server.connectionCount == 1)
        #expect(host.hellos.count == 1)
    }

    @Test func connectionCapIs32() async throws {
        let host = FakeBridgeHost()
        let s = try startServer(host: host); defer { s.remove() }
        var clients: [BridgeTestClient] = []
        for _ in 0..<ShellXBridgeServer.maxConnections { clients.append(try BridgeTestClient(path: s.socket.path)) }
        #expect(await eventually { s.server.connectionCount == ShellXBridgeServer.maxConnections })
        let extra = try BridgeTestClient(path: s.socket.path)
        #expect(await extra.closedWithoutFrame())
        clients[0].hello()
        #expect(await clients[0].next()?.type == .ack, "connections under the cap still work")
    }

    @Test func teeIgnoresUnboundSurfaces() {
        let bytes: [UInt8] = [1, 2, 3]
        bytes.withUnsafeBufferPointer { ShellXBridgeTee.consume(surfaceID: UUID(), buffer: $0) }
        #expect(!ShellXBridgeTee.isBound(surfaceID: UUID()))
    }

    @Test func teeDeliversToAnySinkOnlyWhileRegistered() {
        final class Sink: ShellXTeeSink, @unchecked Sendable {
            let lock = NSLock()
            var received = Data()
            func teeOutput(_ bytes: Data) { lock.lock(); received.append(bytes); lock.unlock() }
        }
        let sink = Sink(), surface = UUID()
        let send: ([UInt8]) -> Void = { bytes in
            bytes.withUnsafeBufferPointer { ShellXBridgeTee.consume(surfaceID: surface, buffer: $0) }
        }
        send([0x61])
        ShellXBridgeTee.register(sink, surfaceID: surface)
        ShellXBridgeTee.register(sink, surfaceID: surface)   // idempotent
        #expect(ShellXBridgeTee.isBound(surfaceID: surface))
        send([0x62, 0x63])
        ShellXBridgeTee.unregister(sink, surfaceID: surface)
        send([0x64])
        #expect(sink.received == Data([0x62, 0x63]))
        #expect(!ShellXBridgeTee.isBound(surfaceID: surface))
    }
}
