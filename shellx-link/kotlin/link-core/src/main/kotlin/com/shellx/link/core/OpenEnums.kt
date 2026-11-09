package com.shellx.link.core

// Open enums (PROTOCOL.md section 3, "Extension"): a wire value this version does not know is kept as is,
// never an error. Each constant's wire value is its lower-case name unless written out.

/** The `kind` of a pending request. */
@JvmInline
value class PendingKind(val wire: String) {
    companion object {
        val PERMISSION = PendingKind("permission")
        val QUESTION = PendingKind("question")
        val EXIT_PLAN = PendingKind("exit_plan")
    }
}

/** How the user answers a permission prompt. */
@JvmInline
value class PermissionMode(val wire: String) {
    companion object {
        val ONCE = PermissionMode("once")
        val ALWAYS = PermissionMode("always")
        val ALL = PermissionMode("all")
        val DENY = PermissionMode("deny")
    }
}

/** How the user answers an agent's plan. */
@JvmInline
value class ExitPlanMode(val wire: String) {
    companion object {
        val ULTRAPLAN = ExitPlanMode("ultraplan")
        val AUTO_ACCEPT = ExitPlanMode("auto_accept")
        val MANUAL = ExitPlanMode("manual")
        val DENY = ExitPlanMode("deny")
    }
}

/** What the host did with an `agent.reply`. */
@JvmInline
value class ReplyOutcome(val wire: String) {
    companion object {
        val DELIVERED = ReplyOutcome("delivered")
        val ALREADY_HANDLED = ReplyOutcome("already_handled")
        val UNKNOWN = ReplyOutcome("unknown")
    }
}

/** What an agent session is doing. */
@JvmInline
value class AgentState(val wire: String) {
    companion object {
        val IDLE = AgentState("idle")
        val WORKING = AgentState("working")
        val NEEDS_INPUT = AgentState("needs_input")
        val ENDED = AgentState("ended")
    }
}

/** Who wrote a chat entry. */
@JvmInline
value class ChatEntryRole(val wire: String) {
    companion object {
        val USER = ChatEntryRole("user")
        val AGENT = ChatEntryRole("agent")
        val SYSTEM = ChatEntryRole("system")
    }
}

/** What a chat entry is. */
@JvmInline
value class ChatEntryKind(val wire: String) {
    companion object {
        val PROSE = ChatEntryKind("prose")
        val THOUGHT = ChatEntryKind("thought")
        val TOOL_USE = ChatEntryKind("tool_use")
        val STATUS = ChatEntryKind("status")
        val OTHER = ChatEntryKind("other")
    }
}

/** How the host answered `chat.send`. */
@JvmInline
value class ChatSendOutcome(val wire: String) {
    companion object {
        val SUBMITTED = ChatSendOutcome("submitted")
        val NOT_FOUND = ChatSendOutcome("not_found")
        val BUSY = ChatSendOutcome("busy")
        val FAILED = ChatSendOutcome("failed")
    }
}

/** How the host answered `chat.interrupt`. */
@JvmInline
value class ChatInterruptOutcome(val wire: String) {
    companion object {
        val SENT = ChatInterruptOutcome("sent")
        val NOT_FOUND = ChatInterruptOutcome("not_found")
        val FAILED = ChatInterruptOutcome("failed")
    }
}

/** What an upload is (PROTOCOL.md section 5, "Attachments"). */
@JvmInline
value class AttachmentKind(val wire: String) {
    companion object {
        val IMAGE = AttachmentKind("image")
        val FILE = AttachmentKind("file")
    }
}

/** How the host answered `workspace.create`, `workspace.rename`, `workspace.close`, `agent.close` or `terminal.close`. */
@JvmInline
value class WorkspaceControlOutcome(val wire: String) {
    companion object {
        val OK = WorkspaceControlOutcome("ok")
        val NOT_FOUND = WorkspaceControlOutcome("not_found")
        val REFUSED = WorkspaceControlOutcome("refused")
        val FAILED = WorkspaceControlOutcome("failed")
    }
}
