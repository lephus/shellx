import Foundation
import os

/// The host side of one share link: registers the share's own slot on relay2 and serves one
/// encrypted circuit per viewer, enforcing the share's permission and expiry.
///
/// Control socket: `register` -> `registered`, `ping` every 10 s (no `pong` within 25 s fails the
/// socket), a fresh socket and `register` every 90 s (the old one is closed after the new
/// `registered`), backoff 1/2/4/8/16/30 s on errors.
/// Circuit: `incoming` -> new socket -> `join(role: daemon)` -> `ready` -> wait <= 10 s for `hello`
/// (anything else is dropped) -> `welcome` + `replay` of the active pane -> `out`/`size` of the
/// viewer's selected pane only, and `ka` after 60 s without traffic.
/// Slow viewers: once more than `maxBacklogBytes` of `out` is queued, the queued and buffered
/// output is discarded and a fresh `replay` follows when the writer drains (drop-to-replay);
/// more than 3 resyncs in 10 s ends the circuit.
public actor ShareHost {
    static let pingInterval: TimeInterval = 10
    static let pongTimeout: TimeInterval = 25
    static let reRegisterInterval: TimeInterval = 90
    static let registerTimeout: TimeInterval = 10
    static let helloTimeout: TimeInterval = 10
    static let keepaliveInterval: TimeInterval = 60
    static let maxInputBytes = 4 * 1024
    static let maxLabelCharacters = 40
    /// Raw bytes per `out`/`replay` frame; base64 + JSON keeps the plaintext under 48 KiB.
    static let chunkBytes = 32 * 1024
    /// Per circuit: queued frames and the output pump buffer each stay at or below this.
    static let maxBacklogBytes = 1024 * 1024
    static let maxResyncs = 3
    static let resyncWindow: TimeInterval = 10

    private let shareID: String
    private let slot: String
    private let permission: SharePermission
    private let expiresAt: Date?
    private let source: any ShareSource
    private let tickets: any ShareTicketProvider
    private let sockets: any ShareSocketFactory
    private let clock: @Sendable () -> Date
    private let sleeper: any ShareSleeper
    private let coalesceInterval: Duration
    private let keys: ShareKeys

    public nonisolated let viewerStream: AsyncStream<[ShareViewer]>
    private let viewerContinuation: AsyncStream<[ShareViewer]>.Continuation

    /// `in` frames refused: view-only or expired share, unknown or non-terminal pane, or over 4 KiB.
    public private(set) var droppedInputCount = 0
    /// Frames that failed to open, or were not `hello` before the handshake.
    public private(set) var droppedFrameCount = 0

    private var running = false
    private var stopped = false
    private var relayURL: URL?

    private struct Control { let socket: any ShareSocket; let generation: Int }
    private var current: Control?
    private var pending: Control?
    private var connectingGeneration: Int?
    private var controlGeneration = 0
    private var attempt = 0
    private var pingNonce: UInt64 = 0
    private(set) var lastPongNonce: UInt64 = 0
    private var registerTimer: Int?
    private var pingTimer: Int?

    private enum Stage { case joining, awaitingHello, live }

    /// One queued frame; `outEpoch` marks droppable `out` data.
    private struct Outgoing: Sendable {
        let message: ShareSocketMessage
        let bytes: Int
        let outEpoch: Int?
    }

    private struct Circuit {
        let serial: Int
        let socket: any ShareSocket
        let outbox: AsyncStream<Outgoing>.Continuation
        let writer: Task<Void, Never>
        var cipher: ShareCipher
        var stage = Stage.joining
        var helloTimer: Int?
        var keepaliveTimer: Int?
        var lastSentAt: Date
        var viewer: ShareViewer?
        var pane: String?
        var subscription: ShareSubscription?
        var pump: ShareOutputPump?
        /// The pane the viewer asked for; only a viewer `select` of an existing pane sets it.
        var wantedPane: String?
        /// Bumped at the start of every select; only the latest request commits.
        var selectRequest = 0
        var subscriptionGeneration = 0
        var queuedBytes = 0
        var queuedItems = 0
        var outEpoch = 0
        var resyncPending = false
        var resyncTimes: [Date] = []
    }
    private var circuits: [String: Circuit] = [:]
    private var nextCircuitSerial = 0
    private var knownPanes: [SharePane] = []
    /// Test seam: awaited inside every select before it reads the source, with the target pane.
    private var selectHook: (@Sendable (String) async -> Void)?
    func setSelectHook(_ hook: (@Sendable (String) async -> Void)?) { selectHook = hook }

    private enum TimerAction: Sendable {
        case ping(Int), pongTimeout(Int, UInt64), reRegister(Int), registerTimeout(Int), reconnect
        case helloTimeout(String, Int), keepalive(String, Int), expiry
    }
    private var timers: [Int: Task<Void, Never>] = [:]
    private var nextTimerID = 0

    public init(shareID: String, slot: String, secret: ShareSecret, permission: SharePermission, expiresAt: Date?,
                source: any ShareSource, tickets: any ShareTicketProvider, sockets: any ShareSocketFactory,
                clock: @escaping @Sendable () -> Date = Date.init, sleeper: (any ShareSleeper)? = nil,
                coalesceInterval: Duration = .milliseconds(16)) {
        self.shareID = shareID.replacingOccurrences(of: "-", with: "")
        self.slot = slot
        self.permission = permission
        self.expiresAt = expiresAt
        self.source = source
        self.tickets = tickets
        self.sockets = sockets
        self.clock = clock
        self.sleeper = sleeper ?? ShareSystemSleeper(clock: clock)
        self.coalesceInterval = coalesceInterval
        self.keys = secret.keys(shareID: shareID)
        (viewerStream, viewerContinuation) = AsyncStream.makeStream(of: [ShareViewer].self)
    }

    public var viewers: [ShareViewer] {
        circuits.values.compactMap(\.viewer).sorted { ($0.connectedAt, $0.id) < ($1.connectedAt, $1.id) }
    }

    var isRegistered: Bool { current != nil }
    func backlogBytes(_ id: String) -> Int? { circuits[id]?.queuedBytes }
    func isResyncing(_ id: String) -> Bool { circuits[id]?.resyncPending ?? false }

    private var isExpired: Bool { expiresAt.map { clock() >= $0 } ?? false }

    // MARK: Lifecycle

    public func start() async {
        guard !running, !stopped else { return }
        running = true
        let source = self.source
        knownPanes = await MainActor.run {
            source.onPanesChanged = { [weak self] in Task { await self?.panesChanged() } }
            return source.panes
        }
        guard running else { return }
        connectControl()
        if let expiresAt { schedule(.expiry, at: expiresAt) }
    }

    /// Sends `bye(reason)` on every circuit, closes every socket and finishes `viewerStream`.
    public func stop(reason: ShareByeReason) async {
        await shutdown(reason: reason, mainActorAvailable: true)
    }

    /// Quit (`applicationWillTerminate`, main thread blocked): like `stop`, but never waits on the main
    /// actor. `onPanesChanged` and the output subscriptions are left for process exit.
    public func stopForTermination(reason: ShareByeReason) async {
        await shutdown(reason: reason, mainActorAvailable: false)
    }

    private func shutdown(reason: ShareByeReason, mainActorAvailable: Bool) async {
        guard !stopped else { return }
        stopped = true
        running = false
        for timer in timers.values { timer.cancel() }
        timers.removeAll()
        let source = self.source
        if mainActorAvailable { await MainActor.run { source.onPanesChanged = nil } }
        var ending: [(any ShareSocket, Task<Void, Never>)] = []
        for id in Array(circuits.keys) {
            if let ended = await endCircuit(id, bye: reason, releaseSubscription: mainActorAvailable) {
                ending.append(ended)
            }
        }
        let writers = ending.map(\.1)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { for writer in writers { await writer.value } }
            group.addTask { try? await Task.sleep(for: .seconds(1)) }
            await group.next()
            group.cancelAll()
        }
        for (socket, _) in ending { socket.close() }
        current?.socket.close(); current = nil
        pending?.socket.close(); pending = nil
        viewerContinuation.finish()
    }

    // MARK: Timers

    @discardableResult
    private func schedule(_ action: TimerAction, at deadline: Date) -> Int {
        nextTimerID += 1
        let id = nextTimerID
        let sleeper = self.sleeper
        timers[id] = Task {
            do { try await sleeper.sleep(until: deadline) } catch { return }
            await self.fire(id, action)
        }
        return id
    }

    private func cancelTimer(_ id: Int?) {
        guard let id else { return }
        timers.removeValue(forKey: id)?.cancel()
    }

    private func fire(_ id: Int, _ action: TimerAction) async {
        guard timers.removeValue(forKey: id) != nil, running else { return }
        switch action {
        case .ping(let generation): await ping(generation)
        case .pongTimeout(let generation, let nonce):
            if current?.generation == generation, lastPongNonce < nonce { controlFailed(generation) }
        case .reRegister(let generation):
            if current?.generation == generation, connectingGeneration == nil { connectControl() }
        case .registerTimeout(let generation):
            if pending?.generation == generation { controlFailed(generation) }
        case .reconnect: connectControl()
        case .helloTimeout(let circuit, let serial):
            if let c = circuits[circuit], c.serial == serial, c.stage != .live { _ = await endCircuit(circuit, bye: nil) }
        case .keepalive(let circuit, let serial): keepalive(circuit, serial: serial)
        case .expiry:
            await stop(reason: .expired) // this timer is already untracked, so stop cannot cancel it
        }
    }

    // MARK: Control socket

    private func connectControl() {
        guard running, connectingGeneration == nil else { return }
        controlGeneration += 1
        let generation = controlGeneration
        connectingGeneration = generation
        Task { await self.openControl(generation) }
    }

    private func openControl(_ generation: Int) async {
        do {
            let ticket = try await tickets.hostTicket(shareID: shareID)
            guard running else { return }
            relayURL = ticket.relayURL
            let socket = try await sockets.open(ticket.relayURL)
            guard running, connectingGeneration == generation else { socket.close(); return }
            pending = Control(socket: socket, generation: generation)
            Task { await self.readControl(socket, generation) }
            registerTimer = schedule(.registerTimeout(generation), at: clock() + Self.registerTimeout)
            try await socket.send(text: ShareRelayControl.register(protocol: ShareRelayControl.protocolVersion,
                                                                   slot: slot, ticket: ticket.ticket).encoded())
        } catch {
            controlFailed(generation)
        }
    }

    private func readControl(_ socket: any ShareSocket, _ generation: Int) async {
        do {
            while true {
                if case .text(let text) = try await socket.receive(), let message = ShareRelayControl.decode(text) {
                    await handleControl(message, generation)
                }
            }
        } catch {
            controlFailed(generation)
        }
    }

    private func handleControl(_ message: ShareRelayControl, _ generation: Int) async {
        guard running else { return }
        switch message {
        case .registered:
            guard let new = pending, new.generation == generation else { return }
            let old = current
            current = new
            pending = nil
            connectingGeneration = nil
            attempt = 0
            lastPongNonce = pingNonce // pings sent on the old socket are not owed a pong here
            cancelTimer(registerTimer); registerTimer = nil
            old?.socket.close()
            cancelTimer(pingTimer)
            let now = clock()
            pingTimer = schedule(.ping(generation), at: now + Self.pingInterval)
            schedule(.reRegister(generation), at: now + Self.reRegisterInterval)
        case .pong(let nonce):
            if current?.generation == generation { lastPongNonce = max(lastPongNonce, nonce) }
        case .incoming(let circuit, let lane, let circuitGeneration, let joinTicket):
            openCircuit(circuit, lane: lane, generation: circuitGeneration, joinTicket: joinTicket)
        case .error:
            controlFailed(generation)
        default:
            break
        }
    }

    private func ping(_ generation: Int) async {
        guard let control = current, control.generation == generation else { return }
        pingNonce += 1
        let nonce = pingNonce
        let now = clock()
        pingTimer = schedule(.ping(generation), at: now + Self.pingInterval)
        schedule(.pongTimeout(generation, nonce), at: now + Self.pongTimeout)
        do {
            try await control.socket.send(text: ShareRelayControl.ping(nonce: nonce).encoded())
        } catch {
            controlFailed(generation)
        }
    }

    private func controlFailed(_ generation: Int) {
        if let p = pending, p.generation == generation {
            p.socket.close(); pending = nil
        } else if let c = current, c.generation == generation {
            c.socket.close(); current = nil
            cancelTimer(pingTimer); pingTimer = nil
        } else if connectingGeneration != generation {
            return // a socket that was already replaced
        }
        if connectingGeneration == generation {
            connectingGeneration = nil
            cancelTimer(registerTimer); registerTimer = nil
        }
        guard running, connectingGeneration == nil else { return }
        let delay = ReconnectBackoff.delay(attempt: attempt)
        attempt += 1
        schedule(.reconnect, at: clock() + delay)
    }

    // MARK: Circuits

    private func openCircuit(_ id: String, lane: String, generation: UInt64, joinTicket: String) {
        guard running, let url = relayURL, circuits[id] == nil else { return }
        let join = ShareRelayControl.join(protocol: ShareRelayControl.protocolVersion, slot: slot, circuit: id,
                                          lane: lane, generation: generation, ticket: joinTicket, role: .daemon)
        Task {
            guard let socket = try? await self.sockets.open(url) else { return }
            self.attachCircuit(id, socket: socket, join: join)
        }
    }

    private func attachCircuit(_ id: String, socket: any ShareSocket, join: ShareRelayControl) {
        guard running, circuits[id] == nil else { socket.close(); return }
        nextCircuitSerial += 1
        let serial = nextCircuitSerial
        let (outbox, continuation) = AsyncStream.makeStream(of: Outgoing.self)
        let writer = Task {
            for await item in outbox {
                if let epoch = item.outEpoch, self.isStale(id, serial, outEpoch: epoch) {
                    await self.dequeued(id, serial, bytes: item.bytes)
                    continue
                }
                do {
                    switch item.message {
                    case .text(let text): try await socket.send(text: text)
                    case .data(let data): try await socket.send(data: data)
                    }
                } catch {
                    await self.circuitFailed(id, serial)
                    break
                }
                await self.dequeued(id, serial, bytes: item.bytes)
            }
            socket.close()
        }
        circuits[id] = Circuit(serial: serial, socket: socket, outbox: continuation, writer: writer,
                               cipher: ShareCipher(sendKey: keys.hostToViewer, receiveKey: keys.viewerToHost, circuit: id),
                               lastSentAt: clock())
        let text = join.encoded()
        enqueue(id, Outgoing(message: .text(text), bytes: text.utf8.count, outEpoch: nil))
        Task {
            do {
                while true { await self.handleCircuit(id, serial, try await socket.receive()) }
            } catch {
                await self.circuitFailed(id, serial)
            }
        }
    }

    private func isLive(_ id: String, _ serial: Int) -> Bool { circuits[id]?.serial == serial }

    private func isStale(_ id: String, _ serial: Int, outEpoch: Int) -> Bool {
        guard let circuit = circuits[id], circuit.serial == serial else { return true }
        return outEpoch < circuit.outEpoch
    }

    private func circuitFailed(_ id: String, _ serial: Int) async {
        if isLive(id, serial) { _ = await endCircuit(id, bye: nil) }
    }

    private func handleCircuit(_ id: String, _ serial: Int, _ message: ShareSocketMessage) async {
        guard running, var circuit = circuits[id], circuit.serial == serial else { return }
        switch message {
        case .text(let text):
            if circuit.stage == .joining, case .ready = ShareRelayControl.decode(text) {
                circuit.stage = .awaitingHello
                circuit.helloTimer = schedule(.helloTimeout(id, serial), at: clock() + Self.helloTimeout)
                circuits[id] = circuit
            } else {
                _ = await endCircuit(id, bye: nil) // relay error, or text on a paired circuit
            }
        case .data(let frame):
            guard circuit.stage != .joining else { return }
            let opened = circuit.cipher.open(frame)
            circuits[id] = circuit
            guard let opened else { droppedFrameCount += 1; return }
            switch (circuit.stage, opened) {
            case (.awaitingHello, .hello(let nonce, let label)):
                await welcome(id, viewerNonce: nonce, label: label)
            case (.live, .select(let pane)):
                await viewerSelect(id, pane: pane)
            case (.live, .input(let pane, let data)):
                await input(pane: pane, data: data)
            default:
                droppedFrameCount += 1
            }
        }
    }

    private func welcome(_ id: String, viewerNonce: Data, label: String) async {
        guard var circuit = circuits[id] else { return }
        cancelTimer(circuit.helloTimer)
        circuit.helloTimer = nil
        circuit.cipher.setViewerNonce(viewerNonce)
        circuits[id] = circuit
        guard !isExpired else {
            _ = await endCircuit(id, bye: .expired) // sealed under the welcome-stage AAD
            return
        }
        circuits[id]?.viewer = ShareViewer(id: id, label: String(label.prefix(Self.maxLabelCharacters)),
                                           connectedAt: clock())
        publishViewers()
        let source = self.source
        let (panes, active) = await MainActor.run { (source.panes, source.activePane) }
        guard circuits[id]?.serial == circuit.serial else { return }
        knownPanes = panes
        let activeID = active ?? panes.first?.id ?? ""
        let hostNonce = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        send(id, .welcome(nonce: hostNonce, perm: permission,
                          expiresAt: expiresAt.map { Int($0.timeIntervalSince1970) }, panes: panes, active: activeID))
        circuits[id]?.cipher.setHostNonce(hostNonce)
        // Live only after welcome, so a concurrent `panes` broadcast cannot precede it.
        circuits[id]?.stage = .live
        scheduleKeepalive(id)
        circuits[id]?.wantedPane = activeID
        await reselect(id)
    }

    /// A viewer's `select`: an unknown pane changes nothing; a known one becomes the wanted pane.
    private func viewerSelect(_ id: String, pane: String) async {
        let source = self.source
        let exists = await MainActor.run { source.panes.contains { $0.id == pane } }
        guard exists, circuits[id] != nil else { return }
        circuits[id]?.wantedPane = pane
        await reselect(id)
    }

    /// Streams the circuit's `wantedPane` (falling back to the active pane if it vanished) and sends
    /// its `replay`. The latest request wins: a select superseded while it waited is discarded.
    private func reselect(_ id: String) async {
        guard var circuit = circuits[id] else { return }
        circuit.selectRequest += 1
        let request = circuit.selectRequest
        let serial = circuit.serial
        let wanted = circuit.wantedPane ?? ""
        circuits[id] = circuit
        let pump = ShareOutputPump(limit: Self.maxBacklogBytes, interval: coalesceInterval) { [weak self] flush in
            await self?.deliver(id, serial, generation: request, flush)
        }
        if let selectHook { await selectHook(wanted) }
        let source = self.source
        let result = await MainActor.run {
            () -> (SharePane, (cols: Int, rows: Int, vt: Data)?, ShareSubscription?)? in
            let panes = source.panes
            guard let info = panes.first(where: { $0.id == wanted })
                ?? panes.first(where: { $0.id == source.activePane }) ?? panes.first else { return nil }
            guard info.kind == .terminal else { return (info, nil, nil) }
            let snapshot = source.snapshot(pane: info.id)
            let token = source.subscribe(pane: info.id) { pump.push($0) }
            return (info, snapshot, ShareSubscription(token: token, pump: pump))
        }
        guard var updated = circuits[id], updated.serial == serial, updated.selectRequest == request else {
            await result?.2?.release()
            pump.cancel()
            return
        }
        guard let (info, snapshot, subscription) = result else {
            updated.resyncPending = false // no pane left to replay
            circuits[id] = updated
            pump.cancel()
            return
        }
        let pane = info.id
        let old = updated.subscription
        updated.subscriptionGeneration = request
        updated.wantedPane = pane
        updated.pane = pane
        updated.subscription = subscription
        updated.pump = subscription == nil ? nil : pump
        updated.resyncPending = false
        updated.outEpoch += 1 // output of the previous pane still queued is now stale
        circuits[id] = updated
        if subscription == nil { pump.cancel() }
        let vt = snapshot?.vt ?? Data()
        send(id, .replay(pane: pane, cols: snapshot?.cols ?? info.cols, rows: snapshot?.rows ?? info.rows,
                         data: vt.prefix(Self.chunkBytes)))
        sendOut(id, pane: pane, vt.dropFirst(Self.chunkBytes), droppable: false)
        pump.resume() // only now, so nothing flushed before the replay is lost
        await old?.release()
    }

    private func deliver(_ id: String, _ serial: Int, generation: Int, _ flush: ShareOutputPump.Flush) {
        guard let circuit = circuits[id], circuit.serial == serial, circuit.subscriptionGeneration == generation,
              let pane = circuit.pane else { return }
        switch flush {
        case .data(let data): sendOut(id, pane: pane, data, droppable: true)
        case .overflow: resync(id)
        }
    }

    private func sendOut(_ id: String, pane: String, _ data: Data, droppable: Bool) {
        var offset = data.startIndex
        while offset < data.endIndex {
            guard let circuit = circuits[id] else { return }
            if droppable, circuit.resyncPending { return }
            let end = data.index(offset, offsetBy: Self.chunkBytes, limitedBy: data.endIndex) ?? data.endIndex
            guard let frame = seal(id, .out(pane: pane, data: Data(data[offset..<end]))) else { return }
            if droppable, circuit.queuedBytes + frame.count > Self.maxBacklogBytes {
                resync(id) // the sealed frame is discarded; the viewer tolerates the seq gap
                return
            }
            enqueue(id, Outgoing(message: .data(frame), bytes: frame.count, outEpoch: droppable ? circuit.outEpoch : nil))
            offset = end
        }
    }

    private func send(_ id: String, _ message: ShareMessage) {
        guard let frame = seal(id, message) else { return }
        enqueue(id, Outgoing(message: .data(frame), bytes: frame.count, outEpoch: nil))
    }

    private func seal(_ id: String, _ message: ShareMessage) -> Data? {
        guard var circuit = circuits[id], let frame = try? circuit.cipher.seal(message) else { return nil }
        circuit.lastSentAt = clock()
        circuits[id] = circuit
        return frame
    }

    private func enqueue(_ id: String, _ item: Outgoing) {
        guard var circuit = circuits[id] else { return }
        circuit.queuedBytes += item.bytes
        circuit.queuedItems += 1
        circuits[id] = circuit
        circuit.outbox.yield(item)
    }

    private func dequeued(_ id: String, _ serial: Int, bytes: Int) async {
        guard var circuit = circuits[id], circuit.serial == serial else { return }
        circuit.queuedBytes -= bytes
        circuit.queuedItems -= 1
        circuits[id] = circuit
        if circuit.resyncPending, circuit.queuedItems == 0 {
            await reselect(id) // drained: fresh replay, resubscribed
        }
    }

    /// Drop-to-replay: discards queued and buffered output; the replay follows once the writer drains.
    private func resync(_ id: String) {
        guard var circuit = circuits[id], !circuit.resyncPending else { return }
        let now = clock()
        circuit.resyncTimes = circuit.resyncTimes.filter { now.timeIntervalSince($0) < Self.resyncWindow } + [now]
        guard circuit.resyncTimes.count <= Self.maxResyncs else {
            circuit.socket.close() // hard ceiling: the reader/writer failure ends the circuit
            let serial = circuit.serial
            Task { await self.circuitFailed(id, serial) }
            return
        }
        circuit.resyncPending = true
        circuit.outEpoch += 1
        circuit.pump?.discard()
        circuits[id] = circuit
        if circuit.queuedItems == 0 {
            Task { await self.reselect(id) }
        }
    }

    private func scheduleKeepalive(_ id: String) {
        guard var circuit = circuits[id] else { return }
        cancelTimer(circuit.keepaliveTimer)
        // Never in the past: a skipped check (frames still queued) waits a full interval.
        let wait = circuit.queuedItems > 0 ? Self.keepaliveInterval : 0
        let deadline = max(circuit.lastSentAt + Self.keepaliveInterval, clock() + wait)
        circuit.keepaliveTimer = schedule(.keepalive(id, circuit.serial), at: deadline)
        circuits[id] = circuit
    }

    private func keepalive(_ id: String, serial: Int) {
        guard let circuit = circuits[id], circuit.serial == serial, circuit.stage == .live else { return }
        if circuit.queuedItems == 0, clock().timeIntervalSince(circuit.lastSentAt) >= Self.keepaliveInterval {
            send(id, .ka) // queued frames will carry traffic; no ka behind them
        }
        scheduleKeepalive(id)
    }

    private func input(pane: String, data: Data) async {
        guard permission == .type, !isExpired, data.count <= Self.maxInputBytes else { droppedInputCount += 1; return }
        let source = self.source
        let written = await MainActor.run { () -> Bool in
            guard source.panes.first(where: { $0.id == pane })?.kind == .terminal else { return false }
            source.input(pane: pane, data)
            return true
        }
        if !written { droppedInputCount += 1 }
    }

    /// Removes the circuit; with a reason, the viewer gets `bye` before the socket closes.
    private func endCircuit(_ id: String, bye: ShareByeReason?,
                            releaseSubscription: Bool = true) async -> (any ShareSocket, Task<Void, Never>)? {
        guard var circuit = circuits[id] else { return nil }
        if let bye, let frame = try? circuit.cipher.seal(.bye(bye)) {
            circuit.outbox.yield(Outgoing(message: .data(frame), bytes: frame.count, outEpoch: nil))
        }
        circuits[id] = nil
        circuit.outbox.finish()
        cancelTimer(circuit.helloTimer)
        cancelTimer(circuit.keepaliveTimer)
        if circuit.viewer != nil { publishViewers() }
        if releaseSubscription { await circuit.subscription?.release() }
        return (circuit.socket, circuit.writer)
    }

    private func publishViewers() { viewerContinuation.yield(viewers) }

    private func panesChanged() async {
        guard running else { return }
        let source = self.source
        let (panes, active) = await MainActor.run { (source.panes, source.activePane) }
        guard running else { return }
        let old = Dictionary(knownPanes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        knownPanes = panes
        let activeID = active ?? panes.first?.id ?? ""
        for (id, circuit) in circuits where circuit.stage == .live {
            send(id, .panes(panes, active: activeID))
            if let selected = circuit.pane, let now = panes.first(where: { $0.id == selected }) {
                if let before = old[selected], before.cols != now.cols || before.rows != now.rows {
                    send(id, .size(pane: selected, cols: now.cols, rows: now.rows))
                }
            } else if panes.contains(where: { $0.id == activeID }) {
                await reselect(id) // the selected pane closed: wanted pane, else the active one
            }
        }
    }
}

