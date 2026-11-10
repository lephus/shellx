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

    // Terminal views (PROTOCOL.md section 11; `ShellXLink+Terminal.swift`).

    /** The `welcome.features` entry of a host that serves terminal views (`terminal.view.*`). */
    const val TERMINAL_VIEW_FEATURE = "terminal_view"

    /** The `welcome.features` entry of a host that takes `terminal.create`. */
    const val TERMINAL_CREATE_FEATURE = "terminal_create"

    /** Columns a phone may ask for; the host clamps into this range (PROTOCOL.md 11.3). */
    val TERMINAL_COLUMNS: IntRange = 20..300

    /** Rows a phone may ask for; the host clamps into this range (PROTOCOL.md 11.3). */
    val TERMINAL_ROWS: IntRange = 5..120

    /** Largest `cols` or `rows` in a frame (PROTOCOL.md 11.5). */
    const val TERMINAL_MAX_GRID_SIZE = 1000

    /** Most parts of one frame. */
    const val TERMINAL_MAX_FRAME_PARTS = 256

    /** Most UTF-8 bytes in the text of one cell. */
    const val TERMINAL_MAX_CELL_TEXT_BYTES = 32

    /** History rows a snapshot carries at most. */
    const val TERMINAL_SNAPSHOT_HISTORY_ROWS = 240

    /** History rows of a snapshot and its history frames together. */
    const val TERMINAL_HISTORY_ROW_BUDGET = 4000

    /** Bytes of the messages of the history frames that follow one snapshot. */
    const val TERMINAL_HISTORY_FILL_MAX_BYTES = 262_144

    /** History rows a delta carries at most. */
    const val TERMINAL_MAX_DELTA_HISTORY_ROWS = 2000

    /** Units in one `terminal.view.input`. */
    const val TERMINAL_MAX_INPUT_UNITS = 64

    /** UTF-8 bytes of typed text in one `terminal.view.input`. */
    const val TERMINAL_MAX_TEXT_BYTES = 4096

    /** UTF-8 bytes of pasted text in one `terminal.view.input`. */
    const val TERMINAL_MAX_PASTE_BYTES = 16_384

    /** Most lines of a `scroll` unit, either sign. */
    const val TERMINAL_MAX_SCROLL_LINES = 100

    /** Input and resize messages of a view a host holds unapplied. */
    const val TERMINAL_MAX_QUEUED_INPUTS = 64
}
