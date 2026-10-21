import Foundation
import os
#if canImport(Darwin)
import Darwin
#endif

private let bridgeLog = Logger(subsystem: "pro.shellx.desktop", category: "remote-bridge")

/// Serves the app's Mac terminals to the cmux-tui daemon's virtual PTY
/// (`cmux-tui-core/src/virtual_pty.rs`, W0 spike `4e1ed7bc41`) over a same-user Unix socket.
///
/// One connection = one daemon terminal. Per connection: `H` → `host.bind` → `A`, forced `S`,
/// snapshot `O` (tee output held until then), live `O`; `I` → `host.input` byte exact;
/// `R` → `host.remoteResize`, then `S` always; a 200 ms poll sends `S` when the grid changes and
/// `E` + unbind when the surface is gone; `K` or EOF → `host.unbind` only (D7: never closes a Mac tab).
///
/// Security: socket dir `0700` (an existing symlink, foreign-owned or `0o077` dir is refused),
/// bind under `umask(0o077)` then `chmod 0600`, peer uid (`getpeereid`) must equal `uid()` before
/// anything is read, at most `maxConnections`, frame cap checked on the header before the payload
/// is buffered, and logs carry counts only. Reads and writes run on separate queues per
/// connection so a stalled daemon reader never blocks input; host calls hop to the main queue.
public final class ShellXBridgeServer: @unchecked Sendable {
    public enum StartError: Error, Equatable, Sendable {
        case alreadyStarted
        case pathTooLong
        case insecureDirectory(reason: String)
        case notASocket
        case socketInUse
        case posix(operation: String, errno: Int32)
    }

    public static let maxConnections = 32
    /// Default time a connection has to send a valid `H` before it is closed (frees its slot).
    public static let defaultHelloTimeout: TimeInterval = 10
    /// Pause of the accept source after `EMFILE`/`ENFILE`, so a level-triggered source does not spin.
    static let acceptBackoff: DispatchTimeInterval = .milliseconds(100)

    public let socket: URL
    private let uid: () -> uid_t
    private let helloTimeout: TimeInterval
    private let router: BridgeRouter
    private let acceptQueue = DispatchQueue(label: "pro.shellx.remote-bridge.accept")

    private let lock = NSLock()
    private var listenSource: (any DispatchSourceRead)?
    private var socketIdentity: (dev: dev_t, ino: ino_t)?
    private var connections: [Int: BridgeConnection] = [:]
    private var nextConnectionID = 1
    private var refusedPeers = 0
    private var refusedOverCap = 0
    private var acceptStalls = 0

    public init(socket: URL, host: any ShellXBridgeHost, uid: @escaping () -> uid_t = getuid,
                helloTimeout: TimeInterval = ShellXBridgeServer.defaultHelloTimeout) {
        self.socket = socket
        self.uid = uid
        self.helloTimeout = helloTimeout
        self.router = BridgeRouter(host: host)
    }

    /// Live connections (accepted, peer-checked, not yet closed).
    public var connectionCount: Int {
        lock.lock(); defer { lock.unlock() }
        return connections.count
    }

