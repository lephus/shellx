package com.shellx.link.core

import java.nio.charset.CharacterCodingException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// Strict JSON field readers shared by the Link codec and the relay control codec. Each reader throws
// FieldError when a field is missing or has the wrong JSON type. A `null` value counts as absent for an
// optional field and as wrong for a required one (PROTOCOL.md section 3).

/** A field is missing or malformed. Callers turn it into their own error. */
internal class FieldError : Exception()

private val INTEGER = Regex("-?(0|[1-9][0-9]*)")
private val UNSIGNED = Regex("0|[1-9][0-9]*")
private val NUMBER = Regex("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?")

/** UTF-8 bytes to a JSON element, or null when the bytes are not strict UTF-8 or not JSON. */
internal fun parseJsonOrNull(bytes: ByteArray): JsonElement? {
    val text = try {
        bytes.decodeToString(throwOnInvalidSequence = true)
    } catch (_: CharacterCodingException) {
        return null
    }
    return parseJsonOrNull(text)
}

/**
 * JSON text to an element, or null when it is not JSON. kotlinx keeps any bare token (`nope`, `01`, `NaN`) as a
 * literal, so every non-string literal must also be `true`, `false`, `null` or a JSON number.
 */
internal fun parseJsonOrNull(text: String): JsonElement? {
    val root = try {
        Json.parseToJsonElement(text)
    } catch (_: IllegalArgumentException) {
        return null
    }
    val pending = ArrayDeque<JsonElement>()
    pending.addLast(root)
    while (pending.isNotEmpty()) {
        when (val e = pending.removeLast()) {
            is JsonObject -> pending.addAll(e.values)
            is JsonArray -> pending.addAll(e)
            is JsonNull -> Unit
            is JsonPrimitive -> if (!e.isString && e.content != "true" && e.content != "false" && !NUMBER.matches(e.content)) {
                return null
            }
        }
    }
    return root
}

/** A JSON integer token: a non-string primitive without fraction or exponent. */
internal fun JsonElement.isIntegerToken(): Boolean =
    this is JsonPrimitive && this !is JsonNull && !isString && INTEGER.matches(content)

private fun JsonElement?.present(): JsonElement? = if (this == null || this is JsonNull) null else this

internal fun JsonElement.asStr(): String {
    val p = this as? JsonPrimitive ?: throw FieldError()
    if (!p.isString) throw FieldError()
    return p.content
}

internal fun JsonElement.asLong(): Long {
    if (!isIntegerToken()) throw FieldError()
    return (this as JsonPrimitive).content.toLongOrNull() ?: throw FieldError()
}

internal fun JsonElement.asInt(): Int {
    if (!isIntegerToken()) throw FieldError()
    return (this as JsonPrimitive).content.toIntOrNull() ?: throw FieldError()
}

internal fun JsonElement.asULong(): ULong {
    val p = this as? JsonPrimitive ?: throw FieldError()
    if (p is JsonNull || p.isString || !UNSIGNED.matches(p.content)) throw FieldError()
    return p.content.toULongOrNull() ?: throw FieldError()
}

internal fun JsonElement.asBool(): Boolean {
    val p = this as? JsonPrimitive ?: throw FieldError()
    if (p is JsonNull || p.isString) throw FieldError()
    return when (p.content) {
        "true" -> true
        "false" -> false
        else -> throw FieldError()
    }
}

internal fun JsonElement.asArray(): JsonArray = this as? JsonArray ?: throw FieldError()

internal fun JsonElement.asObj(): JsonObject = this as? JsonObject ?: throw FieldError()

private fun JsonObject.required(key: String): JsonElement = get(key) ?: throw FieldError()

internal fun JsonObject.str(key: String): String = required(key).asStr()
internal fun JsonObject.optStr(key: String): String? = get(key).present()?.asStr()
internal fun JsonObject.long(key: String): Long = required(key).asLong()
internal fun JsonObject.optLong(key: String): Long? = get(key).present()?.asLong()
internal fun JsonObject.int(key: String): Int = required(key).asInt()

/**
 * A JSON integer of up to 64 bits, held at Int's limits. For fields Swift reads as a 64-bit Int and checks only
 * against small limits (a terminal frame's): a value past Int's range passes or breaks each such limit just as the
 * held value does, so both apps accept and refuse the same frames. Past 64 bits it is a [FieldError], as in Swift.
 */
internal fun JsonObject.wideInt(key: String): Int = long(key).toIntHeld()
internal fun JsonObject.optWideInt(key: String): Int? = optLong(key)?.toIntHeld()

private fun Long.toIntHeld(): Int = coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()
internal fun JsonObject.uLong(key: String): ULong = required(key).asULong()
internal fun JsonObject.bool(key: String): Boolean = required(key).asBool()
internal fun JsonObject.optBool(key: String): Boolean? = get(key).present()?.asBool()
internal fun JsonObject.array(key: String): JsonArray = required(key).asArray()
internal fun JsonObject.optArray(key: String): JsonArray? = get(key).present()?.asArray()
internal fun JsonObject.obj(key: String): JsonObject = required(key).asObj()
internal fun JsonObject.optObj(key: String): JsonObject? = get(key).present()?.asObj()

/** Whether [id] is a valid `call_id`: 1 to 64 UTF-8 bytes. */
internal fun isValidCallId(id: String): Boolean = id.utf8Size in 1..LinkCodec.MAX_CALL_ID_BYTES

/** The string when [e] is a valid `call_id`, otherwise null. */
internal fun validCallIdOrNull(e: JsonElement?): String? {
    val p = e as? JsonPrimitive ?: return null
    if (!p.isString) return null
    return p.content.takeIf(::isValidCallId)
}

/** The required `call_id`: a string of 1 to 64 UTF-8 bytes. */
internal fun JsonObject.callId(): String = str("call_id").also { if (!isValidCallId(it)) throw FieldError() }
