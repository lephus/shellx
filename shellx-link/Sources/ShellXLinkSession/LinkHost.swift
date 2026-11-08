import Foundation
import ShellXLinkCore
import ShellXLinkRelay

/// The Mac (or PC) side of ShellX Link: serves the agent feed to trusted phones.
///
/// One `LinkHost` serves any number of circuits at once; each `serve` call is one session.
/// Session state lives in `serve`; the actor holds the configuration and a registry of the live sessions
/// (by authenticated client key) so that ``disconnect(clientKey:)`` can end them.
public actor LinkHost {
    private var live: [UUID: (clientKey: Data, circuit: WatchedCircuit)] = [:]

    private nonisolated let key: NoiseStaticKey
    private nonisolated let trustedClients: @Sendable () -> Set<Data>
    private nonisolated let feed: any AgentFeedSource
    private nonisolated let sessions: (any AgentSessionSource)?
    private nonisolated let chat: (any AgentChatSource)?
    private nonisolated let workspaces: (any WorkspaceSource)?
    private nonisolated let workspaceControl: (any WorkspaceControl)?
    private nonisolated let agentControl: (any AgentControl)?
    private nonisolated let terminalControl: (any TerminalControl)?
    private nonisolated let terminalCreator: (any TerminalCreator)?
    private nonisolated let hostVersion: String
    private nonisolated let machineName: String
    private nonisolated let timings: LinkTimings

    /// - Parameters:
    ///   - trustedClients: the paired phones' static public keys, read on every handshake.
    ///   - sessions: the agent session list; without it `agent.sessions.get` is answered `unsupported`.
    ///   - chat: transcripts and chat commands; without it every `chat.*` call is answered `unsupported`. When its
    ///     `acceptsAttachments` is true the host also offers the `attachments` feature and takes `attach.*` uploads
    ///     (kept in memory for the session, handed to `send(sessionId:text:attachments:)`); otherwise `attach.*` and a
    ///     `chat.send` with attachments are answered `unsupported`.
    ///   - workspaces: the workspace list; with it the host offers the `workspaces` feature, without it
    ///     `workspace.list.get` is answered `unsupported`.
    ///   - workspaceControl: creating, renaming and closing workspaces; with it the host offers the
    ///     `workspace_control` feature, without it `workspace.create`, `workspace.rename` and `workspace.close` are
    ///     answered `unsupported`.
    ///   - agentControl: closing an agent's terminal; with it the host offers the `agent_close` feature, without it
    ///     `agent.close` is answered `unsupported`.
    ///   - terminalControl: closing one terminal tab of a listed workspace; with it the host offers the
    ///     `terminal_close` feature, without it `terminal.close` is answered `unsupported`.
    ///   - terminalCreator: opening a terminal tab in a listed workspace; with it the host offers the
    ///     `terminal_create` feature, without it `terminal.create` is answered `unsupported`.
    public init(
        key: NoiseStaticKey, trustedClients: @escaping @Sendable () -> Set<Data>,
        feed: any AgentFeedSource, sessions: (any AgentSessionSource)? = nil, chat: (any AgentChatSource)? = nil,
        workspaces: (any WorkspaceSource)? = nil, workspaceControl: (any WorkspaceControl)? = nil,
        agentControl: (any AgentControl)? = nil, terminalControl: (any TerminalControl)? = nil,
        terminalCreator: (any TerminalCreator)? = nil,
        hostVersion: String, machineName: String
    ) {
        self.init(
            key: key, trustedClients: trustedClients, feed: feed, sessions: sessions, chat: chat,
            workspaces: workspaces, workspaceControl: workspaceControl, agentControl: agentControl,
            terminalControl: terminalControl, terminalCreator: terminalCreator, hostVersion: hostVersion,
            machineName: machineName, timings: .standard)
    }

    init(
        key: NoiseStaticKey, trustedClients: @escaping @Sendable () -> Set<Data>,
        feed: any AgentFeedSource, sessions: (any AgentSessionSource)?, chat: (any AgentChatSource)?,
        workspaces: (any WorkspaceSource)? = nil, workspaceControl: (any WorkspaceControl)? = nil,
        agentControl: (any AgentControl)? = nil, terminalControl: (any TerminalControl)? = nil,
        terminalCreator: (any TerminalCreator)? = nil,
        hostVersion: String, machineName: String, timings: LinkTimings
    ) {
        self.key = key
        self.trustedClients = trustedClients
        self.feed = feed
        self.sessions = sessions
        self.chat = chat
        self.workspaces = workspaces
        self.workspaceControl = workspaceControl
        self.agentControl = agentControl
        self.terminalControl = terminalControl
        self.terminalCreator = terminalCreator
        self.hostVersion = hostVersion
        self.machineName = machineName
        self.timings = timings
    }

    /// Runs one session on `circuit` and returns when it ends. The circuit is closed on return.
    ///
    /// Flow: Noise handshake (responder), `hello` -> `welcome`, then `agent.changed` pushes for
    /// every feed change and answers to `agent.snapshot.get`, `agent.reply`, `ping` and, with the
    /// sources, the session, chat, workspace and agent calls (`agent.sessions.get`, `chat.*`, `workspace.*`,
    /// `agent.close`, `terminal.close`), plus pushes
    /// for every session change, chat entry, transcript reset (`chat.reset`) and workspace change.
    /// Cancelling the calling task ends the session.
    public func serve(_ circuit: any RelayCircuit) async {
        await runSession(circuit)
    }

    /// Closes every live session authenticated with `clientKey`. A new handshake with that key is refused
    /// only once `trustedClients` no longer contains it, so untrust first.
    public func disconnect(clientKey: Data) async {
        let circuits = live.values.filter { $0.clientKey == clientKey }.map(\.circuit)
        for circuit in circuits { await circuit.close() }
    }

    private func register(_ id: UUID, clientKey: Data, circuit: WatchedCircuit) {
        live[id] = (clientKey, circuit)
    }

    private func unregister(_ id: UUID) {
        live[id] = nil
    }

    private nonisolated func runSession(_ circuit: any RelayCircuit) async {
        let watched = WatchedCircuit(circuit)
        let sessionID = UUID()
        await withDiscardingTaskGroup { group in
            group.addTask { await watched.watch(idleTimeout: self.timings.idleTimeout) }
            await self.converse(on: watched, sessionID: sessionID, group: &group)
            await self.unregister(sessionID)
            // Close first so that child tasks blocked on the circuit fail fast, then stop the rest.
            await watched.close()
            group.cancelAll()
        }
    }

    /// The session itself. Returns when the session must end.
    private nonisolated func converse(on circuit: WatchedCircuit, sessionID: UUID, group: inout DiscardingTaskGroup) async {
        let trustedClients = self.trustedClients
        let channel: SecureChannel
        do {
            channel = try await SecureChannel.open(
                circuit, role: .responder, key: key, trusts: { trustedClients().contains($0) })
        } catch {
            linkLog.info("host handshake failed: \(String(describing: error), privacy: .public)")
            return
        }
        // Registered so `disconnect` can end it. A key untrusted between the handshake and here is closed now.
        await register(sessionID, clientKey: channel.peerKey, circuit: circuit)
        guard trustedClients().contains(channel.peerKey) else {
            await circuit.close()
            return
        }

        // Pre-hello: the first frame must be `hello` (PROTOCOL.md section 7).
        let first: LinkMessage
        do {
            first = try await channel.receive()
        } catch LinkCodecError.wrongVersion {
            await Self.sendError(on: channel, "protocol_mismatch", "this host speaks ShellX Link protocol 1")
            return
        } catch is LinkCodecError {
            await Self.sendError(on: channel, "bad_request", "the first frame must be hello")
            return
        } catch {
            return
        }
        guard case .hello = first else {
            await Self.sendError(on: channel, "bad_request", "the first frame must be hello")
            return
        }

        // Subscribe before `welcome`, so no change after it is missed: the stream buffers until the
        // pusher starts. Leaving the scope without iterating it drops the subscription.
        let changes = feed.changes()
        let sessionChanges = sessions?.sessionChanges()
        let chatPushes = chat?.entries()
        let workspaceChanges = workspaces?.workspaceChanges()
        // Read once: what `welcome` offers is what this session enforces.
        let takesAttachments = chat?.acceptsAttachments == true
        var features: [String] = []
        if takesAttachments { features.append(ShellXLink.attachmentsFeature) }
        if workspaces != nil { features.append(ShellXLink.workspacesFeature) }
        if workspaceControl != nil { features.append(ShellXLink.workspaceControlFeature) }
        if agentControl != nil { features.append(ShellXLink.agentCloseFeature) }
        if terminalControl != nil { features.append(ShellXLink.terminalCloseFeature) }
        if terminalCreator != nil { features.append(ShellXLink.terminalCreateFeature) }
        do {
            try await channel.send(.welcome(
                protocolVersion: ShellXLink.protocolVersion, hostVersion: hostVersion, machineName: machineName,
                features: features))
        } catch {
            return
        }
        // Only now: nothing but `welcome` (or `error`) may precede establishment (PROTOCOL.md 7).
        // The subscription ends when the group cancels this task at the end of the session.
        group.addTask {
            for await change in changes {
                await Self.sendShrinking(on: channel, items: change.added) {
                    .changed(revision: change.revision, added: $0, resolved: change.resolved)
                }
            }
        }
        if let sessionChanges {
            group.addTask {
                for await change in sessionChanges {
                    await Self.deliver(
                        on: channel, frame: Self.shrunkSessions(change.upserted) {
                            .sessionsChanged(revision: change.revision, upserted: $0, removed: change.removed)
                        }, what: "agent.sessions.changed")
                }
            }
        }
        if let workspaceChanges {
            group.addTask {
                for await change in workspaceChanges {
                    await Self.deliver(
                        on: channel, frame: Self.shrunkWorkspaces(change.upserted) {
                            .workspacesChanged(revision: change.revision, upserted: $0, removed: change.removed)
                        }, what: "workspace.changed")
                }
            }
        }
        if let chatPushes {
            group.addTask {
                for await push in chatPushes {
                    switch push {
                    case let .upsert(sessionId, entries):
                        for frame in Self.entryFrames(sessionId: sessionId, entries: entries.map { $0.withTextCap() }) {
                            try? await channel.send(frame: frame)
                        }
                    case let .reset(sessionId):
                        // In order with the session's entries: what was pushed before belongs to the old
                        // transcript (PROTOCOL.md section 4, ChatEntry).
                        try? await channel.send(.chatReset(sessionId: sessionId))
                    }
                }
            }
        }
        let pingInterval = timings.pingInterval
        group.addTask { await runPings(on: channel, every: pingInterval) }

        // Established.
        let feed = self.feed
        let replyOrder = ReplyOrder()
        let sendOrder = ReplyOrder()
        let sessions = self.sessions
        let chat = self.chat
        let workspaces = self.workspaces
        let workspaceControl = self.workspaceControl
        let agentControl = self.agentControl
        let terminalControl = self.terminalControl
        let terminalCreator = self.terminalCreator
        // The uploads of this session: an id means nothing in another one, and they end with this scope.
        var uploads = AttachmentUploads(now: timings.now)
        while true {
            let message: LinkMessage
            do {
                message = try await channel.receive()
            } catch LinkCodecError.wrongVersion {
                await Self.sendError(on: channel, "protocol_mismatch", "this host speaks ShellX Link protocol 1")
                return
            } catch let LinkCodecError.badJSON(callId) {
                await Self.sendError(on: channel, "bad_request", "the frame could not be decoded", callId: callId)
                continue
            } catch is LinkCodecError {
                await Self.sendError(on: channel, "bad_request", "the frame could not be decoded")
                continue
            } catch {
                return
            }
            switch message {
            case let .snapshotGet(callId):
                // Answered in order, so snapshot replies follow the order of the requests.
                let snapshot = await feed.snapshot()
                await Self.sendShrinking(on: channel, items: snapshot.pending, answering: callId) {
                    .snapshot(callId: callId, revision: snapshot.revision, pending: $0)
                }
            case let .reply(callId, requestId, decision):
                // Resolving may wait on the agent hook; keep reading meanwhile. Replies to one
                // request run one after another in arrival order, so the first decision sent is the
                // one the feed takes and later ones answer `already_handled` (PROTOCOL.md section 5);
                // the client matches each result to its call by `call_id`. Replies to different
                // requests run concurrently.
                let turn = await replyOrder.reserve(requestId)
                group.addTask {
                    await replyOrder.wait(for: turn, of: requestId)
                    let outcome = await feed.reply(requestId: requestId, decision: decision)
                    try? await channel.send(.replyResult(callId: callId, requestId: requestId, outcome: outcome))
                    await replyOrder.finish(turn, of: requestId)
                }
            case let .sessionsGet(callId):
                guard let sessions else {
                    await Self.sendError(on: channel, "unsupported", "this host has no agent sessions", callId: callId)
                    continue
                }
                let list = await sessions.sessions()
                await Self.deliver(
                    on: channel, frame: Self.shrunkSessions(list.sessions) {
                        .sessions(callId: callId, revision: list.revision, sessions: $0)
                    }, what: "agent.sessions", answering: callId)
            case let .chatHistoryGet(callId, sessionId, beforeSeq, limit):
                guard let chat else {
                    await Self.sendError(on: channel, "unsupported", "this host has no chat", callId: callId)
                    continue
                }
                guard (1...Self.maxHistoryLimit).contains(limit) else {
                    await Self.sendError(
                        on: channel, "bad_request", "limit must be 1 to \(Self.maxHistoryLimit)", callId: callId)
                    continue
                }
                group.addTask {
                    guard let page = await chat.history(sessionId: sessionId, beforeSeq: beforeSeq, limit: limit) else {
                        await Self.sendError(on: channel, "not_found", "no such session", callId: callId)
                        return
                    }
                    await Self.deliver(
                        on: channel, frame: Self.fittedHistory(callId: callId, sessionId: sessionId,
                            page: (page.entries.map { $0.withTextCap() }, page.hasMore)),
                        what: "chat.history", answering: callId)
                }
            case let .chatSend(callId, sessionId, text, attachmentIds):
                guard let chat else {
                    await Self.sendError(on: channel, "unsupported", "this host has no chat", callId: callId)
                    continue
                }
                // Refused, not typed without them: a silent drop would lose what the user attached.
                if !attachmentIds.isEmpty, !takesAttachments {
                    await Self.sendError(on: channel, "unsupported", "this host takes no attachments", callId: callId)
                    continue
                }
                // A message of only attachments has no text (PROTOCOL.md section 4).
                let textBytes = attachmentIds.isEmpty ? 1...Self.maxSendTextBytes : 0...Self.maxSendTextBytes
                guard textBytes.contains(text.utf8.count) else {
                    await Self.sendError(
                        on: channel, "bad_request",
                        "text must be \(textBytes.lowerBound) to \(Self.maxSendTextBytes) bytes", callId: callId)
                    continue
                }
                // Taken before the chat source is called, so they are gone whatever the outcome; a message that
                // fails these checks takes none of them.
                let attachments: [ChatAttachment]
                do throws(AttachmentRefusal) {
                    attachments = try uploads.take(attachmentIds)
                } catch {
                    await Self.sendError(on: channel, error.code, error.message, callId: callId)
                    continue
                }
                // Typing into a session may wait on the agent; keep reading meanwhile. Sends to one
                // session run one after another in arrival order, as `agent.reply` does per request.
                let turn = await sendOrder.reserve(sessionId)
                group.addTask {
                    await sendOrder.wait(for: turn, of: sessionId)
                    let outcome = attachments.isEmpty
                        ? await chat.send(sessionId: sessionId, text: text)
                        : await chat.send(sessionId: sessionId, text: text, attachments: attachments)
                    try? await channel.send(.chatSendResult(callId: callId, outcome: outcome))
                    await sendOrder.finish(turn, of: sessionId)
                }
            case let .chatInterrupt(callId, sessionId, hard):
                guard let chat else {
                    await Self.sendError(on: channel, "unsupported", "this host has no chat", callId: callId)
                    continue
                }
                group.addTask {
                    let outcome = await chat.interrupt(sessionId: sessionId, hard: hard)
                    try? await channel.send(.chatInterruptResult(callId: callId, outcome: outcome))
                }
            case let .attachBegin(callId, _, _, _), let .attachChunk(callId, _, _, _), let .attachEnd(callId, _, _):
                // Without the feature every upload call is `unsupported`, so a phone never needs to try
                // (PROTOCOL.md section 5). Each step is quick: answered in the loop, in order.
                guard takesAttachments else {
                    await Self.sendError(on: channel, "unsupported", "this host takes no attachments", callId: callId)
                    continue
                }
                try? await channel.send(uploads.serve(message))
            case let .ping(nonce):
                try? await channel.send(.pong(nonce: nonce))
            case let .unknown(_, callId?):
                // A call of a later version (PROTOCOL.md section 3): answered at once, so the phone does not
                // wait out its timeout. One without a call_id is ignored below.
                await Self.sendError(on: channel, "unsupported", "this host does not know this call", callId: callId)
            case let .workspacesGet(callId):
                guard let workspaces else {
                    await Self.sendError(on: channel, "unsupported", "this host lists no workspaces", callId: callId)
                    continue
                }
                let list = await workspaces.workspaces()
                await Self.deliver(
                    on: channel, frame: Self.shrunkWorkspaces(list.workspaces) {
                        .workspaces(callId: callId, revision: list.revision, workspaces: $0)
                    }, what: "workspace.list", answering: callId)
            case let .workspaceCreate(callId):
                guard let workspaceControl else {
                    await Self.sendError(on: channel, "unsupported", "this host takes no workspace control", callId: callId)
                    continue
                }
                // Acting on the Mac may take a while; keep reading meanwhile.
                group.addTask {
                    let result = await workspaceControl.createWorkspace()
                    // The new id goes out only with `ok` (PROTOCOL.md section 4, Workspace).
                    let workspaceId = result.outcome == .ok ? result.workspaceId : nil
                    try? await channel.send(
                        .workspaceCreateResult(callId: callId, outcome: result.outcome, workspaceId: workspaceId))
                }
            case let .workspaceRename(callId, workspaceId, title):
                guard let workspaceControl else {
                    await Self.sendError(on: channel, "unsupported", "this host takes no workspace control", callId: callId)
                    continue
                }
                // Checked before the source is called, in bytes (PROTOCOL.md section 4, Workspace).
                guard title.utf8.count <= ShellXLink.maxWorkspaceTitleBytes else {
                    await Self.sendError(
                        on: channel, "bad_request", "title must be at most \(ShellXLink.maxWorkspaceTitleBytes) bytes",
                        callId: callId)
                    continue
                }
                group.addTask {
                    let outcome = await workspaceControl.renameWorkspace(workspaceId: workspaceId, title: title)
                    try? await channel.send(.workspaceRenameResult(callId: callId, outcome: outcome))
                }
            case let .workspaceClose(callId, workspaceId):
                guard let workspaceControl else {
                    await Self.sendError(on: channel, "unsupported", "this host takes no workspace control", callId: callId)
                    continue
                }
                group.addTask {
                    let outcome = await workspaceControl.closeWorkspace(workspaceId: workspaceId)
                    try? await channel.send(.workspaceCloseResult(callId: callId, outcome: outcome))
                }
            case let .agentClose(callId, sessionId):
                guard let agentControl else {
                    await Self.sendError(on: channel, "unsupported", "this host takes no agent control", callId: callId)
                    continue
                }
                // Closing a terminal may take a while; keep reading meanwhile.
                group.addTask {
                    let outcome = await agentControl.closeAgent(sessionId: sessionId)
                    try? await channel.send(.agentCloseResult(callId: callId, outcome: outcome))
                }
            case let .terminalClose(callId, workspaceId, terminalId):
                guard let terminalControl else {
                    await Self.sendError(
                        on: channel, "unsupported", "this host takes no terminal control", callId: callId)
                    continue
                }
                // Closing a terminal may take a while; keep reading meanwhile.
                group.addTask {
                    let outcome = await terminalControl.closeTerminal(workspaceId: workspaceId, terminalId: terminalId)
                    try? await channel.send(.terminalCloseResult(callId: callId, outcome: outcome))
                }
            case let .terminalViewOpen(callId, _, _, _):
                await Self.sendError(on: channel, "unsupported", "this host offers no terminal views", callId: callId)
            case let .terminalCreate(callId, workspaceId):
                guard let terminalCreator else {
                    await Self.sendError(on: channel, "unsupported", "this host takes no terminal creation", callId: callId)
                    continue
                }
                // Adding a tab may take a while; keep reading meanwhile.
                group.addTask {
                    let created = await terminalCreator.createTerminal(workspaceId: workspaceId)
                    // The new id goes out only with `ok`.
                    try? await channel.send(.terminalCreateResult(
                        callId: callId, outcome: created.outcome, terminalId: created.outcome == .ok ? created.terminalId : nil))
                }
            case .terminalViewInput, .terminalViewResize, .terminalViewResync, .terminalViewClose:
                break
            case .pong, .unknown, .error:
                break
            case .hello, .welcome, .changed, .sessionsChanged, .chatEntries, .chatReset, .workspacesChanged,
                 .terminalViewEnded, .terminalViewFrame:
                // Not allowed from a client once established: ignored, and answered (PROTOCOL.md 7).
                await Self.sendError(on: channel, "bad_request", "unexpected frame from a client")
            case let .snapshot(callId, _, _), let .replyResult(callId, _, _), let .sessions(callId, _, _),
                 let .chatHistory(callId, _, _, _), let .chatSendResult(callId, _), let .chatInterruptResult(callId, _),
                 let .attachReady(callId, _), let .attachChunkResult(callId, _, _), let .attachEndResult(callId, _),
                 let .workspaces(callId, _, _), let .workspaceCreateResult(callId, _, _),
                 let .workspaceRenameResult(callId, _), let .workspaceCloseResult(callId, _),
                 let .agentCloseResult(callId, _), let .terminalCloseResult(callId, _),
                 let .terminalViewOpenResult(callId, _), let .terminalCreateResult(callId, _, _):
                await Self.sendError(on: channel, "bad_request", "unexpected frame from a client", callId: callId)
            }
        }
    }

    private static func sendError(
        on channel: SecureChannel, _ code: String, _ message: String, callId: String? = nil
    ) async {
        try? await channel.send(.error(code: code, message: message, callId: callId))
    }

    /// Longest page a `chat.history.get` may ask for, and longest text a `chat.send` may carry (UTF-8 bytes).
    private static let maxHistoryLimit = 50
    private static let maxSendTextBytes = 16_384

    /// Sends `frame`, or when there is none (nothing fit, PROTOCOL.md section 6) answers call `callId`
    /// with `error` `too_large`; a push (no `callId`) is logged and dropped.
    private static func deliver(
        on channel: SecureChannel, frame: Data?, what: String, answering callId: String? = nil
    ) async {
        guard let frame else {
            linkLog.error("a \(what, privacy: .public) frame does not fit")
            if let callId {
                await sendError(on: channel, "too_large", "the answer does not fit in one frame", callId: callId)
            }
            return
        }
        try? await channel.send(frame: frame)
    }

    /// Sends a message built from `items`, shrinking previews when the frame is too large. When it still
    /// does not fit, an answer to call `callId` becomes `error` `too_large` with that id (PROTOCOL.md
    /// section 6); a push (no `callId`) is logged and dropped.
    private static func sendShrinking(
        on channel: SecureChannel, items: [PendingItem], answering callId: String? = nil,
        _ make: ([PendingItem]) -> LinkMessage
    ) async {
        guard let frame = shrunkFrame(items: items, make) else {
            linkLog.error("a frame does not fit even without previews (\(items.count) items)")
            if let callId {
                await sendError(on: channel, "too_large", "the answer does not fit in one frame", callId: callId)
            }
            return
        }
        try? await channel.send(frame: frame)
    }

    /// PROTOCOL.md section 6: the session list as is, else with every `title` dropped. Nil when none fits.
    static func shrunkSessions(_ sessions: [AgentSession], _ make: ([AgentSession]) -> LinkMessage) -> Data? {
        for dropTitles in [false, true] {
            do {
                return try LinkCodec.encode(make(dropTitles ? sessions.map { $0.withoutTitle() } : sessions))
            } catch LinkCodecError.frameTooLarge {
                continue
            } catch {
                linkLog.error("cannot encode a host frame: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
        return nil
    }

    /// PROTOCOL.md section 6: the workspace list as is, else with shrink steps 1 to 4 (`LinkWorkspace.shrunk(step:)`)
    /// applied to every workspace in turn, the first encoding that fits wins. Never a list with a workspace left out:
    /// nil when even step 4 does not fit.
    static func shrunkWorkspaces(_ workspaces: [LinkWorkspace], _ make: ([LinkWorkspace]) -> LinkMessage) -> Data? {
        for step in 0...4 {
            let list = step == 0 ? workspaces : workspaces.map { $0.shrunk(step: step) ?? $0 }
            do {
                return try LinkCodec.encode(make(list))
            } catch LinkCodecError.frameTooLarge {
                continue
            } catch {
                linkLog.error("cannot encode a host frame: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
        return nil
    }

    /// PROTOCOL.md section 6: a history page that does not fit loses its oldest whole `seq` group at a
    /// time (every entry sharing the smallest remaining `seq`), and `has_more` becomes true, so a client
    /// paging with `before_seq` never skips an entry. Nil when not even the newest group fits.
    static func fittedHistory(callId: String, sessionId: String, page: (entries: [ChatEntry], hasMore: Bool)) -> Data? {
        var entries = page.entries
        var hasMore = page.hasMore
        while true {
            let message = LinkMessage.chatHistory(
                callId: callId, sessionId: sessionId, entries: entries, hasMore: hasMore)
            do {
                return try LinkCodec.encode(message)
            } catch LinkCodecError.frameTooLarge {
                guard let oldest = entries.map(\.seq).min() else { return nil }
                let rest = entries.filter { $0.seq != oldest }
                guard !rest.isEmpty else { return nil }
                entries = rest
                hasMore = true
            } catch {
                linkLog.error("cannot encode a host frame: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }

    /// PROTOCOL.md section 6: `chat.entries` that do not fit are split into several frames, each complete
    /// by itself (entries are upserts). An entry that does not fit alone is logged and dropped.
    static func entryFrames(sessionId: String, entries: [ChatEntry]) -> [Data] {
        guard !entries.isEmpty else { return [] }
        do {
            return [try LinkCodec.encode(.chatEntries(sessionId: sessionId, entries: entries))]
        } catch LinkCodecError.frameTooLarge {
            guard entries.count > 1 else {
                linkLog.error("a chat entry does not fit in one frame")
                return []
            }
            let middle = entries.count / 2
            return entryFrames(sessionId: sessionId, entries: Array(entries[..<middle]))
                + entryFrames(sessionId: sessionId, entries: Array(entries[middle...]))
        } catch {
            linkLog.error("cannot encode a host frame: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// PROTOCOL.md section 6: previews cut to 8192 bytes, then 1024, then omitted; the first
    /// encoding that fits wins. Nil when none fits.
    static func shrunkFrame(items: [PendingItem], _ make: ([PendingItem]) -> LinkMessage) -> Data? {
        let limits: [Int?] = [PendingItem.maxPreviewBytes, 1024, nil]
        for limit in limits {
            do {
                return try LinkCodec.encode(make(items.map { $0.withPreviewLimit(limit) }))
            } catch LinkCodecError.frameTooLarge {
                continue
            } catch {
                linkLog.error("cannot encode a host frame: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
        return nil
    }
}

/// Per-id FIFO turns for one session's `agent.reply` handlers (id = `request_id`) and `chat.send`
/// handlers (id = `session_id`).
///
/// The receive loop reserves a turn when the frame arrives; the handler waits for that turn,
/// and finishing it (after its result was sent) lets the next reply for the same id run.
private actor ReplyOrder {
    /// The next turn to hand out, per id. Absent when no reply for that id is in flight.
    private var nextTurn: [String: Int] = [:]
    /// The turn that may run now, per id.
    private var current: [String: Int] = [:]
    private var waiting: [String: [Int: CheckedContinuation<Void, Never>]] = [:]

    func reserve(_ requestId: String) -> Int {
        let turn = nextTurn[requestId, default: 0]
        nextTurn[requestId] = turn + 1
        return turn
    }

    func wait(for turn: Int, of requestId: String) async {
        guard current[requestId, default: 0] != turn else { return }
        await withCheckedContinuation { waiting[requestId, default: [:]][turn] = $0 }
    }

    func finish(_ turn: Int, of requestId: String) {
        let following = turn + 1
        guard nextTurn[requestId] != following else {
            // Nothing else queued for this id.
            nextTurn[requestId] = nil
            current[requestId] = nil
            waiting[requestId] = nil
            return
        }
        current[requestId] = following
        if let next = waiting[requestId]?.removeValue(forKey: following) {
            next.resume()
        }
    }
}