    public func start() throws {
        lock.lock(); defer { lock.unlock() }
        guard listenSource == nil else { throw StartError.alreadyStarted }
        let path = socket.path
        var addr = sockaddr_un()
        let pathBytes = Array(path.utf8)
        guard !pathBytes.isEmpty, pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            throw StartError.pathTooLong
        }
        try Self.preparePrivateDirectory(socket.deletingLastPathComponent().path)
        try Self.removeStaleSocket(path)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw StartError.posix(operation: "socket", errno: errno) }
        var keepFD = false
        defer { if !keepFD { Darwin.close(fd) } }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
            raw[pathBytes.count] = 0
        }
        let oldMask = umask(0o077)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        let bindErrno = errno
        umask(oldMask)
        guard bound == 0 else { throw StartError.posix(operation: "bind", errno: bindErrno) }
        guard chmod(path, 0o600) == 0 else {
            let code = errno
            unlink(path)
            throw StartError.posix(operation: "chmod", errno: code)
        }
        var st = stat()
        guard lstat(path, &st) == 0 else { throw StartError.posix(operation: "lstat", errno: errno) }
        guard listen(fd, Int32(Self.maxConnections)) == 0 else {
            let code = errno
            unlink(path)
            throw StartError.posix(operation: "listen", errno: code)
        }
        socketIdentity = (st.st_dev, st.st_ino)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in self?.acceptPending(listenFD: fd) }
        source.setCancelHandler { Darwin.close(fd) }
        listenSource = source
        keepFD = true
        source.resume()
        bridgeLog.info("bridge listening")
    }

    /// Stops accepting, removes the socket file (if it is still ours) and closes every connection;
    /// each closed connection is unbound on the main queue.
    public func stop() {
        lock.lock()
        let source = listenSource
        listenSource = nil
        let identity = socketIdentity
        socketIdentity = nil
        let live = Array(connections.values)
        lock.unlock()
        guard let source else { return }
        source.cancel()
        var st = stat()
        if let identity, lstat(socket.path, &st) == 0, st.st_dev == identity.dev, st.st_ino == identity.ino {
            unlink(socket.path)
        }
        for connection in live { connection.end(graceful: false) }
        bridgeLog.info("bridge stopped, closed \(live.count) connection(s)")
    }

    // MARK: - Accept

    /// acceptQueue.
    private func acceptPending(listenFD: Int32) {
        while true {
            let client = accept(listenFD, nil, nil)
            if client < 0 {
                let code = errno
                if code == EINTR || code == ECONNABORTED { continue }
                if code == EMFILE || code == ENFILE { pauseAccepting() }
                return // EAGAIN: drained; anything else: the source fires again or is cancelled.
            }
            admit(client)
        }
    }

    /// Out of descriptors: the pending connection stays queued and the level-triggered source would
    /// fire again at once, so suspend it briefly instead of spinning.
    private func pauseAccepting() {
        lock.lock()
        guard let source = listenSource else { lock.unlock(); return }
        acceptStalls += 1
        let total = acceptStalls
        lock.unlock()
        source.suspend()
        bridgeLog.error("bridge accept out of descriptors, pausing (total \(total))")
        acceptQueue.asyncAfter(deadline: .now() + Self.acceptBackoff) { source.resume() }
    }

    private func admit(_ fd: Int32) {
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        // BSD accept inherits O_NONBLOCK from the listener; connections use blocking I/O.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        // Peer check before reading a single byte.
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(fd, &peerUID, &peerGID) == 0, peerUID == uid() else {
            Darwin.close(fd)
            lock.lock(); refusedPeers += 1; let total = refusedPeers; lock.unlock()
            bridgeLog.error("bridge refused a connection from another user (total \(total))")
            return
        }

        lock.lock()
        guard listenSource != nil, connections.count < Self.maxConnections else {
            refusedOverCap += 1
            let total = refusedOverCap
            lock.unlock()
            Darwin.close(fd)
            bridgeLog.error("bridge refused a connection over the cap (total \(total))")
            return
        }
        let id = nextConnectionID
        nextConnectionID += 1
        // The router is captured strongly: a connection closed after the server is released
        // must still be unbound (tee unregistered, viewport participant cleared).
        let connection = BridgeConnection(fd: fd, id: id, router: router, helloTimeout: helloTimeout) { [weak self, router] id in
            self?.forget(id)
            DispatchQueue.main.async { MainActor.assumeIsolated { router.unbind(connectionID: id) } }
        }
        connections[id] = connection
        lock.unlock()
        connection.start()
    }

    private func forget(_ id: Int) {
        lock.lock()
        connections.removeValue(forKey: id)
        lock.unlock()
    }

    // MARK: - Filesystem

    /// Creates `path` `0700`, or accepts an existing real directory owned by this user with no
    /// group/other bits. A symlink, foreign owner or loose mode is refused, never repaired.
    static func preparePrivateDirectory(_ path: String) throws {
        if mkdir(path, 0o700) != 0, errno != EEXIST {
            throw StartError.posix(operation: "mkdir", errno: errno)
        }
        var st = stat()
        guard lstat(path, &st) == 0 else { throw StartError.posix(operation: "lstat dir", errno: errno) }
        if st.st_mode & S_IFMT == S_IFLNK { throw StartError.insecureDirectory(reason: "is a symlink") }
        guard st.st_mode & S_IFMT == S_IFDIR else { throw StartError.insecureDirectory(reason: "not a directory") }
        guard st.st_uid == geteuid() else { throw StartError.insecureDirectory(reason: "not owned by the current user") }
        guard st.st_mode & 0o077 == 0 else { throw StartError.insecureDirectory(reason: "group/other permissions set (need 0700)") }
    }

    /// Unlinks a stale socket left by a crashed run; refuses a live one or a non-socket.
    private static func removeStaleSocket(_ path: String) throws {
        var st = stat()
        guard lstat(path, &st) == 0 else { return }
        guard st.st_mode & S_IFMT == S_IFSOCK else { throw StartError.notASocket }
        if socketAcceptsConnections(path) { throw StartError.socketInUse }
        guard unlink(path) == 0 || errno == ENOENT else { throw StartError.posix(operation: "unlink", errno: errno) }
    }

    private static func socketAcceptsConnections(_ path: String) -> Bool {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
    }
}

