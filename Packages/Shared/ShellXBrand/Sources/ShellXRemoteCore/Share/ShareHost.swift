import Foundation
import os

/// The host side of one share link: registers the share's own slot on relay2 and serves one
/// encrypted circuit per viewer, enforcing the share's permission and expiry.
///
/// Control socket: `register` -> `registered`, `ping` every 10 s, a fresh socket and `register`
/// every 90 s (the old one is closed after the new `registered`), backoff 1/2/4/8/16/30 s on errors.
/// Circuit: `incoming` -> new socket -> `join(role: daemon)` -> `ready` -> wait <= 10 s for `hello`
/// (anything else is dropped) -> `welcome` + `replay` of the active pane -> `out`/`size` of the
/// viewer's selected pane only.
public actor ShareHost {
    static let pingInterval: TimeInterval = 10
    static let reRegisterInterval: TimeInterval = 90
    static let registerTimeout: TimeInterval = 10
    static let helloTimeout: TimeInterval = 10
    static let maxInputBytes = 4 * 1024
    static let maxLabelCharacters = 40
    /// Raw bytes per `out`/`replay` frame; base64 + JSON keeps the plaintext under 48 KiB.
    static let chunkBytes = 32 * 1024

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

    /// `in` frames refused: view-only share, unknown or non-terminal pane, or over 4 KiB.
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
    private var registerTimer: Int?
    private var pingTimer: Int?

    private enum Stage { case joining, awaitingHello, live }
    private struct Circuit {
        let socket: any ShareSocket
        let outbox: AsyncStream<ShareSocketMessage>.Continuation
        let writer: Task<Void, Never>
        var cipher: ShareCipher
        var stage = Stage.joining
        var helloTimer: Int?
        var viewer: ShareViewer?
        var pane: String?
        var subscription: ShareSubscription?
        var subscriptionGeneration = 0
    }
    private var circuits: [String: Circuit] = [:]
    private var knownPanes: [SharePane] = []

    private enum TimerAction: Sendable {
        case ping(Int), reRegister(Int), registerTimeout(Int), reconnect, helloTimeout(String), expiry
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
        guard !stopped else { return }
        stopped = true
        running = false
        for timer in timers.values { timer.cancel() }
        timers.removeAll()
        let source = self.source
        await MainActor.run { source.onPanesChanged = nil }
        var ending: [(any ShareSocket, Task<Void, Never>)] = []
        for id in Array(circuits.keys) {
            if let ended = await endCircuit(id, bye: reason) { ending.append(ended) }
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
        case .reRegister(let generation):
            if current?.generation == generation, connectingGeneration == nil { connectControl() }
        case .registerTimeout(let generation):
            if pending?.generation == generation { controlFailed(generation) }
        case .reconnect: connectControl()
        case .helloTimeout(let circuit):
            if circuits[circuit]?.stage != .live { _ = await endCircuit(circuit, bye: nil) }
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
            cancelTimer(registerTimer); registerTimer = nil
            old?.socket.close()
            cancelTimer(pingTimer)
            let now = clock()
            pingTimer = schedule(.ping(generation), at: now + Self.pingInterval)
            schedule(.reRegister(generation), at: now + Self.reRegisterInterval)
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
        pingTimer = schedule(.ping(generation), at: clock() + Self.pingInterval)
        do {
            try await control.socket.send(text: ShareRelayControl.ping(nonce: pingNonce).encoded())
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
        let (outbox, continuation) = AsyncStream.makeStream(of: ShareSocketMessage.self)
        let writer = Task {
            do {
                for await message in outbox {
                    switch message {
                    case .text(let text): try await socket.send(text: text)
                    case .data(let data): try await socket.send(data: data)
                    }
                }
            } catch {
                await self.circuitFailed(id, socket)
            }
            socket.close()
        }
        circuits[id] = Circuit(socket: socket, outbox: continuation, writer: writer,
                               cipher: ShareCipher(sendKey: keys.hostToViewer, receiveKey: keys.viewerToHost, circuit: id))
        continuation.yield(.text(join.encoded()))
        Task {
            do {
                while true { await self.handleCircuit(id, socket, try await socket.receive()) }
            } catch {
                await self.circuitFailed(id, socket)
            }
        }
    }

    private func isCurrent(_ id: String, _ socket: any ShareSocket) -> Bool {
        guard let circuit = circuits[id] else { return false }
        return circuit.socket as AnyObject === socket as AnyObject
    }

    private func circuitFailed(_ id: String, _ socket: any ShareSocket) async {
        if isCurrent(id, socket) { _ = await endCircuit(id, bye: nil) }
    }

    private func handleCircuit(_ id: String, _ socket: any ShareSocket, _ message: ShareSocketMessage) async {
        guard running, isCurrent(id, socket), var circuit = circuits[id] else { return }
        switch message {
        case .text(let text):
            if circuit.stage == .joining, case .ready = ShareRelayControl.decode(text) {
                circuit.stage = .awaitingHello
                circuit.helloTimer = schedule(.helloTimeout(id), at: clock() + Self.helloTimeout)
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
                await select(id, pane: pane)
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
        circuit.viewer = ShareViewer(id: id, label: String(label.prefix(Self.maxLabelCharacters)), connectedAt: clock())
        circuits[id] = circuit
        publishViewers()
        let source = self.source
        let (panes, active) = await MainActor.run { (source.panes, source.activePane) }
        guard circuits[id] != nil else { return }
        knownPanes = panes
        let activeID = active ?? panes.first?.id ?? ""
        let hostNonce = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        send(id, .welcome(nonce: hostNonce, perm: permission,
                          expiresAt: expiresAt.map { Int($0.timeIntervalSince1970) }, panes: panes, active: activeID))
        circuits[id]?.cipher.setHostNonce(hostNonce)
        // Live only after welcome, so a concurrent `panes` broadcast cannot precede it.
        circuits[id]?.stage = .live
        await select(id, pane: activeID)
    }

    /// Switches the circuit's stream to `pane` and sends its `replay`; unknown panes are ignored.
    private func select(_ id: String, pane: String) async {
        guard var circuit = circuits[id] else { return }
        circuit.subscriptionGeneration += 1
        let generation = circuit.subscriptionGeneration
        let old = circuit.subscription
        circuit.subscription = nil
        circuit.pane = nil
        circuits[id] = circuit
        await old?.release()

        let pump = ShareOutputPump(interval: coalesceInterval) { [weak self] data in
            await self?.deliver(id, generation: generation, data: data)
        }
        let source = self.source
        let result = await MainActor.run { () -> (SharePane, (cols: Int, rows: Int, vt: Data)?, ShareSubscription?)? in
            guard let info = source.panes.first(where: { $0.id == pane }) else { return nil }
            guard info.kind == .terminal else { return (info, nil, nil) }
            let snapshot = source.snapshot(pane: pane)
            let token = source.subscribe(pane: pane) { pump.push($0) }
            return (info, snapshot, ShareSubscription(token: token, pump: pump))
        }
        guard let (info, snapshot, subscription) = result else { pump.cancel(); return }
        guard circuits[id]?.subscriptionGeneration == generation else {
            await subscription?.release()
            return
        }
        circuits[id]?.pane = pane
        circuits[id]?.subscription = subscription
        if subscription == nil { pump.cancel() }
        let vt = snapshot?.vt ?? Data()
        send(id, .replay(pane: pane, cols: snapshot?.cols ?? info.cols, rows: snapshot?.rows ?? info.rows,
                         data: vt.prefix(Self.chunkBytes)))
        sendOut(id, pane: pane, vt.dropFirst(Self.chunkBytes))
    }

    private func deliver(_ id: String, generation: Int, data: Data) {
        guard let circuit = circuits[id], circuit.subscriptionGeneration == generation, let pane = circuit.pane else { return }
        sendOut(id, pane: pane, data)
    }

    private func sendOut(_ id: String, pane: String, _ data: Data) {
        var offset = data.startIndex
        while offset < data.endIndex {
            let end = data.index(offset, offsetBy: Self.chunkBytes, limitedBy: data.endIndex) ?? data.endIndex
            send(id, .out(pane: pane, data: Data(data[offset..<end])))
            offset = end
        }
    }

    private func send(_ id: String, _ message: ShareMessage) {
        guard var circuit = circuits[id], let frame = try? circuit.cipher.seal(message) else { return }
        circuits[id] = circuit
        circuit.outbox.yield(.data(frame))
    }

    private func input(pane: String, data: Data) async {
        guard permission == .type, data.count <= Self.maxInputBytes else { droppedInputCount += 1; return }
        let source = self.source
        let written = await MainActor.run { () -> Bool in
            guard source.panes.first(where: { $0.id == pane })?.kind == .terminal else { return false }
            source.input(pane: pane, data)
            return true
        }
        if !written { droppedInputCount += 1 }
    }

    /// Removes the circuit; with a reason, the viewer gets `bye` before the socket closes.
    private func endCircuit(_ id: String, bye: ShareByeReason?) async -> (any ShareSocket, Task<Void, Never>)? {
        guard var circuit = circuits[id] else { return nil }
        if let bye, let frame = try? circuit.cipher.seal(.bye(bye)) { circuit.outbox.yield(.data(frame)) }
        circuits[id] = nil
        circuit.outbox.finish()
        cancelTimer(circuit.helloTimer)
        if circuit.viewer != nil { publishViewers() }
        await circuit.subscription?.release()
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
                await select(id, pane: activeID) // the selected pane closed
            }
        }
    }
}

// MARK: - Output plumbing

/// Coalesces pane output: `push` only appends under a lock (safe on the libghostty IO thread);
/// one consumer task flushes at most every `interval`, off the main actor.
final class ShareOutputPump: Sendable {
    private let buffer = OSAllocatedUnfairLock(initialState: Data())
    private let signal: AsyncStream<Void>.Continuation
    private let consumer: Task<Void, Never>

    init(interval: Duration, flush: @escaping @Sendable (Data) async -> Void) {
        let (signals, signal) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        self.signal = signal
        let buffer = self.buffer
        consumer = Task.detached {
            for await _ in signals {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { return }
                let data = buffer.withLock { b -> Data in defer { b = Data() }; return b }
                if !data.isEmpty { await flush(data) }
            }
        }
    }

    func push(_ data: Data) {
        buffer.withLock { $0.append(data) }
        signal.yield()
    }

    func cancel() {
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

// MARK: - Ticket provider (moves to ShareTicketProvider.swift at merge)

public protocol ShareTicketProvider: Sendable {
    func hostTicket(shareID: String) async throws -> (ticket: String, relayURL: URL, expiresAt: Date)
}
