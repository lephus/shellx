package com.shellx.core.storage

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.longOrNull

/** Encodes and decodes one stored document. [decode] throws on anything it cannot read (the store then treats the
 *  file as corrupt). */
interface JsonCodec<T> {
    fun encode(value: T): JsonElement

    fun decode(json: JsonElement): T
}

// Strict readers for the codecs: a missing field or one of the wrong type throws IllegalArgumentException, whose
// message names the field (never its value).

internal fun JsonElement.obj(what: String): JsonObject = this as? JsonObject ?: throw IllegalArgumentException("not an object: $what")

internal fun JsonElement.array(what: String): JsonArray = this as? JsonArray ?: throw IllegalArgumentException("not an array: $what")

internal fun JsonObject.field(key: String): JsonElement = this[key] ?: throw IllegalArgumentException("missing $key")

internal fun JsonObject.string(key: String): String {
    val value = field(key) as? JsonPrimitive
    require(value != null && value.isString) { "not a string: $key" }
    return value.content
}

internal fun JsonObject.optString(key: String): String? {
    val value = this[key] ?: return null
    if (value is JsonNull) return null
    require(value is JsonPrimitive && value.isString) { "not a string: $key" }
    return value.content
}

internal fun JsonElement.longValue(what: String): Long {
    val value = this as? JsonPrimitive
    require(value != null && !value.isString) { "not a number: $what" }
    return value.longOrNull ?: throw IllegalArgumentException("not an integer: $what")
}

internal fun JsonObject.long(key: String): Long = field(key).longValue(key)

internal fun JsonObject.optLong(key: String): Long? {
    val value = this[key] ?: return null
    if (value is JsonNull) return null
    return value.longValue(key)
}

internal fun JsonObject.bool(key: String): Boolean = optBool(key) ?: throw IllegalArgumentException("missing $key")

internal fun JsonObject.optBool(key: String): Boolean? {
    val value = this[key] ?: return null
    if (value is JsonNull) return null
    require(value is JsonPrimitive && !value.isString) { "not a boolean: $key" }
    return value.booleanOrNull ?: throw IllegalArgumentException("not a boolean: $key")
}
