package com.shellx.link.core

import java.util.Base64
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

/** Builds the message a `messages.json` entry describes, by hand and key by key. It never calls [LinkCodec]. */
object VectorMessages {
    /** The 50 sendable cases of the plans' tables (3B's 40 and 3G's ten): every case except `unknown`. */
    val SENDABLE_CASES: Set<String> = setOf(
        "hello", "welcome", "error", "snapshot_get", "snapshot", "changed", "reply", "reply_result", "ping", "pong",
        "sessions_get", "sessions", "sessions_changed", "chat_history_get", "chat_history", "chat_entries",
        "chat_reset", "chat_send", "chat_send_result", "chat_interrupt", "chat_interrupt_result",
        "attach_begin", "attach_ready", "attach_chunk", "attach_chunk_result", "attach_end", "attach_end_result",
        "workspaces_get", "workspaces", "workspaces_changed", "workspace_create", "workspace_create_result",
        "workspace_rename", "workspace_rename_result", "workspace_close", "workspace_close_result",
        "agent_close", "agent_close_result", "terminal_close", "terminal_close_result",
        "terminal_view_open", "terminal_view_open_result", "terminal_view_input", "terminal_view_resize",
        "terminal_view_resync", "terminal_view_close", "terminal_view_ended", "terminal_create", "terminal_create_result",
        "terminal_view_frame",
    )

    private fun JsonObject.s(key: String): String = getValue(key).jsonPrimitive.content
    private fun JsonObject.os(key: String): String? = get(key)?.jsonPrimitive?.content
    private fun JsonObject.l(key: String): Long = getValue(key).jsonPrimitive.long
    private fun JsonObject.ol(key: String): Long? = get(key)?.jsonPrimitive?.long
    private fun JsonObject.i(key: String): Int = getValue(key).jsonPrimitive.int
    private fun JsonObject.oi(key: String): Int? = get(key)?.jsonPrimitive?.int
    private fun JsonObject.b(key: String): Boolean = getValue(key).jsonPrimitive.boolean
    private fun JsonObject.ob(key: String): Boolean? = get(key)?.jsonPrimitive?.boolean
    private fun JsonObject.strings(key: String): List<String> = getValue(key).jsonArray.map { it.jsonPrimitive.content }
    private fun JsonObject.objects(key: String): List<JsonObject> = getValue(key).jsonArray.map { it.jsonObject }

    private fun pending(o: JsonObject) = PendingItem(
        requestId = o.s("request_id"), kind = PendingKind(o.s("kind")), agent = o.s("agent"),
        workspaceId = o.s("workspace_id"), workspaceTitle = o.s("workspace_title"),
        toolName = o.os("tool_name"), toolInputPreview = o.os("tool_input_preview"), createdAtMs = o.l("created_at_ms"),
        modes = o.strings("modes"),
        questions = o["questions"]?.jsonArray?.map { question(it.jsonObject) }, planPreview = o.os("plan_preview"),
    )

    private fun question(o: JsonObject) = PendingQuestion(
        id = o.s("id"), header = o.os("header"), prompt = o.s("prompt"), multiSelect = o.b("multi_select"),
        options = o.objects("options").map { PendingQuestionOption(it.s("id"), it.s("label"), it.os("description")) },
    )

    private fun session(o: JsonObject) = AgentSession(
        sessionId = o.s("session_id"), agent = o.s("agent"), workspaceId = o.s("workspace_id"),
        workspaceTitle = o.s("workspace_title"), title = o.os("title"), state = AgentState(o.s("state")),
        stateSinceMs = o.ol("state_since_ms"), lastActivityMs = o.ol("last_activity_ms"),
    )

    private fun entry(o: JsonObject) = ChatEntry(
        id = o.s("id"), rev = o.l("rev"), seq = o.l("seq"), role = ChatEntryRole(o.s("role")),
        kind = ChatEntryKind(o.s("kind")), text = o.s("text"), truncated = o.ob("truncated"),
        toolName = o.os("tool_name"), tsMs = o.l("ts_ms"),
    )

    private fun workspace(o: JsonObject) = LinkWorkspace(
        workspaceId = o.s("workspace_id"), title = o.s("title"), order = o.i("order"), directory = o.os("directory"),
        branch = o.os("branch"), ports = o["ports"]?.jsonArray?.map { it.jsonPrimitive.int },
        terminals = o.objects("terminals").map {
            LinkTerminal(it.s("terminal_id"), it.s("title"), it.i("order"), it.b("selected"), it.os("session_id"))
        },
    )

    private fun decision(o: JsonObject): LinkDecision = when (val kind = o.s("kind")) {
        "permission" -> LinkDecision.Permission(PermissionMode(o.s("mode")))
        "question" -> LinkDecision.Question(o.strings("selections"))
        "exit_plan" -> LinkDecision.ExitPlan(ExitPlanMode(o.s("mode")), o.os("feedback"))
        else -> LinkDecision.Other(kind)
    }

