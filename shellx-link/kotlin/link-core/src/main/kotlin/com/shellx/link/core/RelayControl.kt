package com.shellx.link.core

import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonUnquotedLiteral
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Errors raised by the relay client. Transport failures before a circuit is ready (connection refused, TLS) surface
 * as the transport's own `IOException`.
 */
sealed class RelayException(message: String) : Exception(message) {
    /** The circuit ended: the peer or this side closed it, or the socket dropped. */
    class Closed : RelayException("closed")

    /** The relay refused an operation with an `error` control message. */
    data class Server(val code: String, val retryable: Boolean) : RelayException(code)

    /** The relay sent something this client does not expect, or a URL is unusable. */
    data class ProtocolViolation(val detail: String) : RelayException(detail)

    /** The URL would send a ticket or token over an unencrypted link to a host that is not loopback. */
    data class InsecureTransport(val scheme: String) : RelayException("insecure_transport")

    /** A control exchange got no answer in time. */
    class TimedOut : RelayException("timed_out")
}

/** Protocol constants of `cmux-relay`. */
object RelayProtocol {
    /** The value the relay requires in the `protocol` field of register, connect and join. */
    const val VERSION = 5

    /** How long a control exchange (register, allocation, join) may wait for its reply. */
    val CONTROL_TIMEOUT: Duration = 10.seconds

    /** Error codes that mean the ticket itself is not acceptable. */
    val AUTHENTICATION_CODES: Set<String> = setOf("unauthorized", "invalid-ticket", "ticket-expired", "registration-expired")
}

/** Which end of a circuit a socket joins as. */
enum class RelayRole(val wire: String) { DAEMON("daemon"), CLIENT("client") }

/** The JSON text messages the relay exchanges, tagged by `type`. Tickets never print. */
sealed interface RelayControl {
    data class Register(val protocol: Int, val slot: String, val ticket: String) : RelayControl {
        override fun toString(): String = "Register(protocol=$protocol, slot=$slot, ticket=<redacted>)"
    }

    data class Registered(val leaseSeconds: Long) : RelayControl

    data class Connect(val protocol: Int, val slot: String, val ticket: String, val lane: String, val generation: ULong) :
        RelayControl {
        override fun toString(): String =
            "Connect(protocol=$protocol, slot=$slot, ticket=<redacted>, lane=$lane, generation=$generation)"
    }

    data class Allocated(val circuit: String, val lane: String, val generation: ULong, val joinTicket: String) : RelayControl {
        override fun toString(): String =
            "Allocated(circuit=$circuit, lane=$lane, generation=$generation, joinTicket=<redacted>)"
    }

    data class Incoming(val circuit: String, val lane: String, val generation: ULong, val joinTicket: String) : RelayControl {
        override fun toString(): String =
            "Incoming(circuit=$circuit, lane=$lane, generation=$generation, joinTicket=<redacted>)"
    }

    data class Join(
        val protocol: Int,
        val slot: String,
        val circuit: String,
        val lane: String,
        val generation: ULong,
        val ticket: String,
        val role: RelayRole,
    ) : RelayControl {
        override fun toString(): String = "Join(protocol=$protocol, slot=$slot, circuit=$circuit, lane=$lane, " +
            "generation=$generation, ticket=<redacted>, role=$role)"
    }

    data class Ready(val circuit: String, val lane: String, val generation: ULong) : RelayControl

    data class Ping(val nonce: ULong) : RelayControl

    data class Pong(val nonce: ULong) : RelayControl

    data class Error(val code: String, val message: String, val retryable: Boolean) : RelayControl

    /** The message as one line of JSON, `type` first, then the fields in declaration order. */
    fun encodeText(): String = Json.encodeToString(JsonObject.serializer(), RelayControlCodec.toJson(this))

    companion object {
        /** Parses one text message. Anything else is `ProtocolViolation("invalid relay control message")`. */
        fun decode(text: String): RelayControl {
            val o = parseJsonOrNull(text) as? JsonObject ?: throw invalid()
            return try {
                RelayControlCodec.fromJson(o) ?: throw invalid()
            } catch (_: FieldError) {
                throw invalid()
            }
        }

        private fun invalid() = RelayException.ProtocolViolation("invalid relay control message")
    }
}