// MARK: - Output plumbing

/// Coalesces pane output: `push` only appends under a lock (safe on the libghostty IO thread) and
/// never holds more than `limit` bytes (past it, the buffer is discarded and `overflow` is
/// flushed instead). One consumer task, started paused until `resume()`, flushes at most every
/// `interval`, off the main actor.
final class ShareOutputPump: Sendable {
    enum Flush: Sendable, Equatable { case data(Data), overflow }

    private struct Buffer { var data = Data(); var overflowed = false }
    private let buffer = OSAllocatedUnfairLock(initialState: Buffer())
    private let limit: Int
    private let signal: AsyncStream<Void>.Continuation
    private let gate: AsyncStream<Void>.Continuation
    private let consumer: Task<Void, Never>

    init(limit: Int, interval: Duration, flush: @escaping @Sendable (Flush) async -> Void) {
        self.limit = limit
        let (signals, signal) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let (gates, gate) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        self.signal = signal
        self.gate = gate
        let buffer = self.buffer
        consumer = Task.detached {
            for await _ in gates { break }
            for await _ in signals {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { return }
                let taken = buffer.withLock { b -> Buffer in defer { b = Buffer() }; return b }
                if taken.overflowed {
                    await flush(.overflow)
                } else if !taken.data.isEmpty {
                    await flush(.data(taken.data))
                }
            }
        }
    }

    var bufferedBytes: Int { buffer.withLock { $0.data.count } }

    func push(_ data: Data) {
        let limit = self.limit
        buffer.withLock { b in
            if b.overflowed { return }
            if b.data.count + data.count > limit {
                b.data = Data()
                b.overflowed = true
            } else {
                b.data.append(data)
            }
        }
        signal.yield()
    }

    /// Drops buffered output (the host is resyncing).
    func discard() { buffer.withLock { $0 = Buffer() } }

    func resume() { gate.yield() }

    func cancel() {
        gate.finish()
        signal.finish()
        consumer.cancel()
    }
}

/// The source's subscription token, kept and dropped on the main actor.
@MainActor
final class ShareSubscription {
    private var token: AnyObject?
    private let pump: ShareOutputPump

    init(token: AnyObject, pump: ShareOutputPump) {
        self.token = token
        self.pump = pump
    }

    nonisolated func release() async {
        await MainActor.run {
            token = nil
            pump.cancel()
        }
    }
}
