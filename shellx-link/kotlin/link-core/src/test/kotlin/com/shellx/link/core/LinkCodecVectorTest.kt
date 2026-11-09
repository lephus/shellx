package com.shellx.link.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlin.test.fail
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class LinkCodecVectorTest {
    private val file = Vectors.messages
    private fun entries(section: String) = file.getValue(section).jsonArray.map { it.jsonObject }
    private fun JsonObject.text(key: String) = getValue(key).jsonPrimitive.content
    private fun frame(element: JsonElement) = Json.encodeToString(JsonElement.serializer(), element).encodeToByteArray()

    @Test
    fun vectorsDecodeAndEncodeBack() {
        val seen = mutableSetOf<String>()
        for (v in entries("vectors")) {
            val case = v.getValue("message").jsonObject.text("case")
            val name = v.text("name")
            seen += case
            val expected = VectorMessages.fromVector(v.getValue("message").jsonObject)
            assertEquals(expected, LinkCodec.decode(frame(v.getValue("json"))), name)
            assertEquals(v.getValue("json"), Json.parseToJsonElement(LinkCodec.encode(expected).decodeToString()), name)
        }
        assertEquals(VectorMessages.SENDABLE_CASES, seen)
    }

    @Test
    fun decodeOnlyVectors() {
        val seen = mutableSetOf<String>()
        for (v in entries("decode_only")) {
            val case = v.getValue("message").jsonObject.text("case")
            seen += case
            assertEquals(
                VectorMessages.fromVector(v.getValue("message").jsonObject),
                LinkCodec.decode(frame(v.getValue("json"))),
                v.text("name"),
            )
        }
        assertTrue("unknown" in seen)
    }

    @Test
    fun decodeErrorVectors() {
        for (v in entries("decode_errors")) {
            val name = v.text("name")
            val json = v["json"]?.jsonObject
            val bytes = v["json_text"]?.jsonPrimitive?.content?.encodeToByteArray() ?: frame(json!!)
            val error = assertFailsWith<LinkCodecException>(name) { LinkCodec.decode(bytes) }
            when (v.text("error")) {
                "wrong_version" -> assertIs<LinkCodecException.WrongVersion>(error, name)
                "frame_too_large" -> assertIs<LinkCodecException.FrameTooLarge>(error, name)
                "bad_json" -> assertEquals(LinkCodecException.BadJson(v["call_id"]?.jsonPrimitive?.content), error, name)
                else -> fail("unknown error name in $name")
            }
        }
    }

    @Test
    fun boundaryFrames() {
        val b = file.getValue("boundary_frames").jsonObject
        val cases = b.getValue("cases").jsonArray.map { it.jsonObject }
        assertTrue(cases.size >= 4)
        for (c in cases) {
            val name = c.text("name")
            val filler = c.getValue("filler").jsonArray.joinToString("") {
                it.jsonObject.text("text").repeat(it.jsonObject.getValue("count").jsonPrimitive.int)
            }
            val text = b.text("prefix") + filler + b.text("suffix")
            assertEquals(c.getValue("bytes").jsonPrimitive.int, text.utf8Size, name)
            c["chars"]?.let { assertEquals(it.jsonPrimitive.int, text.codePointCount(0, text.length), name) }
            val message = LinkMessage.Error(code = "x", message = filler)
            when (c.text("result")) {
                "ok" -> {
                    assertEquals(message, LinkCodec.decode(text.encodeToByteArray()), name)
                    assertEquals(text.utf8Size, LinkCodec.encode(message).size, name)
                }
                "frame_too_large" -> {
                    assertFailsWith<LinkCodecException.FrameTooLarge>(name) { LinkCodec.decode(text.encodeToByteArray()) }
                    assertFailsWith<LinkCodecException.FrameTooLarge>(name) { LinkCodec.encode(message) }
                }
                else -> fail("unknown result in $name")
            }
        }
    }
}