// MARK: - Connection

/// One daemon connection. Reads run on `readQueue` (a read source), writes on the serial
/// `writeQueue`, so the two never wait on each other. The tee calls `teeOutput` from the
/// libghostty IO thread.
final class BridgeConnection: ShellXTeeSink, @unchecked Sendable {
    /// Queued-but-unwritten bytes (held tee output included) above which the connection is dropped,
    /// so a daemon that stops reading cannot grow app memory without bound.
    static let maxPendingBytes = 64 << 20
    private static let readChunk = 64 << 10
    private static let gracefulCloseTimeout: TimeInterval = 2

    let id: Int
    private let fd: Int32
    private let router: BridgeRouter
    private let onClosed: @Sendable (Int) -> Void
    private let helloTimeout: TimeInterval
    private let readQueue: DispatchQueue
    private let writeQueue: DispatchQueue

    // readQueue only.
    private var readSource: (any DispatchSourceRead)?
    private var decoder = BridgeFrameDecoder()
    private var readBuffer: [UInt8]
    private var sawHello = false

    // Guarded by `lock`.
    private let lock = NSLock()
    private var ended = false
    private var shutDown = false
    private var fdClosed = false
    private var holding = true
    private var held: [Data] = []
    private var pendingBytes = 0
    private var bytesIn = 0
    private var bytesOut = 0

    init(fd: Int32, id: Int, router: BridgeRouter, helloTimeout: TimeInterval,
         onClosed: @escaping @Sendable (Int) -> Void) {
        self.fd = fd
        self.id = id
        self.router = router
        self.helloTimeout = helloTimeout
        self.onClosed = onClosed
        readQueue = DispatchQueue(label: "pro.shellx.remote-bridge.read.\(id)")
        writeQueue = DispatchQueue(label: "pro.shellx.remote-bridge.write.\(id)", qos: .userInitiated)
        readBuffer = [UInt8](repeating: 0, count: Self.readChunk)
    }

