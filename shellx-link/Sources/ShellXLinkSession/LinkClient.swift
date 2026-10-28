import Foundation
import ShellXLinkCore
import ShellXLinkRelay

/// Failures of a `LinkClient` session.
public enum LinkClientError: Error, Equatable, Sendable {
    /// The host speaks another protocol version; the user should update the app (PROTOCOL.md 7).
    case protocolMismatch(message: String)
    /// The host answered `hello` with an `error`.
    case rejected(code: String, message: String)
    /// The session ended (closed by either side, or found dead) before an answer arrived.
    case sessionClosed
    /// No answer arrived within the request timeout (10 s by default). The session stays usable.
    case timedOut
    /// The host answered one specific call with an `error` (PROTOCOL.md section 7). `unsupported` means the host
    /// cannot serve this call: it has no source for it, or it predates the call's type (section 3).
    case remote(code: String, message: String)
    /// The host answered a call with a message of another type than the call expects. A fault of the
    /// host's, not an `error` it sent: callers that branch on `.remote` codes never see it.
    case unexpectedAnswer
}

/// The phone side of ShellX Link: one established session with one host.
public actor LinkClient {
    private typealias Change = (revision: Int, added: [PendingItem], resolved: [String])
    private typealias SessionChange = (revision: Int, upserted: [AgentSession], removed: [String])

    /// Every `agent.changed` from the host, in order. Single consumer. It finishes when the
    /// session ends.
    ///
    /// Each change carries the host's `revision`. Compared with the revision of the last change or
    /// snapshot the caller applied: at or below it, the caller already has the change and skips
    /// it; exactly one above, it applies it; further above, it missed one and must resync with
    /// `snapshot()` (PROTOCOL.md section 4).
    public nonisolated let changes: AsyncStream<(revision: Int, added: [PendingItem], resolved: [String])>

    /// Every `agent.sessions.changed` from the host, in order. Single consumer. It finishes when the
    /// session ends. The caller applies the revision rule of PROTOCOL.md section 4 against the
    /// revision of its last `sessions()` result or applied change, exactly as for `changes`.
    public nonisolated let sessionChanges: AsyncStream<(revision: Int, upserted: [AgentSession], removed: [String])>

    /// Every `chat.entries` and `chat.reset` push from the host, in the order they arrived. Single consumer. It
    /// finishes when the session ends.
    ///
    /// * `.upsert(sessionId, entries)`: upserts by `ChatEntry.id`, keeping the higher `rev`.
    /// * `.reset(sessionId)`: the session's transcript was replaced (PROTOCOL.md section 4, ChatEntry). Drop
    ///   every entry held for that session, drop the result of any `chatHistory` call for it that started
    ///   before the reset, and page again from the newest (`chatHistory(sessionId:beforeSeq: nil, limit:)`).
    ///   The `.upsert` pushes after it belong to the new transcript.
    ///
    /// `ChatPush.sessionId` and `ChatPush.entries` read both cases (`entries` is empty for a reset), so a
    /// consumer written for the earlier `(sessionId, entries)` element treats a reset as an empty upsert until
    /// it handles `.reset`.
    public nonisolated let chatEntries: AsyncStream<ChatPush>

    /// The optional capabilities the host listed in `welcome.features` (PROTOCOL.md section 4, Features). Use a
    /// capability only when it is here: for `ShellXLink.attachmentsFeature`, `uploadAttachment` and
    /// `chatSend(attachments:)`. A string this version does not know is kept, and ignored.
    public nonisolated let hostFeatures: Set<String>

    private let changesContinuation: AsyncStream<Change>.Continuation
    private let sessionChangesContinuation: AsyncStream<SessionChange>.Continuation
    private let chatEntriesContinuation: AsyncStream<ChatPush>.Continuation
    private let channel: SecureChannel
    private let pinger: Task<Void, Never>
    private let watchdog: Task<Void, Never>
    private var reader: Task<Void, Never>?
    private var nextCallNumber = 0
    private let requestTimeout: Duration
    /// The calls waiting for their answer, by `call_id` (PROTOCOL.md section 3). An answer whose
    /// `call_id` is not here (the call timed out or was cancelled) is dropped.
    private var waiters: [String: Waiter] = [:]
    private var endError: LinkClientError?
    /// The callers of ``uploadAttachment(kind:name:data:progress:)`` waiting for their turn, oldest first. An
    /// upload runs from `attach.begin` to its end with no other upload in between (the host drops an unfinished
    /// upload at every `attach.begin`), and this actor is reentrant at every `await`: hence a gate.
    private var uploadWaiters: [(ticket: Int, continuation: CheckedContinuation<Void, any Error>)] = []
    /// True while an upload holds the turn, from the moment it gets it until ``releaseUploadTurn()``.
    private var uploadBusy = false
    private var nextUploadTicket = 0

    /// How many uploads wait behind the one running. For tests.
    var uploadsWaiting: Int { uploadWaiters.count }

    /// One caller waiting for an answer, and the timer that fails it after `requestTimeout`.
    private struct Waiter {
        let continuation: CheckedContinuation<LinkMessage, any Error>
        let timer: Task<Void, Never>

        func resume(returning value: LinkMessage) {
            timer.cancel()
            continuation.resume(returning: value)
        }

        func resume(throwing error: any Error) {
            timer.cancel()
            continuation.resume(throwing: error)
        }
    }

    private init(channel: SecureChannel, hostFeatures: Set<String>, watchdog: Task<Void, Never>, timings: LinkTimings) {
        self.hostFeatures = hostFeatures
        let pingInterval = timings.pingInterval
        requestTimeout = timings.requestTimeout
        let (stream, continuation) = AsyncStream.makeStream(of: Change.self)
        changes = stream
        changesContinuation = continuation
        let (sessionStream, sessionContinuation) = AsyncStream.makeStream(of: SessionChange.self)
        sessionChanges = sessionStream
        sessionChangesContinuation = sessionContinuation
        let (chatStream, chatContinuation) = AsyncStream.makeStream(of: ChatPush.self)
        chatEntries = chatStream
        chatEntriesContinuation = chatContinuation
        self.channel = channel
        self.watchdog = watchdog
        pinger = Task { await runPings(on: channel, every: pingInterval) }
    }

    deinit {
        pinger.cancel()
        watchdog.cancel()
        changesContinuation.finish()
        sessionChangesContinuation.finish()
        chatEntriesContinuation.finish()
        let channel = self.channel
        Task { await channel.close() }
    }

    /// Runs the handshake (initiator, trusting only `hostKey`) and `hello` / `welcome`.
    ///
    /// Throws `NoiseError` when the host is not `hostKey`, `RelayError.closed` when the host drops
    /// the circuit (for example because it does not trust this phone), and `LinkClientError` when
    /// the host answers with an error. The circuit is closed on failure.
    public static func connect(
        _ circuit: any RelayCircuit, key: NoiseStaticKey, hostKey: Data,
        clientVersion: String, deviceName: String
    ) async throws -> LinkClient {
        try await connect(
            circuit, key: key, hostKey: hostKey, clientVersion: clientVersion, deviceName: deviceName,
            timings: .standard)
    }

    static func connect(
        _ circuit: any RelayCircuit, key: NoiseStaticKey, hostKey: Data,
        clientVersion: String, deviceName: String, timings: LinkTimings
    ) async throws -> LinkClient {
        let watched = WatchedCircuit(circuit)
        let idleTimeout = timings.idleTimeout
        let watchdog = Task { await watched.watch(idleTimeout: idleTimeout) }
        do {
            let channel = try await SecureChannel.open(
                watched, role: .initiator, key: key, trusts: { $0 == hostKey })
            try await channel.send(.hello(clientVersion: clientVersion, deviceName: deviceName))
            let features = try await awaitWelcome(on: channel)
            let client = LinkClient(channel: channel, hostFeatures: features, watchdog: watchdog, timings: timings)
            await client.startReading()
            return client
        } catch {
            watchdog.cancel()
            await watched.close()
            throw error
        }
    }

    /// Asks the host for the full pending set.
    ///
    /// Throws `LinkClientError.remote(code: "too_large", ...)` when the host could not fit the
    /// snapshot in one frame (PROTOCOL.md section 6), and `.timedOut` when no answer arrives within
    /// the request timeout (10 s); the session stays usable, and a snapshot that arrives late is
    /// dropped (its `call_id` is no longer awaited). Throws `.sessionClosed` when the session
    /// ends first.
    public func snapshot() async throws -> (revision: Int, pending: [PendingItem]) {
        let answer = try await call { .snapshotGet(callId: $0) }
        guard case let .snapshot(_, revision, pending) = answer else { throw LinkClientError.unexpectedAnswer }
        return (revision, pending)
    }

    /// Sends a decision. Safe to repeat: the host answers `already_handled` for a resolved request.
    ///
    /// Throws `LinkClientError.timedOut` when no result arrives within the request timeout (10 s);
    /// the decision may still have been delivered, and repeating it is safe. A result that arrives
    /// after its call timed out (or was cancelled) is dropped, never given to a newer call.
    /// Throws `.remote` when the host answers the call with an `error`, and `.sessionClosed` when
    /// the session ends first.
    public func reply(requestId: String, decision: LinkDecision) async throws -> ReplyOutcome {
        let answer = try await call { .reply(callId: $0, requestId: requestId, decision: decision) }
        guard case let .replyResult(_, _, outcome) = answer else { throw LinkClientError.unexpectedAnswer }
        return outcome
    }

    /// Asks the host for the full list of agent sessions.
    ///
    /// Throws `.remote(code: "unsupported", ...)` when the host has no session list,
    /// `.remote(code: "too_large", ...)` when it could not fit the list in one frame (PROTOCOL.md
    /// section 6), `.timedOut` after the request timeout, and `.sessionClosed` when the session ends first.
    public func sessions() async throws -> (revision: Int, sessions: [AgentSession]) {
        let answer = try await call { .sessionsGet(callId: $0) }
        guard case let .sessions(_, revision, sessions) = answer else { throw LinkClientError.unexpectedAnswer }
        return (revision, sessions)
    }

    /// A page of a session's transcript, oldest entry first: the newest `limit` (1 to 50) entries with
    /// `seq` below `beforeSeq`, or the newest entries when it is nil. `hasMore` tells whether older
    /// entries exist; the host sets it also when it dropped entries to fit the frame.
    ///
    /// Throws `.remote(code: "not_found", ...)` for an unknown session, `"unsupported"` when the
    /// host has no chat, and `"bad_request"` for a `limit` out of range.
    public func chatHistory(
        sessionId: String, beforeSeq: Int?, limit: Int
    ) async throws -> (entries: [ChatEntry], hasMore: Bool) {
        let answer = try await call {
            .chatHistoryGet(callId: $0, sessionId: sessionId, beforeSeq: beforeSeq, limit: limit)
        }
        guard case let .chatHistory(_, _, entries, hasMore) = answer else { throw LinkClientError.unexpectedAnswer }
        return (entries, hasMore)
    }

    /// Types `text` (0 to 16 384 UTF-8 bytes; at least 1 when `attachments` is empty) into a session, with the
    /// finished uploads named by `attachments` (up to 5 ids from ``uploadAttachment(kind:name:data:progress:)``,
    /// each used by one message only). Not safe to repeat: a timeout leaves it unknown whether the host
    /// delivered it. Errors as for `chatHistory`, except `"not_found"` comes as the outcome `.notFound`; also
    /// `.remote(code: "bad_request", ...)` for an id the host does not hold (it ended with its session, was used
    /// already, expired, was dropped by a later upload, or never finished) and `"unsupported"` for attachments to
    /// a host without the feature. The host removes the uploads of an accepted message whatever the outcome; a
    /// refused message uses none of them.
    public func chatSend(sessionId: String, text: String, attachments: [String] = []) async throws -> ChatSendOutcome {
        let answer = try await call {
            .chatSend(callId: $0, sessionId: sessionId, text: text, attachments: attachments)
        }
        guard case let .chatSendResult(_, outcome) = answer else { throw LinkClientError.unexpectedAnswer }
        return outcome
    }

    /// Uploads a photo or file to the host (PROTOCOL.md section 5, "Attachments") and returns the id to name in
    /// ``chatSend(sessionId:text:attachments:)``. Call it only when ``hostFeatures`` lists
    /// `ShellXLink.attachmentsFeature`.
    ///
    /// Sends `attach.begin`, then the bytes in chunks of `ShellXLink.maxAttachmentChunkBytes`, each after the
    /// result of the one before, then `attach.end` with the SHA-256 of `data`. `progress` gets the bytes sent so
    /// far after each chunk's result, so the last value is `data.count`. It runs on this actor: keep it quick.
    ///
    /// Each step is a call with the usual 10 s timeout. Throws `.remote(code: ...)` when the host refuses a
    /// step: `"too_large"` or `"bad_request"` for a size outside 1 to `ShellXLink.maxAttachmentBytes`,
    /// `"bad_request"` for a kind other than `.image` and `.file` or a sixth unsent upload, `"unsupported"`
    /// without the feature.
    ///
    /// Uploads of one client run one at a time, in the order they were called: a caller waits for the upload
    /// before it to finish or fail (the host drops an unfinished upload at the next `attach.begin`, so two at once
    /// would drop each other). A failed or cancelled upload needs no cleanup and gives up its turn; so does a caller
    /// cancelled while it waits. A finished upload waits for a `chat.send` for `ShellXLink.unsentUploadLifetime` (5 minutes) after its
    /// `attach.end`; later its id is `bad_request` and the attachment must be uploaded again.
    public func uploadAttachment(
        kind: AttachmentKind, name: String, data: Data, progress: @Sendable (Int) -> Void = { _ in }
    ) async throws -> String {
        try await acquireUploadTurn()
        defer { releaseUploadTurn() }
        let size = data.count
        let ready = try await call { .attachBegin(callId: $0, kind: kind, name: name, size: size) }
        guard case let .attachReady(_, attachmentId) = ready else { throw LinkClientError.unexpectedAnswer }
        var offset = 0
        while offset < size {
            let start = offset
            let end = min(start + ShellXLink.maxAttachmentChunkBytes, size)
            let chunk = Data(data[(data.startIndex + start)..<(data.startIndex + end)])
            let answer = try await call {
                .attachChunk(callId: $0, attachmentId: attachmentId, offset: start, data: chunk)
            }
            guard case let .attachChunkResult(_, id, received) = answer, id == attachmentId, received == end else {
                throw LinkClientError.unexpectedAnswer
            }
            offset = end
            progress(offset)
        }
        let digest = sha256Digest(of: data)
        let finished = try await call { .attachEnd(callId: $0, attachmentId: attachmentId, sha256: digest) }
        guard case let .attachEndResult(_, id) = finished, id == attachmentId else {
            throw LinkClientError.unexpectedAnswer
        }
        return attachmentId
    }

    /// Interrupts a session's current turn; `hard` asks for a stronger stop. Errors as for `chatSend`.
    public func chatInterrupt(sessionId: String, hard: Bool) async throws -> ChatInterruptOutcome {
        let answer = try await call { .chatInterrupt(callId: $0, sessionId: sessionId, hard: hard) }
        guard case let .chatInterruptResult(_, outcome) = answer else { throw LinkClientError.unexpectedAnswer }
        return outcome
    }

    /// Waits for the turn to upload. Throws `CancellationError` when the caller is cancelled first, and the session's
    /// end error when it ends first; either way the caller holds no turn.
    private func acquireUploadTurn() async throws {
        try checkOpen()
        guard uploadBusy else {
            uploadBusy = true
            return
        }
        let ticket = nextUploadTicket
        nextUploadTicket += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // This body and `leaveUploadQueue` both run on the actor, so a cancellation that came first is
                // seen here, and one that comes later finds the waiter queued.
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                uploadWaiters.append((ticket, continuation))
            }
        } onCancel: {
            Task { await self.leaveUploadQueue(ticket) }
        }
    }

    /// Hands the turn to the oldest waiter, or frees it. The turn passes directly, so `uploadBusy` stays true.
    private func releaseUploadTurn() {
        guard !uploadWaiters.isEmpty else {
            uploadBusy = false
            return
        }
        uploadWaiters.removeFirst().continuation.resume()
    }

    /// A waiter whose task was cancelled leaves the queue. One that already got the turn is not in it.
    private func leaveUploadQueue(_ ticket: Int) {
        guard let index = uploadWaiters.firstIndex(where: { $0.ticket == ticket }) else { return }
        uploadWaiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    /// Ends the session and closes the circuit. Pending calls throw `LinkClientError.sessionClosed`.
    public func close() async {
        await end(.sessionClosed)
    }

    // MARK: - Session

    /// Waits for `welcome`; returns the host's `features`.
    private static func awaitWelcome(on channel: SecureChannel) async throws -> Set<String> {
        while true {
            let message: LinkMessage
            do {
                message = try await channel.receive()
            } catch LinkCodecError.wrongVersion {
                throw LinkClientError.protocolMismatch(message: "the host sent another protocol version")
            } catch let error as LinkCodecError {
                linkLog.info("client dropped an undecodable frame: \(String(describing: error), privacy: .public)")
                continue
            }
            switch message {
            case let .welcome(protocolVersion, _, _, features):
                guard protocolVersion == ShellXLink.protocolVersion else {
                    throw LinkClientError.protocolMismatch(message: "the host speaks protocol \(protocolVersion)")
                }
                return Set(features)
            case let .error(code, text, _):
                if code == "protocol_mismatch" { throw LinkClientError.protocolMismatch(message: text) }
                throw LinkClientError.rejected(code: code, message: text)
            default:
                // Nothing else is allowed before `welcome`; ignored (PROTOCOL.md section 7).
                continue
            }
        }
    }

    private func startReading() {
        let channel = self.channel
        // Weak, so a client nobody holds any more ends its session (see deinit).
        reader = Task { [weak self] in
            while true {
                let result: Result<LinkMessage, any Error>
                do {
                    result = .success(try await channel.receive())
                } catch {
                    result = .failure(error)
                }
                guard let self else { return }
                guard await self.handle(result) else { return }
            }
        }
    }

    /// Applies one received frame. Returns false when the session is over.
    private func handle(_ result: Result<LinkMessage, any Error>) async -> Bool {
        let message: LinkMessage
        switch result {
        case let .success(received):
            message = received
        case .failure(LinkCodecError.wrongVersion):
            await end(.protocolMismatch(message: "the host sent another protocol version"))
            return false
        case let .failure(error as LinkCodecError):
            linkLog.info("client dropped an undecodable frame: \(String(describing: error), privacy: .public)")
            return true
        case .failure:
            await end(.sessionClosed)
            return false
        }
        switch message {
        case let .snapshot(callId, _, _), let .replyResult(callId, _, _), let .sessions(callId, _, _),
             let .chatHistory(callId, _, _, _), let .chatSendResult(callId, _), let .chatInterruptResult(callId, _),
             let .attachReady(callId, _), let .attachChunkResult(callId, _, _), let .attachEndResult(callId, _):
            // A late answer (its call timed out or was cancelled) finds no waiter and is dropped.
            waiters.removeValue(forKey: callId)?.resume(returning: message)
        case let .sessionsChanged(revision, upserted, removed):
            sessionChangesContinuation.yield((revision, upserted, removed))
        case let .chatEntries(sessionId, entries):
            chatEntriesContinuation.yield(.upsert(sessionId: sessionId, entries: entries))
        case let .chatReset(sessionId):
            chatEntriesContinuation.yield(.reset(sessionId: sessionId))
        case let .changed(revision, added, resolved):
            changesContinuation.yield((revision, added, resolved))
        case let .ping(nonce):
            try? await channel.send(.pong(nonce: nonce))
        case let .error(code, text, callId):
            if code == "protocol_mismatch" {
                await end(.protocolMismatch(message: text))
                return false
            }
            if let callId, let waiter = waiters.removeValue(forKey: callId) {
                waiter.resume(throwing: LinkClientError.remote(code: code, message: text))
                return true
            }
            linkLog.info("host reported error \(code, privacy: .public)")
        case .pong, .unknown, .hello, .welcome, .snapshotGet, .reply, .sessionsGet, .chatHistoryGet, .chatSend,
             .chatInterrupt, .attachBegin, .attachChunk, .attachEnd:
            break
        }
        return true
    }

    private func end(_ error: LinkClientError) async {
        guard endError == nil else { return }
        endError = error
        let pending = waiters
        waiters = [:]
        for waiter in pending.values { waiter.resume(throwing: error) }
        // Callers still waiting for an upload turn fail the same way; the one running fails on its call.
        let queued = uploadWaiters
        uploadWaiters = []
        for waiter in queued { waiter.continuation.resume(throwing: error) }
        changesContinuation.finish()
        sessionChangesContinuation.finish()
        chatEntriesContinuation.finish()
        pinger.cancel()
        watchdog.cancel()
        await channel.close()
    }

    private func checkOpen() throws {
        if let endError { throw endError }
        try Task.checkCancellation()
    }

    /// Sends the message `make` builds for a fresh `call_id` and waits for the one answer that carries
    /// that id (or an `error` that does). Generic over the message type: the answer is the raw
    /// `LinkMessage`, which the caller unpacks.
    func call(_ make: @Sendable (String) -> LinkMessage) async throws -> LinkMessage {
        try checkOpen()
        nextCallNumber += 1
        let callId = "c\(nextCallNumber)"
        let message = make(callId)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<LinkMessage, any Error>) in
                if let endError {
                    continuation.resume(throwing: endError)
                    return
                }
                waiters[callId] = Waiter(continuation: continuation, timer: startTimer(for: callId))
                Task { await self.transmit(message, forCall: callId) }
            }
        } onCancel: {
            Task { await self.failWaiter(callId, with: CancellationError()) }
        }
    }

    /// Sends a request whose answer `callId` waits for; the waiter fails if the send does.
    private func transmit(_ message: LinkMessage, forCall callId: String) async {
        do {
            try await channel.send(message)
        } catch {
            failWaiter(callId, with: LinkClientError.sessionClosed)
        }
    }

    /// Fails waiter `callId` after `requestTimeout`. Only the waiter times out: the reader keeps its
    /// pending `receive()`, because cancelling that would kill the circuit.
    private func startTimer(for callId: String) -> Task<Void, Never> {
        let timeout = requestTimeout
        return Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            await self?.failWaiter(callId, with: LinkClientError.timedOut)
        }
    }

    /// Removes waiter `callId` (if it is still waiting) and throws `error` to it.
    private func failWaiter(_ callId: String, with error: any Error) {
        waiters.removeValue(forKey: callId)?.resume(throwing: error)
    }
}
