import Foundation

public enum LinkCodecError: Error, Equatable, Sendable {
    case frameTooLarge
    /// `callId` is the frame's `call_id` when it could be read (valid, 1-64 bytes), so a host can echo it.
    case badJSON(callId: String?)
    case wrongVersion
    case cannotEncodeUnknown
}

/// JSON frame codec for ShellX Link v1: `{"v":1,"t":"<type>",...}` in UTF-8.
public enum LinkCodec {
    /// Noise max message (65535) minus the 16-byte tag; counts UTF-8 bytes of the JSON frame.
    public static let maxFrameBytes = 65_519
    /// Maximum UTF-8 bytes of a `call_id`.
    public static let maxCallIdBytes = 64

    private enum T {
        static let hello = "hello", welcome = "welcome", error = "error"
        static let snapshotGet = "agent.snapshot.get", snapshot = "agent.snapshot", changed = "agent.changed"
        static let reply = "agent.reply", replyResult = "agent.reply.result"
        static let ping = "ping", pong = "pong"
        static let sessionsGet = "agent.sessions.get", sessions = "agent.sessions"
        static let sessionsChanged = "agent.sessions.changed"
        static let chatHistoryGet = "chat.history.get", chatHistory = "chat.history", chatEntries = "chat.entries"
        static let chatReset = "chat.reset"
        static let chatSend = "chat.send", chatSendResult = "chat.send.result"
        static let chatInterrupt = "chat.interrupt", chatInterruptResult = "chat.interrupt.result"
        static let attachBegin = "attach.begin", attachReady = "attach.ready"
        static let attachChunk = "attach.chunk", attachChunkResult = "attach.chunk.result"
        static let attachEnd = "attach.end", attachEndResult = "attach.end.result"
        static let workspacesGet = "workspace.list.get", workspaces = "workspace.list"
        static let workspacesChanged = "workspace.changed"
        static let workspaceCreate = "workspace.create", workspaceCreateResult = "workspace.create.result"
        static let workspaceRename = "workspace.rename", workspaceRenameResult = "workspace.rename.result"
        static let workspaceClose = "workspace.close", workspaceCloseResult = "workspace.close.result"
        static let agentClose = "agent.close", agentCloseResult = "agent.close.result"
        static let terminalClose = "terminal.close", terminalCloseResult = "terminal.close.result"
        static let terminalViewOpen = "terminal.view.open", terminalViewOpenResult = "terminal.view.open.result"
        static let terminalViewInput = "terminal.view.input", terminalViewResize = "terminal.view.resize"
        static let terminalViewResync = "terminal.view.resync", terminalViewClose = "terminal.view.close"
        static let terminalViewEnded = "terminal.view.ended"
        static let terminalCreate = "terminal.create", terminalCreateResult = "terminal.create.result"
    }

