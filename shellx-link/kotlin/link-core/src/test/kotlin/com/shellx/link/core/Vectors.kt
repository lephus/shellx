package com.shellx.link.core

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

object Vectors {
    /** Contracts §5: read in place, relative to the module directory. */
    fun file(relative: String): File = File(relative).also { check(it.isFile) { "missing vector file ${it.absolutePath}" } }

    fun json(relative: String): JsonObject = Json.parseToJsonElement(file(relative).readText()).jsonObject

    val messages: JsonObject get() = json("../../spec/vectors/messages.json")
    val noise: JsonObject get() = json("../../vectors/noise_xx.json")

    fun hex(text: String): ByteArray = hexToBytesOrNull(text) ?: error("bad hex")

    /** Contracts §6: cases plan 3G adds. Skipped here if 2A has put them in messages.json. */
    val TERMINAL_VIEW_CASES = setOf(
        "terminal_view_open", "terminal_view_open_result", "terminal_view_frame",
        "terminal_view_input", "terminal_view_resize", "terminal_view_resync", "terminal_view_close",
        "terminal_view_ended", "terminal_create", "terminal_create_result",
    )

    fun isTerminalViewFrame(t: String?) =
        t != null && (t.startsWith("terminal.view.") || t == "terminal.create" || t == "terminal.create.result")
}
