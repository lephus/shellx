package com.shellx.core.pending

import com.shellx.core.text.utf8Size
import com.shellx.link.core.PendingItem
import com.shellx.link.core.PendingKind
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Keys of a tool's input that say best what the call does, most telling first: Bash's `command`, the file of
 *  Read/Edit/Write, the address of WebFetch, the pattern of Grep/Glob. */
private val TELLING = listOf("command", "file_path", "notebook_path", "url", "pattern", "path", "query")

/**
 * The text under a card's header, for display only (PROTOCOL.md section 6: never the complete input):
 * - permission: the tool input's most telling value (the command, the file), or the preview as it came when it is
 *   not a JSON object (a preview cut at 8192 bytes no longer parses);
 * - question: every question's prompt, one per line;
 * - plan: the plan.
 */
val PendingItem.previewText: String?
    get() = when (kind) {
        PendingKind.PERMISSION -> toolInputPreview?.let(::tellingValue)
        PendingKind.QUESTION -> questions.orEmpty().map { it.prompt }.takeIf { it.isNotEmpty() }?.joinToString("\n")
        PendingKind.EXIT_PLAN -> planPreview
        else -> toolInputPreview ?: planPreview
    }

/**
 * The tool input's fields for the full view ("Show more"): the most telling first, then the others by name. A value
 * that is not a string is compact JSON with object keys sorted, recursively. Null when the preview is not a JSON
 * object (then it is shown as it came).
 */
val PendingItem.previewFields: List<Pair<String, String>>?
    get() {
        val preview = toolInputPreview ?: return null
        val obj = jsonObject(preview) ?: return null
        val others = obj.keys.filter { it !in TELLING }.sorted()
        val keys = TELLING.filter { it in obj } + others
        return keys.mapNotNull { key -> obj[key]?.let { key to text(it) } }
    }

/**
 * True when [text] may have been cut by the host (PROTOCOL.md section 6): it ends within one character of the
 * 8192-byte preview limit or of the 1024-byte step for oversize frames.
 */
fun PendingItem.Companion.previewMayBeCut(text: String): Boolean {
    val bytes = text.utf8Size
    return listOf(MAX_PREVIEW_BYTES, 1024).any { bytes <= it && bytes > it - 4 }
}

private fun jsonObject(preview: String): JsonObject? = try {
    Json.parseToJsonElement(preview) as? JsonObject
} catch (_: IllegalArgumentException) {
    // SerializationException (malformed JSON) is an IllegalArgumentException.
    null
}

private fun text(value: JsonElement): String =
    if (value is JsonPrimitive && value.isString) value.content else sortedKeys(value).toString()

private fun sortedKeys(value: JsonElement): JsonElement = when (value) {
    is JsonObject -> JsonObject(value.entries.sortedBy { it.key }.associate { it.key to sortedKeys(it.value) })
    is JsonArray -> JsonArray(value.map(::sortedKeys))
    else -> value
}

private fun tellingValue(preview: String): String {
    val obj = jsonObject(preview) ?: return preview
    for (key in TELLING) {
        val value = obj[key] as? JsonPrimitive ?: continue
        if (value.isString && value.content.isNotEmpty()) return value.content
    }
    return preview
}