    // Per-message bodies (keys are snake_case on the wire).
    private struct Empty: Codable {}
    private struct Hello: Codable { var clientVersion: String; var deviceName: String }
    /// `features` is omitted when empty (nil), and absent decodes to nil.
    private struct Welcome: Codable {
        var protocolVersion: Int; var hostVersion: String; var machineName: String; var features: [String]?
    }
    private struct Err: Codable { var code: String; var message: String; var callId: String? }
    private struct CallOnly: Codable { var callId: String }
    private struct Snapshot: Codable { var callId: String; var revision: Int; var pending: [PendingItem] }
    private struct Changed: Codable { var revision: Int; var added: [PendingItem]; var resolved: [String] }
    private struct Reply: Codable { var callId: String; var requestId: String; var decision: LinkDecision }
    private struct ReplyResult: Codable { var callId: String; var requestId: String; var outcome: ReplyOutcome }
    private struct Nonce: Codable { var nonce: UInt64 }
    private struct Sessions: Codable { var callId: String; var revision: Int; var sessions: [AgentSession] }
    private struct SessionsChanged: Codable { var revision: Int; var upserted: [AgentSession]; var removed: [String] }
    private struct HistoryGet: Codable { var callId: String; var sessionId: String; var beforeSeq: Int?; var limit: Int }
    private struct History: Codable { var callId: String; var sessionId: String; var entries: [ChatEntry]; var hasMore: Bool }
    private struct Entries: Codable { var sessionId: String; var entries: [ChatEntry] }
    private struct Reset: Codable { var sessionId: String }
    /// `attachments` is omitted when empty (nil), and absent decodes to nil.
    private struct Send: Codable { var callId: String; var sessionId: String; var text: String; var attachments: [String]? }
    private struct SendResult: Codable { var callId: String; var outcome: ChatSendOutcome }
    private struct Interrupt: Codable { var callId: String; var sessionId: String; var hard: Bool }
    private struct InterruptResult: Codable { var callId: String; var outcome: ChatInterruptOutcome }
    private struct AttachBegin: Codable { var callId: String; var kind: AttachmentKind; var name: String; var size: Int }
    /// `attach.ready` and `attach.end.result`.
    private struct AttachRef: Codable { var callId: String; var attachmentId: String }
    /// `data` is the base64 text, converted by `base64Bytes`.
    private struct AttachChunk: Codable { var callId: String; var attachmentId: String; var offset: Int; var data: String }
    private struct AttachChunkResult: Codable { var callId: String; var attachmentId: String; var received: Int }
    /// `sha256` is the hex text, converted by `hexDigest`.
    private struct AttachEnd: Codable { var callId: String; var attachmentId: String; var sha256: String }

    private struct WorkspaceList: Codable { var callId: String; var revision: Int; var workspaces: [LinkWorkspace] }
    private struct WorkspaceListChanged: Codable { var revision: Int; var upserted: [LinkWorkspace]; var removed: [String] }
    /// `workspace_id` is omitted when nil: the host sets it only when `outcome` is `ok`.
    private struct WorkspaceCreateResult: Codable {
        var callId: String; var outcome: WorkspaceControlOutcome; var workspaceId: String?
    }
    private struct WorkspaceRename: Codable { var callId: String; var workspaceId: String; var title: String }
    private struct WorkspaceClose: Codable { var callId: String; var workspaceId: String }
    private struct AgentClose: Codable { var callId: String; var sessionId: String }
    private struct TerminalClose: Codable { var callId: String; var workspaceId: String; var terminalId: String }
    /// `workspace.rename.result`, `workspace.close.result`, `agent.close.result` and `terminal.close.result`.
    private struct WorkspaceOutcome: Codable { var callId: String; var outcome: WorkspaceControlOutcome }

    private struct TerminalViewOpen: Codable { var callId: String; var terminalId: String; var cols: Int; var rows: Int }
    private struct TerminalViewOpenResult: Codable { var callId: String; var outcome: TerminalViewOpenOutcome }
    private struct TerminalViewInput: Codable { var terminalId: String; var units: [TerminalInputUnit] }
    private struct TerminalViewSize: Codable { var terminalId: String; var cols: Int; var rows: Int }
    /// `terminal.view.resync` and `terminal.view.close`.
    private struct TerminalRef: Codable { var terminalId: String }
    private struct TerminalViewEnded: Codable { var terminalId: String; var reason: TerminalViewEndReason }
    private struct TerminalCreate: Codable { var callId: String; var workspaceId: String }
    /// `terminal_id` is omitted when nil: the host sets it only when `outcome` is `ok`.
    private struct TerminalCreateResult: Codable {
        var callId: String; var outcome: WorkspaceControlOutcome; var terminalId: String?
    }

    private struct Envelope { var v: Int; var t: String }

    /// Strict envelope: `v` must be a JSON integer token (`1.0`, `1e0`, `"1"`, `true` are `badJSON`).
    private static func parseEnvelope(_ d: Data) throws -> Envelope {
        guard let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let vn = obj["v"] as? NSNumber, String(cString: vn.objCType) == "q",
              let t = obj["t"] as? String
        else { throw LinkCodecError.badJSON(callId: nil) }
        return Envelope(v: vn.intValue, t: t)
    }

    private static func validCallId(_ id: String) -> Bool {
        let n = id.utf8.count
        return n >= 1 && n <= maxCallIdBytes
    }

