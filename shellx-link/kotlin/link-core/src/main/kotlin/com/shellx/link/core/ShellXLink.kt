package com.shellx.link.core

import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/** Protocol constants of ShellX Link v1 (PROTOCOL.md; `ShellXLink.swift`). */
object ShellXLink {
    const val PROTOCOL_VERSION = 1

    /** Largest attachment, in bytes (10 MiB); PROTOCOL.md section 5, "Attachments". */
    const val MAX_ATTACHMENT_BYTES = 10_485_760

    /** Most attachments one `chat.send` may name. */
    const val MAX_ATTACHMENTS_PER_MESSAGE = 5

    /** Most finished uploads a Link session holds that no `chat.send` has used yet. */
    const val MAX_PENDING_UPLOADS = 5

    /** How long a host keeps a session's unsent uploads after the last `attach.*` call it accepted. */
    val UNSENT_UPLOAD_LIFETIME: Duration = 300.seconds

    /** Most bytes of file data in one `attach.chunk` (the base64 form fits a frame). */
    const val MAX_ATTACHMENT_CHUNK_BYTES = 45_000

    /** The `welcome.features` entry of a host that takes attachments. */
    const val ATTACHMENTS_FEATURE = "attachments"

    /** The `welcome.features` entry of a host that lists its workspaces. */
    const val WORKSPACES_FEATURE = "workspaces"

    /** The `welcome.features` entry of a host that takes `workspace.create`, `workspace.rename` and `workspace.close`. */
    const val WORKSPACE_CONTROL_FEATURE = "workspace_control"

    /** The `welcome.features` entry of a host that takes `agent.close`. */
    const val AGENT_CLOSE_FEATURE = "agent_close"

    /** The `welcome.features` entry of a host that takes `terminal.close`. */
    const val TERMINAL_CLOSE_FEATURE = "terminal_close"

    /** Longest `title` of a `workspace.rename`, in UTF-8 bytes. The host checks it; the codec does not. */
    const val MAX_WORKSPACE_TITLE_BYTES = 512
}
