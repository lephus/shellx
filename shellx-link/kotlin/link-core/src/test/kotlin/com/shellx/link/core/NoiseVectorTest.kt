package com.shellx.link.core

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class NoiseVectorTest {
    @Test
    fun matchesSnowVectors() {
        val v = Vectors.noise
        fun JsonObject.hex(key: String) = Vectors.hex(getValue(key).jsonPrimitive.content)
        fun party(name: String) = v.getValue(name).jsonObject
        assertEquals(NoiseHandshake.PROTOCOL_NAME, v.getValue("protocol").jsonPrimitive.content)
        assertContentEquals(NoiseHandshake.PROLOGUE, v.hex("prologue"))
        val keys = listOf("initiator", "responder").associateWith { p ->
            NoiseStaticKey.fromPrivate(party(p).hex("static_private")) to NoiseStaticKey.fromPrivate(party(p).hex("ephemeral_private"))
        }
        for ((p, pair) in keys) {
            assertContentEquals(party(p).hex("static_public"), pair.first.publicKey)
            assertContentEquals(party(p).hex("ephemeral_public"), pair.second.publicKey)
        }
        val initiator = NoiseHandshake(NoiseRole.INITIATOR, keys.getValue("initiator").first, { true }, keys.getValue("initiator").second)
        val responder = NoiseHandshake(NoiseRole.RESPONDER, keys.getValue("responder").first, { true }, keys.getValue("responder").second)
        val steps = v.getValue("handshake").jsonArray.map { it.jsonObject }
        assertEquals(3, steps.size)
        steps.forEachIndexed { i, step ->
            val initiatorSends = i % 2 == 0
            assertEquals(if (initiatorSends) "initiator" else "responder", step.getValue("sender").jsonPrimitive.content)
            val (writer, reader) = if (initiatorSends) initiator to responder else responder to initiator
            val message = writer.writeMessage(step.hex("payload"))
            assertEquals(step.getValue("ciphertext").jsonPrimitive.content, message.toHex(), "handshake message ${i + 1}")
            assertContentEquals(step.hex("payload"), reader.readMessage(message))
        }
        assertTrue(initiator.isComplete && responder.isComplete)
        assertContentEquals(party("responder").hex("static_public"), initiator.remoteStatic)
        assertContentEquals(party("initiator").hex("static_public"), responder.remoteStatic)
        assertEquals(v.getValue("handshake_hash").jsonPrimitive.content, initiator.handshakeHash.toHex())
        assertEquals(v.getValue("handshake_hash").jsonPrimitive.content, responder.handshakeHash.toHex())
        val iT = initiator.split()
        val rT = responder.split()
        val transport = v.getValue("transport").jsonObject
        for ((key, pair) in listOf("initiator_to_responder" to (iT to rT), "responder_to_initiator" to (rT to iT))) {
            for (m in transport.getValue(key).jsonArray.map { it.jsonObject }) {
                assertEquals(m.getValue("ciphertext").jsonPrimitive.content, pair.first.encrypt(m.hex("payload")).toHex())
                assertContentEquals(m.hex("payload"), pair.second.decrypt(m.hex("ciphertext")))
            }
        }
    }
}
