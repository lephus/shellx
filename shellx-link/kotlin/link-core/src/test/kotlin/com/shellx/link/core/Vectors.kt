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
    val pairing: JsonObject get() = json("../../spec/vectors/pairing.json")
    val terminal: JsonObject get() = json("../../spec/vectors/terminal.json")

    fun hex(text: String): ByteArray = hexToBytesOrNull(text) ?: error("bad hex")

    /** Contracts §6: `terminal.view.frame`, which plan 3G Task 2 adds. Skipped in every section until then. */
    val TERMINAL_VIEW_CASES = setOf("terminal_view_frame")

    fun isTerminalViewFrame(t: String?) = t == "terminal.view.frame"
}