    /// The frame's `call_id`, when it is a valid one.
    private static func readCallId(_ d: Data) -> String? {
        guard let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let id = obj["call_id"] as? String, validCallId(id) else { return nil }
        return id
    }

    private struct Frame<Body: Encodable>: Encodable {
        var t: String
        var body: Body
        private enum Keys: String, CodingKey { case v, t }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(ShellXLink.protocolVersion, forKey: .v)
            try c.encode(t, forKey: .t)
            try body.encode(to: encoder)
        }
    }

    public static func encode(_ m: LinkMessage) throws -> Data {
        let data: Data
        do {
            switch m {
            case let .hello(cv, dn): data = try enc(T.hello, Hello(clientVersion: cv, deviceName: dn))
            case let .welcome(pv, hv, mn, features):
                data = try enc(T.welcome, Welcome(
                    protocolVersion: pv, hostVersion: hv, machineName: mn, features: features.isEmpty ? nil : features))
            case let .error(code, message, callId):
                if let callId { try requireValid(callId) }
                data = try enc(T.error, Err(code: code, message: message, callId: callId))
            case let .snapshotGet(callId):
                try requireValid(callId)
                data = try enc(T.snapshotGet, CallOnly(callId: callId))
            case let .snapshot(callId, r, p):
                try requireValid(callId)
                data = try enc(T.snapshot, Snapshot(callId: callId, revision: r, pending: p))
            case let .changed(r, a, res): data = try enc(T.changed, Changed(revision: r, added: a, resolved: res))
            case let .reply(callId, id, decision):
                try requireValid(callId)
                data = try enc(T.reply, Reply(callId: callId, requestId: id, decision: decision))
            case let .replyResult(callId, id, o):
                try requireValid(callId)
                data = try enc(T.replyResult, ReplyResult(callId: callId, requestId: id, outcome: o))
            case let .ping(n): data = try enc(T.ping, Nonce(nonce: n))
            case let .pong(n): data = try enc(T.pong, Nonce(nonce: n))
            case let .sessionsGet(callId):
                try requireValid(callId)
                data = try enc(T.sessionsGet, CallOnly(callId: callId))
            case let .sessions(callId, r, s):
                try requireValid(callId)
                data = try enc(T.sessions, Sessions(callId: callId, revision: r, sessions: s))
            case let .sessionsChanged(r, up, rem):
                data = try enc(T.sessionsChanged, SessionsChanged(revision: r, upserted: up, removed: rem))
            case let .chatHistoryGet(callId, sid, before, limit):
                try requireValid(callId)
                data = try enc(T.chatHistoryGet, HistoryGet(callId: callId, sessionId: sid, beforeSeq: before, limit: limit))
            case let .chatHistory(callId, sid, entries, more):
                try requireValid(callId)
                data = try enc(T.chatHistory, History(callId: callId, sessionId: sid, entries: entries, hasMore: more))
            case let .chatEntries(sid, entries): data = try enc(T.chatEntries, Entries(sessionId: sid, entries: entries))
            case let .chatReset(sid): data = try enc(T.chatReset, Reset(sessionId: sid))
            case let .chatSend(callId, sid, text, attachments):
                try requireValid(callId)
                data = try enc(T.chatSend, Send(
                    callId: callId, sessionId: sid, text: text, attachments: attachments.isEmpty ? nil : attachments))
            case let .chatSendResult(callId, outcome):
                try requireValid(callId)
                data = try enc(T.chatSendResult, SendResult(callId: callId, outcome: outcome))
            case let .chatInterrupt(callId, sid, hard):
                try requireValid(callId)
                data = try enc(T.chatInterrupt, Interrupt(callId: callId, sessionId: sid, hard: hard))
            case let .chatInterruptResult(callId, outcome):
                try requireValid(callId)
                data = try enc(T.chatInterruptResult, InterruptResult(callId: callId, outcome: outcome))
            case let .attachBegin(callId, kind, name, size):
                try requireValid(callId)
                data = try enc(T.attachBegin, AttachBegin(callId: callId, kind: kind, name: name, size: size))
            case let .attachReady(callId, attachmentId):
                try requireValid(callId)
                data = try enc(T.attachReady, AttachRef(callId: callId, attachmentId: attachmentId))
            case let .attachChunk(callId, attachmentId, offset, bytes):
                try requireValid(callId)
                data = try enc(T.attachChunk, AttachChunk(
                    callId: callId, attachmentId: attachmentId, offset: offset, data: bytes.base64EncodedString()))
            case let .attachChunkResult(callId, attachmentId, received):
                try requireValid(callId)
                data = try enc(T.attachChunkResult, AttachChunkResult(
                    callId: callId, attachmentId: attachmentId, received: received))
            case let .attachEnd(callId, attachmentId, sha256):
                try requireValid(callId)
                guard sha256.count == sha256Bytes else { throw LinkCodecError.badJSON(callId: nil) }
                data = try enc(T.attachEnd, AttachEnd(callId: callId, attachmentId: attachmentId, sha256: hexString(sha256)))
            case let .attachEndResult(callId, attachmentId):
                try requireValid(callId)
                data = try enc(T.attachEndResult, AttachRef(callId: callId, attachmentId: attachmentId))
            case let .workspacesGet(callId):
                try requireValid(callId)
                data = try enc(T.workspacesGet, CallOnly(callId: callId))
            case let .workspaces(callId, r, w):
                try requireValid(callId)
                data = try enc(T.workspaces, WorkspaceList(callId: callId, revision: r, workspaces: w))
            case let .workspacesChanged(r, up, rem):
                data = try enc(T.workspacesChanged, WorkspaceListChanged(revision: r, upserted: up, removed: rem))
            case let .workspaceCreate(callId):
                try requireValid(callId)
                data = try enc(T.workspaceCreate, CallOnly(callId: callId))
            case let .workspaceCreateResult(callId, outcome, workspaceId):
                try requireValid(callId)
                data = try enc(T.workspaceCreateResult, WorkspaceCreateResult(
                    callId: callId, outcome: outcome, workspaceId: workspaceId))
            case let .workspaceRename(callId, workspaceId, title):
                try requireValid(callId)
                data = try enc(T.workspaceRename, WorkspaceRename(callId: callId, workspaceId: workspaceId, title: title))
            case let .workspaceRenameResult(callId, outcome):
                try requireValid(callId)
                data = try enc(T.workspaceRenameResult, WorkspaceOutcome(callId: callId, outcome: outcome))
            case let .workspaceClose(callId, workspaceId):
                try requireValid(callId)
                data = try enc(T.workspaceClose, WorkspaceClose(callId: callId, workspaceId: workspaceId))
            case let .workspaceCloseResult(callId, outcome):
                try requireValid(callId)
                data = try enc(T.workspaceCloseResult, WorkspaceOutcome(callId: callId, outcome: outcome))
            case let .agentClose(callId, sessionId):
                try requireValid(callId)
                data = try enc(T.agentClose, AgentClose(callId: callId, sessionId: sessionId))
            case let .agentCloseResult(callId, outcome):
                try requireValid(callId)
                data = try enc(T.agentCloseResult, WorkspaceOutcome(callId: callId, outcome: outcome))
            case let .terminalClose(callId, workspaceId, terminalId):
                try requireValid(callId)
                data = try enc(
                    T.terminalClose, TerminalClose(callId: callId, workspaceId: workspaceId, terminalId: terminalId))
            case let .terminalCloseResult(callId, outcome):
                try requireValid(callId)
                data = try enc(T.terminalCloseResult, WorkspaceOutcome(callId: callId, outcome: outcome))
            case let .terminalViewOpen(callId, terminalId, cols, rows):
                try requireValid(callId)
                data = try enc(T.terminalViewOpen, TerminalViewOpen(callId: callId, terminalId: terminalId, cols: cols, rows: rows))
            case let .terminalViewOpenResult(callId, outcome):
                try requireValid(callId)
                data = try enc(T.terminalViewOpenResult, TerminalViewOpenResult(callId: callId, outcome: outcome))
            case let .terminalViewInput(terminalId, units):
                data = try enc(T.terminalViewInput, TerminalViewInput(terminalId: terminalId, units: units))
            case let .terminalViewResize(terminalId, cols, rows):
                data = try enc(T.terminalViewResize, TerminalViewSize(terminalId: terminalId, cols: cols, rows: rows))
            case let .terminalViewResync(terminalId): data = try enc(T.terminalViewResync, TerminalRef(terminalId: terminalId))
            case let .terminalViewClose(terminalId): data = try enc(T.terminalViewClose, TerminalRef(terminalId: terminalId))
            case let .terminalViewEnded(terminalId, reason):
                data = try enc(T.terminalViewEnded, TerminalViewEnded(terminalId: terminalId, reason: reason))
            case let .terminalCreate(callId, workspaceId):
                try requireValid(callId)
                data = try enc(T.terminalCreate, TerminalCreate(callId: callId, workspaceId: workspaceId))
            case let .terminalCreateResult(callId, outcome, terminalId):
                try requireValid(callId)
                data = try enc(T.terminalCreateResult, TerminalCreateResult(callId: callId, outcome: outcome, terminalId: terminalId))
            case .unknown: throw LinkCodecError.cannotEncodeUnknown
            }
        } catch let e as LinkCodecError {
            throw e
        } catch {
            throw LinkCodecError.badJSON(callId: nil)
        }
        guard data.count <= maxFrameBytes else { throw LinkCodecError.frameTooLarge }
        return data
    }

    public static func decode(_ d: Data) throws -> LinkMessage {
        guard d.count <= maxFrameBytes else { throw LinkCodecError.frameTooLarge }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let env = try parseEnvelope(d)
        guard env.v == ShellXLink.protocolVersion else { throw LinkCodecError.wrongVersion }
        func body<B: Decodable>(_ type: B.Type) throws -> B {
            do { return try decoder.decode(type, from: d) } catch { throw LinkCodecError.badJSON(callId: readCallId(d)) }
        }
        /// A `call_id` that is present must also be 1-64 bytes; a frame with a bad one is `bad_json`
        /// without a callId to echo.
        func call<B: Decodable>(_ type: B.Type, _ id: KeyPath<B, String>) throws -> B {
            let b = try body(type)
            guard validCallId(b[keyPath: id]) else { throw LinkCodecError.badJSON(callId: nil) }
            return b
        }
        switch env.t {
        case T.hello: let b = try body(Hello.self); return .hello(clientVersion: b.clientVersion, deviceName: b.deviceName)
        case T.welcome:
            let b = try body(Welcome.self)
            return .welcome(
                protocolVersion: b.protocolVersion, hostVersion: b.hostVersion, machineName: b.machineName,
                features: b.features ?? [])
        case T.error:
            let b = try body(Err.self)
            if let id = b.callId, !validCallId(id) { throw LinkCodecError.badJSON(callId: nil) }
            return .error(code: b.code, message: b.message, callId: b.callId)
        case T.snapshotGet: return .snapshotGet(callId: try call(CallOnly.self, \.callId).callId)
        case T.snapshot:
            let b = try call(Snapshot.self, \.callId)
            return .snapshot(callId: b.callId, revision: b.revision, pending: b.pending)
        case T.changed:
            let b = try body(Changed.self)
            return .changed(revision: b.revision, added: b.added, resolved: b.resolved)
        case T.reply:
            let b = try call(Reply.self, \.callId)
            return .reply(callId: b.callId, requestId: b.requestId, decision: b.decision)
        case T.replyResult:
            let b = try call(ReplyResult.self, \.callId)
            return .replyResult(callId: b.callId, requestId: b.requestId, outcome: b.outcome)
        case T.ping: return .ping(nonce: try body(Nonce.self).nonce)
        case T.pong: return .pong(nonce: try body(Nonce.self).nonce)
        case T.sessionsGet: return .sessionsGet(callId: try call(CallOnly.self, \.callId).callId)
        case T.sessions:
            let b = try call(Sessions.self, \.callId)
            return .sessions(callId: b.callId, revision: b.revision, sessions: b.sessions)
        case T.sessionsChanged:
            let b = try body(SessionsChanged.self)
            return .sessionsChanged(revision: b.revision, upserted: b.upserted, removed: b.removed)
        case T.chatHistoryGet:
            let b = try call(HistoryGet.self, \.callId)
            return .chatHistoryGet(callId: b.callId, sessionId: b.sessionId, beforeSeq: b.beforeSeq, limit: b.limit)
        case T.chatHistory:
            let b = try call(History.self, \.callId)
            return .chatHistory(callId: b.callId, sessionId: b.sessionId, entries: b.entries, hasMore: b.hasMore)
        case T.chatEntries:
            let b = try body(Entries.self)
            return .chatEntries(sessionId: b.sessionId, entries: b.entries)
        case T.chatReset: return .chatReset(sessionId: try body(Reset.self).sessionId)
        case T.chatSend:
            let b = try call(Send.self, \.callId)
            return .chatSend(callId: b.callId, sessionId: b.sessionId, text: b.text, attachments: b.attachments ?? [])
        case T.chatSendResult:
            let b = try call(SendResult.self, \.callId)
            return .chatSendResult(callId: b.callId, outcome: b.outcome)
        case T.chatInterrupt:
            let b = try call(Interrupt.self, \.callId)
            return .chatInterrupt(callId: b.callId, sessionId: b.sessionId, hard: b.hard)
        case T.chatInterruptResult:
            let b = try call(InterruptResult.self, \.callId)
            return .chatInterruptResult(callId: b.callId, outcome: b.outcome)
        case T.attachBegin:
            let b = try call(AttachBegin.self, \.callId)
            return .attachBegin(callId: b.callId, kind: b.kind, name: b.name, size: b.size)
        case T.attachReady:
            let b = try call(AttachRef.self, \.callId)
            return .attachReady(callId: b.callId, attachmentId: b.attachmentId)
        case T.attachChunk:
            let b = try call(AttachChunk.self, \.callId)
            guard let bytes = base64Bytes(b.data) else { throw LinkCodecError.badJSON(callId: b.callId) }
            return .attachChunk(callId: b.callId, attachmentId: b.attachmentId, offset: b.offset, data: bytes)
        case T.attachChunkResult:
            let b = try call(AttachChunkResult.self, \.callId)
            return .attachChunkResult(callId: b.callId, attachmentId: b.attachmentId, received: b.received)
        case T.attachEnd:
            let b = try call(AttachEnd.self, \.callId)
            guard let digest = hexDigest(b.sha256) else { throw LinkCodecError.badJSON(callId: b.callId) }
            return .attachEnd(callId: b.callId, attachmentId: b.attachmentId, sha256: digest)
        case T.attachEndResult:
            let b = try call(AttachRef.self, \.callId)
            return .attachEndResult(callId: b.callId, attachmentId: b.attachmentId)
        case T.workspacesGet: return .workspacesGet(callId: try call(CallOnly.self, \.callId).callId)
        case T.workspaces:
            let b = try call(WorkspaceList.self, \.callId)
            return .workspaces(callId: b.callId, revision: b.revision, workspaces: b.workspaces)
        case T.workspacesChanged:
            let b = try body(WorkspaceListChanged.self)
            return .workspacesChanged(revision: b.revision, upserted: b.upserted, removed: b.removed)
        case T.workspaceCreate: return .workspaceCreate(callId: try call(CallOnly.self, \.callId).callId)
        case T.workspaceCreateResult:
            let b = try call(WorkspaceCreateResult.self, \.callId)
            return .workspaceCreateResult(callId: b.callId, outcome: b.outcome, workspaceId: b.workspaceId)
        case T.workspaceRename:
            let b = try call(WorkspaceRename.self, \.callId)
            return .workspaceRename(callId: b.callId, workspaceId: b.workspaceId, title: b.title)
        case T.workspaceRenameResult:
            let b = try call(WorkspaceOutcome.self, \.callId)
            return .workspaceRenameResult(callId: b.callId, outcome: b.outcome)
        case T.workspaceClose:
            let b = try call(WorkspaceClose.self, \.callId)
            return .workspaceClose(callId: b.callId, workspaceId: b.workspaceId)
        case T.workspaceCloseResult:
            let b = try call(WorkspaceOutcome.self, \.callId)
            return .workspaceCloseResult(callId: b.callId, outcome: b.outcome)
        case T.agentClose:
            let b = try call(AgentClose.self, \.callId)
            return .agentClose(callId: b.callId, sessionId: b.sessionId)
        case T.agentCloseResult:
            let b = try call(WorkspaceOutcome.self, \.callId)
            return .agentCloseResult(callId: b.callId, outcome: b.outcome)
        case T.terminalClose:
            let b = try call(TerminalClose.self, \.callId)
            return .terminalClose(callId: b.callId, workspaceId: b.workspaceId, terminalId: b.terminalId)
        case T.terminalCloseResult:
            let b = try call(WorkspaceOutcome.self, \.callId)
            return .terminalCloseResult(callId: b.callId, outcome: b.outcome)
        case T.terminalViewOpen:
            let b = try call(TerminalViewOpen.self, \.callId)
            return .terminalViewOpen(callId: b.callId, terminalId: b.terminalId, cols: b.cols, rows: b.rows)
        case T.terminalViewOpenResult:
            let b = try call(TerminalViewOpenResult.self, \.callId)
            return .terminalViewOpenResult(callId: b.callId, outcome: b.outcome)
        case T.terminalViewInput:
            let b = try body(TerminalViewInput.self)
            return .terminalViewInput(terminalId: b.terminalId, units: b.units)
        case T.terminalViewResize:
            let b = try body(TerminalViewSize.self)
            return .terminalViewResize(terminalId: b.terminalId, cols: b.cols, rows: b.rows)
        case T.terminalViewResync: return .terminalViewResync(terminalId: try body(TerminalRef.self).terminalId)
        case T.terminalViewClose: return .terminalViewClose(terminalId: try body(TerminalRef.self).terminalId)
        case T.terminalViewEnded:
            let b = try body(TerminalViewEnded.self)
            return .terminalViewEnded(terminalId: b.terminalId, reason: b.reason)
        case T.terminalCreate:
            let b = try call(TerminalCreate.self, \.callId)
            return .terminalCreate(callId: b.callId, workspaceId: b.workspaceId)
        case T.terminalCreateResult:
            let b = try call(TerminalCreateResult.self, \.callId)
            return .terminalCreateResult(callId: b.callId, outcome: b.outcome, terminalId: b.terminalId)
        default: return .unknown(type: env.t, callId: readCallId(d))
        }
    }

    /// Length of a SHA-256 digest, in bytes.
    private static let sha256Bytes = 32

    /// Standard base64 (RFC 4648 section 4) with padding, no line breaks and no other characters. Foundation
    /// alone accepts more (missing padding, whitespace), so the text must also be what encoding the bytes gives.
    private static func base64Bytes(_ text: String) -> Data? {
        guard let bytes = Data(base64Encoded: text), bytes.base64EncodedString() == text else { return nil }
        return bytes
    }

    private static let hexDigits = Array("0123456789abcdef".utf8)

    private static func hexString(_ bytes: Data) -> String {
        var out = [UInt8]()
        out.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            out.append(hexDigits[Int(byte >> 4)])
            out.append(hexDigits[Int(byte & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// 64 lowercase hex characters (0-9, a-f) to 32 bytes; anything else is nil.
    private static func hexDigest(_ text: String) -> Data? {
        let chars = Array(text.utf8)
        guard chars.count == sha256Bytes * 2 else { return nil }
        func nibble(_ c: UInt8) -> UInt8? {
            switch c {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
            default: return nil
            }
        }
        var out = Data()
        out.reserveCapacity(sha256Bytes)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let high = nibble(chars[i]), let low = nibble(chars[i + 1]) else { return nil }
            out.append(high << 4 | low)
        }
        return out
    }

    private static func requireValid(_ callId: String) throws {
        guard validCallId(callId) else { throw LinkCodecError.badJSON(callId: nil) }
    }

    private static func enc<B: Encodable>(_ t: String, _ body: B) throws -> Data {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try e.encode(Frame(t: t, body: body))
    }
}