    func start() {
        readQueue.async { [self] in
            // Ended (server stopped) before reading began: no source to cancel, close directly.
            if isEnded {
                writeQueue.async { [self] in closeDescriptor() }
                return
            }
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: readQueue)
            source.setEventHandler { [self] in readAvailable() }
            source.setCancelHandler { [self] in
                writeQueue.async { [self] in closeDescriptor() }
            }
            readSource = source
            source.resume()
            // A peer that never sends a valid hello must not hold one of the capped slots.
            readQueue.asyncAfter(deadline: .now() + helloTimeout) { [self] in
                guard !sawHello else { return }
                bridgeLog.error("bridge conn \(self.id) no hello in time, closing")
                end(graceful: false)
            }
        }
    }

    var isEnded: Bool {
        lock.lock(); defer { lock.unlock() }
        return ended
    }

    // MARK: Reading (readQueue)

    private func readAvailable() {
        let n = readBuffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        if n < 0 {
            if errno == EINTR || errno == EAGAIN { return }
            end(graceful: false)
            return
        }
        if n == 0 {
            end(graceful: true) // EOF: unbind only, like K.
            return
        }
        let frames: [BridgeFrame]
        do {
            // The decoder rejects a header whose length exceeds the cap before buffering its payload.
            frames = try decoder.feed(Data(readBuffer[0..<n]))
        } catch {
            bridgeLog.error("bridge conn \(self.id) protocol error, closing")
            end(graceful: false)
            return
        }
        for frame in frames where !dispatch(frame) { break }
    }

    /// Routes one daemon frame; false stops reading.
    private func dispatch(_ frame: BridgeFrame) -> Bool {
        let router = self.router
        guard sawHello else {
            guard frame.type == .hello, let hello = BridgeHello.parse(frame.payload, connectionID: id) else {
                bridgeLog.error("bridge conn \(self.id) bad hello, refusing")
                send(BridgeFrame(type: .exit, payload: Data()))
                end(graceful: true)
                return false
            }
            sawHello = true
            DispatchQueue.main.async { [self] in MainActor.assumeIsolated { router.bind(self, hello: hello) } }
            return true
        }
        switch frame.type {
        case .input:
            lock.lock(); bytesIn += frame.payload.count; lock.unlock()
            let bytes = frame.payload
            let id = self.id
            DispatchQueue.main.async { MainActor.assumeIsolated { router.input(connectionID: id, bytes: bytes) } }
        case .resize where frame.payload.count == 4:
            let b = [UInt8](frame.payload)
            let cols = UInt16(b[0]) << 8 | UInt16(b[1])
            let rows = UInt16(b[2]) << 8 | UInt16(b[3])
            let id = self.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { router.remoteResize(connectionID: id, cols: cols, rows: rows) }
            }
        case .kill:
            end(graceful: true) // unbind only (D7); the close hook unbinds on main.
            return false
        default:
            break // A second hello or an app->daemon type: ignored.
        }
        return true
    }

    // MARK: Writing

    func send(_ frame: BridgeFrame) {
        let bytes = frame.encoded()
        lock.lock()
        guard !ended else { lock.unlock(); return }
        let ok = enqueueLocked(bytes)
        lock.unlock()
        if !ok { overflow() }
    }

    /// Called on the libghostty IO thread for every chunk of the bound surface's output.
    func teeOutput(_ bytes: Data) {
        lock.lock()
        guard !ended else { lock.unlock(); return }
        bytesOut += bytes.count
        let ok: Bool
        if holding {
            held.append(bytes)
            pendingBytes += bytes.count
            ok = pendingBytes <= Self.maxPendingBytes
        } else {
            ok = enqueueLocked(BridgeFrame(type: .output, payload: bytes).encoded())
        }
        lock.unlock()
        if !ok { overflow() }
    }

    /// Ends the attach hold: the snapshot goes first, then output teed while it was taken
    /// (may repeat a few bytes the snapshot already shows, as in the spike).
    func releaseHold(snapshot: Data?) {
        lock.lock()
        guard !ended, holding else { lock.unlock(); return }
        holding = false
        let chunks = held
        held.removeAll()
        pendingBytes -= chunks.reduce(0) { $0 + $1.count }
        var ok = true
        if let snapshot, !snapshot.isEmpty {
            ok = enqueueLocked(BridgeFrame(type: .output, payload: snapshot).encoded())
        }
        for chunk in chunks where ok {
            ok = enqueueLocked(BridgeFrame(type: .output, payload: chunk).encoded())
        }
        lock.unlock()
        if !ok { overflow() }
    }

    /// Requires `lock`. False when the pending cap is exceeded (nothing queued then).
    private func enqueueLocked(_ bytes: Data) -> Bool {
        guard pendingBytes + bytes.count <= Self.maxPendingBytes else { return false }
        pendingBytes += bytes.count
        writeQueue.async { [self] in writeAll(bytes) }
        return true
    }

    private func overflow() {
        bridgeLog.error("bridge conn \(self.id) daemon not reading, dropping the connection")
        end(graceful: false)
    }

    private func writeAll(_ bytes: Data) {
        defer { lock.lock(); pendingBytes -= bytes.count; lock.unlock() }
        lock.lock()
        let dead = shutDown
        lock.unlock()
        if dead { return }
        let failed = bytes.withUnsafeBytes { raw -> Bool in
            guard var p = raw.baseAddress else { return false }
            var left = raw.count
            while left > 0 {
                let n = Darwin.write(fd, p, left)
                if n < 0 {
                    if errno == EINTR { continue }
                    return true
                }
                left -= n
                p = p.advanced(by: n)
            }
            return false
        }
        if failed { end(graceful: false) }
    }

    // MARK: Closing

    /// Stops the connection. Graceful: frames already queued (an `E`) are written first, with a
    /// timeout in case the daemon stopped reading. The descriptor is closed once both the read
    /// source is cancelled and the write queue is drained; then `onClosed` unbinds on main.
    func end(graceful: Bool) {
        lock.lock()
        let first = !ended
        ended = true
        if first { held.removeAll() }
        lock.unlock()
        if graceful && first {
            writeQueue.async { [self] in shutdownSocket() }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.gracefulCloseTimeout) { [self] in shutdownSocket() }
        } else {
            shutdownSocket()
        }
        if first {
            readQueue.async { [self] in readSource?.cancel() }
        }
    }

    /// `shutdown(2)` wakes a write blocked on a daemon that stopped reading.
    private func shutdownSocket() {
        lock.lock(); defer { lock.unlock() }
        guard !shutDown, !fdClosed else { return }
        shutDown = true
        Darwin.shutdown(fd, SHUT_RDWR)
    }

    /// writeQueue, after the read source's cancel.
    private func closeDescriptor() {
        lock.lock()
        let already = fdClosed
        fdClosed = true
        shutDown = true
        let counts = (bytesIn, bytesOut)
        lock.unlock()
        guard !already else { return }
        Darwin.close(fd)
        bridgeLog.info("bridge conn \(self.id) closed (in=\(counts.0) B, out=\(counts.1) B)")
        onClosed(id)
    }
}