    /** As 2A's `terminalUnits`: an unknown `k` keeps only its kind. */
    private fun terminalUnits(e: JsonElement?): List<TerminalInputUnit> = e!!.jsonArray.map { it.jsonObject }.map { u ->
        when (val k = u.s("k")) {
            "text" -> TerminalInputUnit.Text(u.s("text"))
            "key" -> TerminalInputUnit.Key(
                TerminalKey(u.s("key")),
                u["mods"]?.jsonArray?.map { TerminalModifier(it.jsonPrimitive.content) } ?: emptyList(),
            )
            "paste" -> TerminalInputUnit.Paste(u.s("text"))
            "scroll" -> TerminalInputUnit.Scroll(u.i("lines"))
            else -> TerminalInputUnit.Other(k)
        }
    }

    /** As 2A's `terminalFramePart`: absent arrays are empty, absent `history` and `scroll` are 0. */
    private fun terminalFramePart(m: JsonObject): TerminalFramePart {
        fun head(h: JsonObject) = TerminalFrameHead(
            kind = TerminalFrameKind(h.s("kind")), cols = h.i("cols"), rows = h.i("rows"), alt = h.b("alt"),
            cursor = h["cursor"]?.jsonObject?.let { c ->
                TerminalCursor(c.i("x"), c.i("y"), TerminalCursorShape(c.s("shape")), c.b("visible"), c.b("blink"))
            },
            palette = h["palette"]?.jsonObject?.let { p -> TerminalPalette(p.s("fg"), p.s("bg"), p.os("cursor"), p.strings("colors")) },
            history = h.oi("history") ?: 0, scroll = h.oi("scroll") ?: 0,
        )
        val styles = m["styles"]?.jsonArray?.map { it.jsonObject }?.map { s ->
            TerminalStyle(
                s.i("id"), s.oi("fg"), s.os("fg_rgb"), s.oi("bg"), s.os("bg_rgb"),
                s["attrs"]?.jsonArray?.map { TerminalAttribute(it.jsonPrimitive.content) } ?: emptyList(),
            )
        } ?: emptyList()
        val lines = m["lines"]?.jsonArray?.map { it.jsonObject }?.map { l ->
            TerminalLine(l.i("y"), l["runs"]?.jsonArray?.map { it.jsonObject }?.map { r -> TerminalRun(r.oi("x"), r.s("t"), r.oi("s"), r.oi("w")) } ?: emptyList())
        } ?: emptyList()
        return TerminalFramePart(m.l("revision"), m.i("part"), m.i("parts"), m["head"]?.jsonObject?.let(::head), styles, lines)
    }

