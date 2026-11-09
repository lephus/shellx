package com.shellx.link.core

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonUnquotedLiteral
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Why a frame could not be encoded or decoded. */
sealed class LinkCodecException(message: String) : Exception(message) {
    /** The frame is over [LinkCodec.MAX_FRAME_BYTES] UTF-8 bytes. */
    class FrameTooLarge : LinkCodecException("frame_too_large")

    /** Not a valid frame. `callId` is the frame's `call_id` when it is a valid one, so a host can echo it. */
    data class BadJson(val callId: String?) : LinkCodecException("bad_json")

    /** A well-formed integer `v` other than 1. */
    class WrongVersion : LinkCodecException("wrong_version")

    /** [LinkMessage.Unknown] is decode-only. */
    class CannotEncodeUnknown : LinkCodecException("cannot_encode_unknown")
}

/** JSON frame codec for ShellX Link v1: `{"v":1,"t":"<type>",...}` in UTF-8 (PROTOCOL.md section 3). */
object LinkCodec {
    /** Noise max message (65 535) minus the 16-byte tag; counts UTF-8 bytes of the JSON frame. */
    const val MAX_FRAME_BYTES = 65_519

    /** Maximum UTF-8 bytes of a `call_id`. */
    const val MAX_CALL_ID_BYTES = 64

    private const val SHA256_BYTES = 32

    /** The frame of [message]. Throws [LinkCodecException]. */
    fun encode(message: LinkMessage): ByteArray {
        val frame = Json.encodeToString(JsonObject.serializer(), toJson(message)).encodeToByteArray()
        if (frame.size > MAX_FRAME_BYTES) throw LinkCodecException.FrameTooLarge()
        return frame
    }

