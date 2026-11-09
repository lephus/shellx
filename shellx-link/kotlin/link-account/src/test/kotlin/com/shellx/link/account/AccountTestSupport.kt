package com.shellx.link.account

import java.net.InetAddress
import java.util.Base64
import java.util.concurrent.TimeUnit
import kotlin.test.fail
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.RecordedRequest
import okhttp3.OkHttpClient

/** A MockWebServer on 127.0.0.1 that answers the [RelayApi] under test. */
class ApiServer : AutoCloseable {
    val server = MockWebServer().apply { start(InetAddress.getByName("127.0.0.1"), 0) }
    val client: OkHttpClient = OkHttpClient()
    val base: String = "http://127.0.0.1:${server.port}"

    fun api(base: String = this.base, clientVersion: String = "9.9.9"): RelayApi = RelayApi(base, client, clientVersion)

    /** Queues one answer; [json] is sent as `application/json` when it is set. */
    fun reply(status: Int, json: String? = null, location: String? = null) {
        val builder = MockResponse.Builder().code(status)
        if (json != null) builder.addHeader("Content-Type", "application/json").body(json)
        if (location != null) builder.addHeader("Location", location)
        server.enqueue(builder.build())
    }

    /** The next request the server saw, within 5 s. */
    fun take(): RecordedRequest = server.takeRequest(5, TimeUnit.SECONDS) ?: fail("the server saw no request")

    override fun close() {
        server.close()
        client.dispatcher.executorService.shutdown()
        client.connectionPool.evictAll()
    }
}

/** The request body as a JSON object. */
fun RecordedRequest.json(): JsonObject = Json.parseToJsonElement(body?.utf8() ?: "") as JsonObject

/** The string field [name], or null when it is missing or not a string. */
fun JsonObject.text(name: String): String? = (this[name] as? JsonPrimitive)?.takeIf { it.isString }?.content

/** A ticket shaped like the relay's: `v2.<base64url claims>.<signature>` (StubURLProtocol.swift). */
fun stubTicket(slot: String, permission: String = "connect", role: String = "client"): String {
    val claims = buildJsonObject {
        put("slot", slot)
        put("permission", permission)
        put("role", role)
        put("expires_at_unix", 1_900_000_000L)
    }
    val payload = Base64.getUrlEncoder().withoutPadding().encodeToString(claims.toString().encodeToByteArray())
    return "v2.$payload.c2ln"
}

/** Runs [block], failing the test when it takes longer than [timeout]. */
suspend fun <T> within(timeout: Duration = 5.seconds, block: suspend CoroutineScope.() -> T): T = withTimeout(timeout, block)