// MARK: - Router (main actor)

/// Main-actor side: bindings, host calls and the 200 ms grid poll.
@MainActor
final class BridgeRouter {
    private struct Grid: Equatable { let cols, rows: UInt16 }

    private struct Entry {
        let binding: BridgeBinding
        let connection: BridgeConnection
        var lastGrid: Grid?
    }

    static let pollInterval: DispatchTimeInterval = .milliseconds(200)

    nonisolated private let host: any ShellXBridgeHost
    private var entries: [Int: Entry] = [:]
    private var timer: (any DispatchSourceTimer)?

    nonisolated init(host: any ShellXBridgeHost) {
        self.host = host
    }

    func bind(_ connection: BridgeConnection, hello: BridgeHello) {
        // A connection that died while the hop was queued must not open a Mac tab.
        guard !connection.isEnded, entries[connection.id] == nil else { return }
        guard let proposed = host.bind(hello: hello) else {
            bridgeLog.info("bridge conn \(connection.id) bind refused by host")
            connection.send(BridgeFrame(type: .exit, payload: Data()))
            connection.end(graceful: true)
            return
        }
        let binding = BridgeBinding(connectionID: connection.id, surfaceID: proposed.surfaceID,
                                    workspaceID: proposed.workspaceID, mode: proposed.mode)
        ShellXBridgeTee.register(connection, surfaceID: binding.surfaceID) // held until releaseHold
        entries[connection.id] = Entry(binding: binding, connection: connection, lastGrid: nil)
        bridgeLog.info("bridge conn \(connection.id) bound mode=\(binding.mode, privacy: .public)")
        connection.send(BridgeFrame(type: .ack, payload: binding.ackPayload))
        guard sendGrid(connectionID: connection.id, force: true) else { return }
        connection.releaseHold(snapshot: host.snapshot(binding: binding))
        startTimerIfNeeded()
    }

    func input(connectionID: Int, bytes: Data) {
        guard let entry = entries[connectionID] else { return }
        host.input(bytes, binding: entry.binding)
    }

    func remoteResize(connectionID: Int, cols: UInt16, rows: UInt16) {
        guard let entry = entries[connectionID] else { return }
        host.remoteResize(cols: cols, rows: rows, binding: entry.binding)
        // Always echo: the Mac owns the PTY, a wish it could not honour must reach the mirror.
        sendGrid(connectionID: connectionID, force: true)
    }

    func poll() {
        for id in Array(entries.keys) { sendGrid(connectionID: id, force: false) }
    }

    /// Sends `S` (when forced or changed); a gone surface sends `E` and unbinds. False if unbound.
    @discardableResult
    private func sendGrid(connectionID: Int, force: Bool) -> Bool {
        guard let entry = entries[connectionID] else { return false }
        guard let grid = host.grid(binding: entry.binding) else {
            bridgeLog.info("bridge conn \(connectionID) surface gone, sending exit")
            entry.connection.send(BridgeFrame(type: .exit, payload: Data()))
            unbind(connectionID: connectionID)
            return false
        }
        let current = Grid(cols: grid.cols, rows: grid.rows)
        if force || entry.lastGrid != current {
            entries[connectionID]?.lastGrid = current
            entry.connection.send(BridgeFrame.size(cols: current.cols, rows: current.rows))
        }
        return true
    }

    /// Unbinds without closing the Mac surface (D7). Idempotent.
    func unbind(connectionID: Int) {
        guard let entry = entries.removeValue(forKey: connectionID) else { return }
        ShellXBridgeTee.unregister(entry.connection, surfaceID: entry.binding.surfaceID)
        host.unbind(entry.binding)
        entry.connection.end(graceful: true)
        bridgeLog.info("bridge conn \(connectionID) unbound (\(self.entries.count) bound)")
        if entries.isEmpty {
            timer?.cancel()
            timer = nil
        }
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + Self.pollInterval, repeating: Self.pollInterval)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.poll() } }
        timer = source
        source.resume()
    }
}