    /** The message in [frame]. Throws [LinkCodecException]; an unknown `t` is [LinkMessage.Unknown]. */
    fun decode(frame: ByteArray): LinkMessage {
        if (frame.size > MAX_FRAME_BYTES) throw LinkCodecException.FrameTooLarge()
        val o = parseJsonOrNull(frame) as? JsonObject ?: throw LinkCodecException.BadJson(null)
        val t = (o["t"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: throw LinkCodecException.BadJson(null)
        val v = o["v"]
        if (v == null || !v.isIntegerToken()) throw LinkCodecException.BadJson(null)
        if ((v as JsonPrimitive).content != ShellXLink.PROTOCOL_VERSION.toString()) throw LinkCodecException.WrongVersion()
        return try {
            fromJson(t, o) ?: LinkMessage.Unknown(t, validCallIdOrNull(o["call_id"]))
        } catch (_: FieldError) {
            throw LinkCodecException.BadJson(validCallIdOrNull(o["call_id"]))
        }
    }

    // Encoding

    private fun requireCallId(id: String) {
        if (!isValidCallId(id)) throw LinkCodecException.BadJson(null)
    }

    private fun frame(t: String, callId: String? = null, body: JsonObjectBuilder.() -> Unit = {}): JsonObject {
        if (callId != null) requireCallId(callId)
        return buildJsonObject {
            put("v", ShellXLink.PROTOCOL_VERSION)
            put("t", t)
            if (callId != null) put("call_id", callId)
            body()
        }
    }

    private fun JsonObjectBuilder.putOpt(key: String, value: String?) {
        if (value != null) put(key, value)
    }

    private fun JsonObjectBuilder.putOpt(key: String, value: Long?) {
        if (value != null) put(key, value)
    }

    private fun JsonObjectBuilder.putOpt(key: String, value: Boolean?) {
        if (value != null) put(key, value)
    }

    private fun strings(values: List<String>): JsonArray = buildJsonArray { values.forEach { add(JsonPrimitive(it)) } }

    private fun <T> list(values: List<T>, item: (T) -> JsonElement): JsonArray = buildJsonArray { values.forEach { add(item(it)) } }

    @OptIn(ExperimentalSerializationApi::class)
    private fun uint64(value: ULong): JsonElement = JsonUnquotedLiteral(value.toString())

    private fun pending(p: PendingItem): JsonObject = buildJsonObject {
        put("request_id", p.requestId)
        put("kind", p.kind.wire)
        put("agent", p.agent)
        put("workspace_id", p.workspaceId)
        put("workspace_title", p.workspaceTitle)
        putOpt("tool_name", p.toolName)
        putOpt("tool_input_preview", p.toolInputPreview)
        put("created_at_ms", p.createdAtMs)
        put("modes", strings(p.modes))
        p.questions?.let { put("questions", list(it, ::question)) }
        putOpt("plan_preview", p.planPreview)
    }

    private fun question(q: PendingQuestion): JsonObject = buildJsonObject {
        put("id", q.id)
        putOpt("header", q.header)
        put("prompt", q.prompt)
        put("multi_select", q.multiSelect)
        put("options", list(q.options) { o ->
            buildJsonObject {
                put("id", o.id)
                put("label", o.label)
                putOpt("description", o.description)
            }
        })
    }

    private fun decision(d: LinkDecision): JsonObject = buildJsonObject {
        put("kind", d.kind)
        when (d) {
            is LinkDecision.Permission -> put("mode", d.mode.wire)
            is LinkDecision.Question -> put("selections", strings(d.selections))
            is LinkDecision.ExitPlan -> {
                put("mode", d.mode.wire)
                putOpt("feedback", d.feedback)
            }
            is LinkDecision.Other -> Unit
        }
    }

    private fun session(s: AgentSession): JsonObject = buildJsonObject {
        put("session_id", s.sessionId)
        put("agent", s.agent)
        put("workspace_id", s.workspaceId)
        put("workspace_title", s.workspaceTitle)
        putOpt("title", s.title)
        put("state", s.state.wire)
        putOpt("state_since_ms", s.stateSinceMs)
        putOpt("last_activity_ms", s.lastActivityMs)
    }

    private fun entry(e: ChatEntry): JsonObject = buildJsonObject {
        put("id", e.id)
        put("rev", e.rev)
        put("seq", e.seq)
        put("role", e.role.wire)
        put("kind", e.kind.wire)
        put("text", e.text)
        putOpt("truncated", e.truncated)
        putOpt("tool_name", e.toolName)
        put("ts_ms", e.tsMs)
    }

    private fun workspace(w: LinkWorkspace): JsonObject = buildJsonObject {
        put("workspace_id", w.workspaceId)
        put("title", w.title)
        put("order", w.order)
        putOpt("directory", w.directory)
        putOpt("branch", w.branch)
        w.ports?.let { ports -> put("ports", list(ports) { JsonPrimitive(it) }) }
        put("terminals", list(w.terminals) { t ->
            buildJsonObject {
                put("terminal_id", t.terminalId)
                put("title", t.title)
                put("order", t.order)
                put("selected", t.selected)
                putOpt("session_id", t.sessionId)
            }
        })
    }

    private fun unit(u: TerminalInputUnit): JsonObject = buildJsonObject {
        when (u) {
            is TerminalInputUnit.Text -> {
                put("k", "text")
                put("text", u.text)
            }
            is TerminalInputUnit.Key -> {
                put("k", "key")
                put("key", u.key.wire)
                if (u.mods.isNotEmpty()) put("mods", strings(u.mods.map { it.wire }))
            }
            is TerminalInputUnit.Paste -> {
                put("k", "paste")
                put("text", u.text)
            }
            is TerminalInputUnit.Scroll -> {
                put("k", "scroll")
                put("lines", u.lines)
            }
            is TerminalInputUnit.Other -> put("k", u.kind)
        }
    }

    private fun toJson(m: LinkMessage): JsonObject = when (m) {
        is LinkMessage.Hello -> frame(T.HELLO) {
            put("client_version", m.clientVersion)
            put("device_name", m.deviceName)
        }
        is LinkMessage.Welcome -> frame(T.WELCOME) {
            put("protocol_version", m.protocolVersion)
            put("host_version", m.hostVersion)
            put("machine_name", m.machineName)
            if (m.features.isNotEmpty()) put("features", strings(m.features))
        }
        is LinkMessage.Error -> {
            m.callId?.let(::requireCallId)
            frame(T.ERROR) {
                put("code", m.code)
                put("message", m.message)
                putOpt("call_id", m.callId)
            }
        }
        is LinkMessage.SnapshotGet -> frame(T.SNAPSHOT_GET, m.callId)
        is LinkMessage.Snapshot -> frame(T.SNAPSHOT, m.callId) {
            put("revision", m.revision)
            put("pending", list(m.pending, ::pending))
        }
        is LinkMessage.Changed -> frame(T.CHANGED) {
            put("revision", m.revision)
            put("added", list(m.added, ::pending))
            put("resolved", strings(m.resolved))
        }
        is LinkMessage.Reply -> frame(T.REPLY, m.callId) {
            put("request_id", m.requestId)
            put("decision", decision(m.decision))
        }
        is LinkMessage.ReplyResult -> frame(T.REPLY_RESULT, m.callId) {
            put("request_id", m.requestId)
            put("outcome", m.outcome.wire)
        }
        is LinkMessage.Ping -> frame(T.PING) { put("nonce", uint64(m.nonce)) }
        is LinkMessage.Pong -> frame(T.PONG) { put("nonce", uint64(m.nonce)) }
        is LinkMessage.SessionsGet -> frame(T.SESSIONS_GET, m.callId)
        is LinkMessage.Sessions -> frame(T.SESSIONS, m.callId) {
            put("revision", m.revision)
            put("sessions", list(m.sessions, ::session))
        }
        is LinkMessage.SessionsChanged -> frame(T.SESSIONS_CHANGED) {
            put("revision", m.revision)
            put("upserted", list(m.upserted, ::session))
            put("removed", strings(m.removed))
        }
        is LinkMessage.ChatHistoryGet -> frame(T.CHAT_HISTORY_GET, m.callId) {
            put("session_id", m.sessionId)
            putOpt("before_seq", m.beforeSeq)
            put("limit", m.limit)
        }
        is LinkMessage.ChatHistory -> frame(T.CHAT_HISTORY, m.callId) {
            put("session_id", m.sessionId)
            put("entries", list(m.entries, ::entry))
            put("has_more", m.hasMore)
        }
        is LinkMessage.ChatEntries -> frame(T.CHAT_ENTRIES) {
            put("session_id", m.sessionId)
            put("entries", list(m.entries, ::entry))
        }
        is LinkMessage.ChatReset -> frame(T.CHAT_RESET) { put("session_id", m.sessionId) }
        is LinkMessage.ChatSend -> frame(T.CHAT_SEND, m.callId) {
            put("session_id", m.sessionId)
            put("text", m.text)
            if (m.attachments.isNotEmpty()) put("attachments", strings(m.attachments))
        }
        is LinkMessage.ChatSendResult -> frame(T.CHAT_SEND_RESULT, m.callId) { put("outcome", m.outcome.wire) }
        is LinkMessage.ChatInterrupt -> frame(T.CHAT_INTERRUPT, m.callId) {
            put("session_id", m.sessionId)
            put("hard", m.hard)
        }
        is LinkMessage.ChatInterruptResult -> frame(T.CHAT_INTERRUPT_RESULT, m.callId) { put("outcome", m.outcome.wire) }
        is LinkMessage.AttachBegin -> frame(T.ATTACH_BEGIN, m.callId) {
            put("kind", m.kind.wire)
            put("name", m.name)
            put("size", m.size)
        }
        is LinkMessage.AttachReady -> frame(T.ATTACH_READY, m.callId) { put("attachment_id", m.attachmentId) }
        is LinkMessage.AttachChunk -> frame(T.ATTACH_CHUNK, m.callId) {
            put("attachment_id", m.attachmentId)
            put("offset", m.offset)
            put("data", m.data.toBase64())
        }
        is LinkMessage.AttachChunkResult -> frame(T.ATTACH_CHUNK_RESULT, m.callId) {
            put("attachment_id", m.attachmentId)
            put("received", m.received)
        }
        is LinkMessage.AttachEnd -> {
            if (m.sha256.size != SHA256_BYTES) throw LinkCodecException.BadJson(null)
            frame(T.ATTACH_END, m.callId) {
                put("attachment_id", m.attachmentId)
                put("sha256", m.sha256.toHex())
            }
        }
        is LinkMessage.AttachEndResult -> frame(T.ATTACH_END_RESULT, m.callId) { put("attachment_id", m.attachmentId) }
        is LinkMessage.WorkspacesGet -> frame(T.WORKSPACES_GET, m.callId)
        is LinkMessage.Workspaces -> frame(T.WORKSPACES, m.callId) {
            put("revision", m.revision)
            put("workspaces", list(m.workspaces, ::workspace))
        }
        is LinkMessage.WorkspacesChanged -> frame(T.WORKSPACES_CHANGED) {
            put("revision", m.revision)
            put("upserted", list(m.upserted, ::workspace))
            put("removed", strings(m.removed))
        }
        is LinkMessage.WorkspaceCreate -> frame(T.WORKSPACE_CREATE, m.callId)
        is LinkMessage.WorkspaceCreateResult -> frame(T.WORKSPACE_CREATE_RESULT, m.callId) {
            put("outcome", m.outcome.wire)
            putOpt("workspace_id", m.workspaceId)
        }
        is LinkMessage.WorkspaceRename -> frame(T.WORKSPACE_RENAME, m.callId) {
            put("workspace_id", m.workspaceId)
            put("title", m.title)
        }
        is LinkMessage.WorkspaceRenameResult -> frame(T.WORKSPACE_RENAME_RESULT, m.callId) { put("outcome", m.outcome.wire) }
        is LinkMessage.WorkspaceClose -> frame(T.WORKSPACE_CLOSE, m.callId) { put("workspace_id", m.workspaceId) }
        is LinkMessage.WorkspaceCloseResult -> frame(T.WORKSPACE_CLOSE_RESULT, m.callId) { put("outcome", m.outcome.wire) }
        is LinkMessage.AgentClose -> frame(T.AGENT_CLOSE, m.callId) { put("session_id", m.sessionId) }
        is LinkMessage.AgentCloseResult -> frame(T.AGENT_CLOSE_RESULT, m.callId) { put("outcome", m.outcome.wire) }
        is LinkMessage.TerminalClose -> frame(T.TERMINAL_CLOSE, m.callId) {
            put("workspace_id", m.workspaceId)
            put("terminal_id", m.terminalId)
        }
        is LinkMessage.TerminalCloseResult -> frame(T.TERMINAL_CLOSE_RESULT, m.callId) { put("outcome", m.outcome.wire) }
        is LinkMessage.TerminalViewOpen -> frame(T.TERMINAL_VIEW_OPEN, m.callId) {
            put("terminal_id", m.terminalId)
            put("cols", m.cols)
            put("rows", m.rows)
        }
        is LinkMessage.TerminalViewOpenResult -> frame(T.TERMINAL_VIEW_OPEN_RESULT, m.callId) { put("outcome", m.outcome.wire) }
        is LinkMessage.TerminalViewInput -> frame(T.TERMINAL_VIEW_INPUT) {
            put("terminal_id", m.terminalId)
            put("units", list(m.units, ::unit))
        }
        is LinkMessage.TerminalViewResize -> frame(T.TERMINAL_VIEW_RESIZE) {
            put("terminal_id", m.terminalId)
            put("cols", m.cols)
            put("rows", m.rows)
        }
        is LinkMessage.TerminalViewResync -> frame(T.TERMINAL_VIEW_RESYNC) { put("terminal_id", m.terminalId) }
        is LinkMessage.TerminalViewClose -> frame(T.TERMINAL_VIEW_CLOSE) { put("terminal_id", m.terminalId) }
        is LinkMessage.TerminalViewEnded -> frame(T.TERMINAL_VIEW_ENDED) {
            put("terminal_id", m.terminalId)
            put("reason", m.reason.wire)
        }
        is LinkMessage.TerminalCreate -> frame(T.TERMINAL_CREATE, m.callId) { put("workspace_id", m.workspaceId) }
        is LinkMessage.TerminalCreateResult -> frame(T.TERMINAL_CREATE_RESULT, m.callId) {
            put("outcome", m.outcome.wire)
            putOpt("terminal_id", m.terminalId)
        }
        is LinkMessage.Unknown -> throw LinkCodecException.CannotEncodeUnknown()
    }

    // Decoding

    private fun JsonArray.strings(): List<String> = map { it.asStr() }

    private fun pending(o: JsonObject) = PendingItem(
        requestId = o.str("request_id"),
        kind = PendingKind(o.str("kind")),
        agent = o.str("agent"),
        workspaceId = o.str("workspace_id"),
        workspaceTitle = o.str("workspace_title"),
        toolName = o.optStr("tool_name"),
        toolInputPreview = o.optStr("tool_input_preview"),
        createdAtMs = o.long("created_at_ms"),
        modes = o.array("modes").strings(),
        questions = o.optArray("questions")?.map { question(it.asObj()) },
        planPreview = o.optStr("plan_preview"),
    )

    private fun question(o: JsonObject) = PendingQuestion(
        id = o.str("id"),
        header = o.optStr("header"),
        prompt = o.str("prompt"),
        multiSelect = o.bool("multi_select"),
        options = o.array("options").map {
            val option = it.asObj()
            PendingQuestionOption(option.str("id"), option.str("label"), option.optStr("description"))
        },
    )

    private fun decision(o: JsonObject): LinkDecision = when (val kind = o.str("kind")) {
        "permission" -> LinkDecision.Permission(PermissionMode(o.str("mode")))
        "question" -> LinkDecision.Question(o.array("selections").strings())
        "exit_plan" -> LinkDecision.ExitPlan(ExitPlanMode(o.str("mode")), o.optStr("feedback"))
        else -> LinkDecision.Other(kind)
    }

    private fun session(o: JsonObject) = AgentSession(
        sessionId = o.str("session_id"),
        agent = o.str("agent"),
        workspaceId = o.str("workspace_id"),
        workspaceTitle = o.str("workspace_title"),
        title = o.optStr("title"),
        state = AgentState(o.str("state")),
        stateSinceMs = o.optLong("state_since_ms"),
        lastActivityMs = o.optLong("last_activity_ms"),
    )

    private fun entry(o: JsonObject) = ChatEntry(
        id = o.str("id"),
        rev = o.long("rev"),
        seq = o.long("seq"),
        role = ChatEntryRole(o.str("role")),
        kind = ChatEntryKind(o.str("kind")),
        text = o.str("text"),
        truncated = o.optBool("truncated"),
        toolName = o.optStr("tool_name"),
        tsMs = o.long("ts_ms"),
    )

    private fun workspace(o: JsonObject) = LinkWorkspace(
        workspaceId = o.str("workspace_id"),
        title = o.str("title"),
        order = o.int("order"),
        directory = o.optStr("directory"),
        branch = o.optStr("branch"),
        ports = o.optArray("ports")?.map { it.asInt() },
        terminals = o.array("terminals").map {
            val t = it.asObj()
            LinkTerminal(t.str("terminal_id"), t.str("title"), t.int("order"), t.bool("selected"), t.optStr("session_id"))
        },
    )

    private fun pendingList(o: JsonObject, key: String) = o.array(key).map { pending(it.asObj()) }
    private fun sessionList(o: JsonObject, key: String) = o.array(key).map { session(it.asObj()) }
    private fun entryList(o: JsonObject, key: String) = o.array(key).map { entry(it.asObj()) }
    private fun workspaceList(o: JsonObject, key: String) = o.array(key).map { workspace(it.asObj()) }
    private fun outcome(o: JsonObject) = WorkspaceControlOutcome(o.str("outcome"))

    /**
     * A `terminal.view.input` unit. `lines` is any JSON integer a 64-bit host may send; one outside Int's range is held
     * as Int.MIN_VALUE or Int.MAX_VALUE, which [TerminalInputCheck] refuses as it refuses the value itself.
     */
    private fun unit(o: JsonObject): TerminalInputUnit = when (val k = o.str("k")) {
        "text" -> TerminalInputUnit.Text(o.str("text"))
        "key" -> TerminalInputUnit.Key(
            TerminalKey(o.str("key")),
            o.optArray("mods")?.strings()?.map(::TerminalModifier) ?: emptyList(),
        )
        "paste" -> TerminalInputUnit.Paste(o.str("text"))
        "scroll" -> TerminalInputUnit.Scroll(o.long("lines").coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt())
        else -> TerminalInputUnit.Other(k)
    }

    private fun chunkData(text: String): ByteArray = canonicalBase64ToBytesOrNull(text) ?: throw FieldError()

    private fun digest(text: String): ByteArray {
        if (text.length != SHA256_BYTES * 2) throw FieldError()
        return hexToBytesOrNull(text) ?: throw FieldError()
    }

    /** The message of a known `t`, or null when `t` is unknown. Throws [FieldError]. */
    private fun fromJson(t: String, o: JsonObject): LinkMessage? = when (t) {
        T.HELLO -> LinkMessage.Hello(o.str("client_version"), o.str("device_name"))
        T.WELCOME -> LinkMessage.Welcome(
            o.int("protocol_version"), o.str("host_version"), o.str("machine_name"),
            o.optArray("features")?.strings() ?: emptyList(),
        )
        T.ERROR -> {
            val callId = o.optStr("call_id")
            if (callId != null && !isValidCallId(callId)) throw FieldError()
            LinkMessage.Error(o.str("code"), o.str("message"), callId)
        }
        T.SNAPSHOT_GET -> LinkMessage.SnapshotGet(o.callId())
        T.SNAPSHOT -> LinkMessage.Snapshot(o.callId(), o.long("revision"), pendingList(o, "pending"))
        T.CHANGED -> LinkMessage.Changed(o.long("revision"), pendingList(o, "added"), o.array("resolved").strings())
        T.REPLY -> LinkMessage.Reply(o.callId(), o.str("request_id"), decision(o.obj("decision")))
        T.REPLY_RESULT -> LinkMessage.ReplyResult(o.callId(), o.str("request_id"), ReplyOutcome(o.str("outcome")))
        T.PING -> LinkMessage.Ping(o.uLong("nonce"))
        T.PONG -> LinkMessage.Pong(o.uLong("nonce"))
        T.SESSIONS_GET -> LinkMessage.SessionsGet(o.callId())
        T.SESSIONS -> LinkMessage.Sessions(o.callId(), o.long("revision"), sessionList(o, "sessions"))
        T.SESSIONS_CHANGED ->
            LinkMessage.SessionsChanged(o.long("revision"), sessionList(o, "upserted"), o.array("removed").strings())
        T.CHAT_HISTORY_GET -> LinkMessage.ChatHistoryGet(o.callId(), o.str("session_id"), o.optLong("before_seq"), o.int("limit"))
        T.CHAT_HISTORY -> LinkMessage.ChatHistory(o.callId(), o.str("session_id"), entryList(o, "entries"), o.bool("has_more"))
        T.CHAT_ENTRIES -> LinkMessage.ChatEntries(o.str("session_id"), entryList(o, "entries"))
        T.CHAT_RESET -> LinkMessage.ChatReset(o.str("session_id"))
        T.CHAT_SEND -> LinkMessage.ChatSend(
            o.callId(), o.str("session_id"), o.str("text"), o.optArray("attachments")?.strings() ?: emptyList(),
        )
        T.CHAT_SEND_RESULT -> LinkMessage.ChatSendResult(o.callId(), ChatSendOutcome(o.str("outcome")))
        T.CHAT_INTERRUPT -> LinkMessage.ChatInterrupt(o.callId(), o.str("session_id"), o.bool("hard"))
        T.CHAT_INTERRUPT_RESULT -> LinkMessage.ChatInterruptResult(o.callId(), ChatInterruptOutcome(o.str("outcome")))
        T.ATTACH_BEGIN -> LinkMessage.AttachBegin(o.callId(), AttachmentKind(o.str("kind")), o.str("name"), o.int("size"))
        T.ATTACH_READY -> LinkMessage.AttachReady(o.callId(), o.str("attachment_id"))
        T.ATTACH_CHUNK ->
            LinkMessage.AttachChunk(o.callId(), o.str("attachment_id"), o.int("offset"), chunkData(o.str("data")))
        T.ATTACH_CHUNK_RESULT -> LinkMessage.AttachChunkResult(o.callId(), o.str("attachment_id"), o.int("received"))
        T.ATTACH_END -> LinkMessage.AttachEnd(o.callId(), o.str("attachment_id"), digest(o.str("sha256")))
        T.ATTACH_END_RESULT -> LinkMessage.AttachEndResult(o.callId(), o.str("attachment_id"))
        T.WORKSPACES_GET -> LinkMessage.WorkspacesGet(o.callId())
        T.WORKSPACES -> LinkMessage.Workspaces(o.callId(), o.long("revision"), workspaceList(o, "workspaces"))
        T.WORKSPACES_CHANGED ->
            LinkMessage.WorkspacesChanged(o.long("revision"), workspaceList(o, "upserted"), o.array("removed").strings())
        T.WORKSPACE_CREATE -> LinkMessage.WorkspaceCreate(o.callId())
        T.WORKSPACE_CREATE_RESULT -> LinkMessage.WorkspaceCreateResult(o.callId(), outcome(o), o.optStr("workspace_id"))
        T.WORKSPACE_RENAME -> LinkMessage.WorkspaceRename(o.callId(), o.str("workspace_id"), o.str("title"))
        T.WORKSPACE_RENAME_RESULT -> LinkMessage.WorkspaceRenameResult(o.callId(), outcome(o))
        T.WORKSPACE_CLOSE -> LinkMessage.WorkspaceClose(o.callId(), o.str("workspace_id"))
        T.WORKSPACE_CLOSE_RESULT -> LinkMessage.WorkspaceCloseResult(o.callId(), outcome(o))
        T.AGENT_CLOSE -> LinkMessage.AgentClose(o.callId(), o.str("session_id"))
        T.AGENT_CLOSE_RESULT -> LinkMessage.AgentCloseResult(o.callId(), outcome(o))
        T.TERMINAL_CLOSE -> LinkMessage.TerminalClose(o.callId(), o.str("workspace_id"), o.str("terminal_id"))
        T.TERMINAL_CLOSE_RESULT -> LinkMessage.TerminalCloseResult(o.callId(), outcome(o))
        T.TERMINAL_VIEW_OPEN -> LinkMessage.TerminalViewOpen(o.callId(), o.str("terminal_id"), o.int("cols"), o.int("rows"))
        T.TERMINAL_VIEW_OPEN_RESULT -> LinkMessage.TerminalViewOpenResult(o.callId(), TerminalViewOpenOutcome(o.str("outcome")))
        T.TERMINAL_VIEW_INPUT -> LinkMessage.TerminalViewInput(o.str("terminal_id"), o.array("units").map { unit(it.asObj()) })
        T.TERMINAL_VIEW_RESIZE -> LinkMessage.TerminalViewResize(o.str("terminal_id"), o.int("cols"), o.int("rows"))
        T.TERMINAL_VIEW_RESYNC -> LinkMessage.TerminalViewResync(o.str("terminal_id"))
        T.TERMINAL_VIEW_CLOSE -> LinkMessage.TerminalViewClose(o.str("terminal_id"))
        T.TERMINAL_VIEW_ENDED -> LinkMessage.TerminalViewEnded(o.str("terminal_id"), TerminalViewEndReason(o.str("reason")))
        T.TERMINAL_CREATE -> LinkMessage.TerminalCreate(o.callId(), o.str("workspace_id"))
        T.TERMINAL_CREATE_RESULT -> LinkMessage.TerminalCreateResult(o.callId(), outcome(o), o.optStr("terminal_id"))
        else -> null
    }

    /** Wire `t` values (PROTOCOL.md section 8). */
    private object T {
        const val HELLO = "hello"
        const val WELCOME = "welcome"
        const val ERROR = "error"
        const val SNAPSHOT_GET = "agent.snapshot.get"
        const val SNAPSHOT = "agent.snapshot"
        const val CHANGED = "agent.changed"
        const val REPLY = "agent.reply"
        const val REPLY_RESULT = "agent.reply.result"
        const val PING = "ping"
        const val PONG = "pong"
        const val SESSIONS_GET = "agent.sessions.get"
        const val SESSIONS = "agent.sessions"
        const val SESSIONS_CHANGED = "agent.sessions.changed"
        const val CHAT_HISTORY_GET = "chat.history.get"
        const val CHAT_HISTORY = "chat.history"
        const val CHAT_ENTRIES = "chat.entries"
        const val CHAT_RESET = "chat.reset"
        const val CHAT_SEND = "chat.send"
        const val CHAT_SEND_RESULT = "chat.send.result"
        const val CHAT_INTERRUPT = "chat.interrupt"
        const val CHAT_INTERRUPT_RESULT = "chat.interrupt.result"
        const val ATTACH_BEGIN = "attach.begin"
        const val ATTACH_READY = "attach.ready"
        const val ATTACH_CHUNK = "attach.chunk"
        const val ATTACH_CHUNK_RESULT = "attach.chunk.result"
        const val ATTACH_END = "attach.end"
        const val ATTACH_END_RESULT = "attach.end.result"
        const val WORKSPACES_GET = "workspace.list.get"
        const val WORKSPACES = "workspace.list"
        const val WORKSPACES_CHANGED = "workspace.changed"
        const val WORKSPACE_CREATE = "workspace.create"
        const val WORKSPACE_CREATE_RESULT = "workspace.create.result"
        const val WORKSPACE_RENAME = "workspace.rename"
        const val WORKSPACE_RENAME_RESULT = "workspace.rename.result"
        const val WORKSPACE_CLOSE = "workspace.close"
        const val WORKSPACE_CLOSE_RESULT = "workspace.close.result"
        const val AGENT_CLOSE = "agent.close"
        const val AGENT_CLOSE_RESULT = "agent.close.result"
        const val TERMINAL_CLOSE = "terminal.close"
        const val TERMINAL_CLOSE_RESULT = "terminal.close.result"
        const val TERMINAL_VIEW_OPEN = "terminal.view.open"
        const val TERMINAL_VIEW_OPEN_RESULT = "terminal.view.open.result"
        const val TERMINAL_VIEW_INPUT = "terminal.view.input"
        const val TERMINAL_VIEW_RESIZE = "terminal.view.resize"
        const val TERMINAL_VIEW_RESYNC = "terminal.view.resync"
        const val TERMINAL_VIEW_CLOSE = "terminal.view.close"
        const val TERMINAL_VIEW_ENDED = "terminal.view.ended"
        const val TERMINAL_CREATE = "terminal.create"
        const val TERMINAL_CREATE_RESULT = "terminal.create.result"
    }
}