    fun fromVector(m: JsonObject): LinkMessage = when (val case = m.s("case")) {
        "hello" -> LinkMessage.Hello(m.s("client_version"), m.s("device_name"))
        "welcome" -> LinkMessage.Welcome(
            m.i("protocol_version"), m.s("host_version"), m.s("machine_name"),
            if ("features" in m) m.strings("features") else emptyList(),
        )
        "error" -> LinkMessage.Error(m.s("code"), m.s("message"), m.os("call_id"))
        "snapshot_get" -> LinkMessage.SnapshotGet(m.s("call_id"))
        "snapshot" -> LinkMessage.Snapshot(m.s("call_id"), m.l("revision"), m.objects("pending").map(::pending))
        "changed" -> LinkMessage.Changed(m.l("revision"), m.objects("added").map(::pending), m.strings("resolved"))
        "reply" -> LinkMessage.Reply(m.s("call_id"), m.s("request_id"), decision(m.getValue("decision").jsonObject))
        "reply_result" -> LinkMessage.ReplyResult(m.s("call_id"), m.s("request_id"), ReplyOutcome(m.s("outcome")))
        "ping" -> LinkMessage.Ping(m.getValue("nonce").jsonPrimitive.content.toULong())
        "pong" -> LinkMessage.Pong(m.getValue("nonce").jsonPrimitive.content.toULong())
        "sessions_get" -> LinkMessage.SessionsGet(m.s("call_id"))
        "sessions" -> LinkMessage.Sessions(m.s("call_id"), m.l("revision"), m.objects("sessions").map(::session))
        "sessions_changed" ->
            LinkMessage.SessionsChanged(m.l("revision"), m.objects("upserted").map(::session), m.strings("removed"))
        "chat_history_get" -> LinkMessage.ChatHistoryGet(m.s("call_id"), m.s("session_id"), m.ol("before_seq"), m.i("limit"))
        "chat_history" ->
            LinkMessage.ChatHistory(m.s("call_id"), m.s("session_id"), m.objects("entries").map(::entry), m.b("has_more"))
        "chat_entries" -> LinkMessage.ChatEntries(m.s("session_id"), m.objects("entries").map(::entry))
        "chat_reset" -> LinkMessage.ChatReset(m.s("session_id"))
        "chat_send" -> LinkMessage.ChatSend(
            m.s("call_id"), m.s("session_id"), m.s("text"),
            if ("attachments" in m) m.strings("attachments") else emptyList(),
        )
        "chat_send_result" -> LinkMessage.ChatSendResult(m.s("call_id"), ChatSendOutcome(m.s("outcome")))
        "chat_interrupt" -> LinkMessage.ChatInterrupt(m.s("call_id"), m.s("session_id"), m.b("hard"))
        "chat_interrupt_result" -> LinkMessage.ChatInterruptResult(m.s("call_id"), ChatInterruptOutcome(m.s("outcome")))
        "attach_begin" -> LinkMessage.AttachBegin(m.s("call_id"), AttachmentKind(m.s("kind")), m.s("name"), m.i("size"))
        "attach_ready" -> LinkMessage.AttachReady(m.s("call_id"), m.s("attachment_id"))
        "attach_chunk" -> LinkMessage.AttachChunk(
            m.s("call_id"), m.s("attachment_id"), m.i("offset"), Base64.getDecoder().decode(m.s("data")),
        )
        "attach_chunk_result" -> LinkMessage.AttachChunkResult(m.s("call_id"), m.s("attachment_id"), m.i("received"))
        "attach_end" -> LinkMessage.AttachEnd(m.s("call_id"), m.s("attachment_id"), Vectors.hex(m.s("sha256")))
        "attach_end_result" -> LinkMessage.AttachEndResult(m.s("call_id"), m.s("attachment_id"))
        "workspaces_get" -> LinkMessage.WorkspacesGet(m.s("call_id"))
        "workspaces" -> LinkMessage.Workspaces(m.s("call_id"), m.l("revision"), m.objects("workspaces").map(::workspace))
        "workspaces_changed" ->
            LinkMessage.WorkspacesChanged(m.l("revision"), m.objects("upserted").map(::workspace), m.strings("removed"))
        "workspace_create" -> LinkMessage.WorkspaceCreate(m.s("call_id"))
        "workspace_create_result" ->
            LinkMessage.WorkspaceCreateResult(m.s("call_id"), WorkspaceControlOutcome(m.s("outcome")), m.os("workspace_id"))
        "workspace_rename" -> LinkMessage.WorkspaceRename(m.s("call_id"), m.s("workspace_id"), m.s("title"))
        "workspace_rename_result" -> LinkMessage.WorkspaceRenameResult(m.s("call_id"), WorkspaceControlOutcome(m.s("outcome")))
        "workspace_close" -> LinkMessage.WorkspaceClose(m.s("call_id"), m.s("workspace_id"))
        "workspace_close_result" -> LinkMessage.WorkspaceCloseResult(m.s("call_id"), WorkspaceControlOutcome(m.s("outcome")))
        "agent_close" -> LinkMessage.AgentClose(m.s("call_id"), m.s("session_id"))
        "agent_close_result" -> LinkMessage.AgentCloseResult(m.s("call_id"), WorkspaceControlOutcome(m.s("outcome")))
        "terminal_close" -> LinkMessage.TerminalClose(m.s("call_id"), m.s("workspace_id"), m.s("terminal_id"))
        "terminal_close_result" -> LinkMessage.TerminalCloseResult(m.s("call_id"), WorkspaceControlOutcome(m.s("outcome")))
        "terminal_view_open" -> LinkMessage.TerminalViewOpen(m.s("call_id"), m.s("terminal_id"), m.i("cols"), m.i("rows"))
        "terminal_view_open_result" -> LinkMessage.TerminalViewOpenResult(m.s("call_id"), TerminalViewOpenOutcome(m.s("outcome")))
        "terminal_view_input" -> LinkMessage.TerminalViewInput(m.s("terminal_id"), terminalUnits(m["units"]))
        "terminal_view_resize" -> LinkMessage.TerminalViewResize(m.s("terminal_id"), m.i("cols"), m.i("rows"))
        "terminal_view_resync" -> LinkMessage.TerminalViewResync(m.s("terminal_id"))
        "terminal_view_close" -> LinkMessage.TerminalViewClose(m.s("terminal_id"))
        "terminal_view_ended" -> LinkMessage.TerminalViewEnded(m.s("terminal_id"), TerminalViewEndReason(m.s("reason")))
        "terminal_view_frame" -> LinkMessage.TerminalViewFrame(m.s("terminal_id"), terminalFramePart(m))
        "terminal_create" -> LinkMessage.TerminalCreate(m.s("call_id"), m.s("workspace_id"))
        "terminal_create_result" ->
            LinkMessage.TerminalCreateResult(m.s("call_id"), WorkspaceControlOutcome(m.s("outcome")), m.os("terminal_id"))
        "unknown" -> LinkMessage.Unknown(m.s("type"), m.os("call_id"))
        else -> error("no vector builder for case $case")
    }
}