private object RelayControlCodec {
    private const val MAX_UINT32 = 4_294_967_295L

    @OptIn(ExperimentalSerializationApi::class)
    private fun uint64(value: ULong): JsonElement = JsonUnquotedLiteral(value.toString())

    fun toJson(c: RelayControl): JsonObject = buildJsonObject {
        when (c) {
            is RelayControl.Register -> {
                put("type", "register")
                put("protocol", c.protocol)
                put("slot", c.slot)
                put("ticket", c.ticket)
            }
            is RelayControl.Registered -> {
                put("type", "registered")
                put("lease_seconds", c.leaseSeconds)
            }
            is RelayControl.Connect -> {
                put("type", "connect")
                put("protocol", c.protocol)
                put("slot", c.slot)
                put("ticket", c.ticket)
                put("lane", c.lane)
                put("generation", uint64(c.generation))
            }
            is RelayControl.Allocated -> {
                put("type", "allocated")
                put("circuit", c.circuit)
                put("lane", c.lane)
                put("generation", uint64(c.generation))
                put("join_ticket", c.joinTicket)
            }
            is RelayControl.Incoming -> {
                put("type", "incoming")
                put("circuit", c.circuit)
                put("lane", c.lane)
                put("generation", uint64(c.generation))
                put("join_ticket", c.joinTicket)
            }
            is RelayControl.Join -> {
                put("type", "join")
                put("protocol", c.protocol)
                put("slot", c.slot)
                put("circuit", c.circuit)
                put("lane", c.lane)
                put("generation", uint64(c.generation))
                put("ticket", c.ticket)
                put("role", c.role.wire)
            }
            is RelayControl.Ready -> {
                put("type", "ready")
                put("circuit", c.circuit)
                put("lane", c.lane)
                put("generation", uint64(c.generation))
            }
            is RelayControl.Ping -> {
                put("type", "ping")
                put("nonce", uint64(c.nonce))
            }
            is RelayControl.Pong -> {
                put("type", "pong")
                put("nonce", uint64(c.nonce))
            }
            is RelayControl.Error -> {
                put("type", "error")
                put("code", c.code)
                put("message", c.message)
                put("retryable", c.retryable)
            }
        }
    }

    private fun JsonObject.protocol(): Int = int("protocol").also { if (it !in 0..255) throw FieldError() }

    private fun JsonObject.role(): RelayRole {
        val wire = str("role")
        return RelayRole.entries.firstOrNull { it.wire == wire } ?: throw FieldError()
    }

    /** The message of a known `type`, or null for an unknown one. Throws [FieldError]. */
    fun fromJson(o: JsonObject): RelayControl? = when (o.str("type")) {
        "register" -> RelayControl.Register(o.protocol(), o.str("slot"), o.str("ticket"))
        "registered" -> RelayControl.Registered(o.long("lease_seconds").also { if (it !in 0..MAX_UINT32) throw FieldError() })
        "connect" -> RelayControl.Connect(o.protocol(), o.str("slot"), o.str("ticket"), o.str("lane"), o.uLong("generation"))
        "allocated" -> RelayControl.Allocated(o.str("circuit"), o.str("lane"), o.uLong("generation"), o.str("join_ticket"))
        "incoming" -> RelayControl.Incoming(o.str("circuit"), o.str("lane"), o.uLong("generation"), o.str("join_ticket"))
        "join" -> RelayControl.Join(
            o.protocol(), o.str("slot"), o.str("circuit"), o.str("lane"), o.uLong("generation"), o.str("ticket"), o.role(),
        )
        "ready" -> RelayControl.Ready(o.str("circuit"), o.str("lane"), o.uLong("generation"))
        "ping" -> RelayControl.Ping(o.uLong("nonce"))
        "pong" -> RelayControl.Pong(o.uLong("nonce"))
        "error" -> RelayControl.Error(o.str("code"), o.str("message"), o.bool("retryable"))
        else -> null
    }
}
