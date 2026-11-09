package com.shellx.link.account

import com.shellx.link.core.RelayException
import java.io.IOException
import java.net.URI
import java.nio.charset.CharacterCodingException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody

/**
 * Runs the call and returns its response with the body already read into memory. The body is read on OkHttp's thread,
 * so a slow body never blocks the caller and is abandoned with the call. Cancelling the caller cancels the call.
 */
internal suspend fun Call.await(): Response = suspendCancellableCoroutine { continuation ->
    continuation.invokeOnCancellation { cancel() }
    enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) {
            continuation.resumeWithException(e)
        }

        override fun onResponse(call: Call, response: Response) {
            // OkHttp drops whatever this callback throws, which would leave the caller waiting forever.
            val buffered = try {
                response.use { it.newBuilder().body(it.body.bytes().toResponseBody(it.body.contentType())).build() }
            } catch (e: Throwable) {
                continuation.resumeWithException(e)
                return
            }
            continuation.resume(buffered)
        }
    })
}

/**
 * The OkHttp URL for [uri], which the caller has already checked with the URL policy. `ws` and `wss` become `http` and
 * `https`. OkHttp parses URLs on its own; when it finds another scheme or host than `java.net.URI` did, the URL is
 * refused, so the host the policy checked is the host OkHttp connects to.
 */
internal fun URI.toCheckedHttpUrl(): HttpUrl {
    val checkedScheme = when (val s = scheme?.lowercase()) {
        "ws" -> "http"
        "wss" -> "https"
        else -> s
    }
    val checkedHost = host?.removeSurrounding("[", "]") ?: throw RelayException.ProtocolViolation("URL is invalid")
    val url = "$checkedScheme:${rawSchemeSpecificPart}".toHttpUrlOrNull()
    if (url == null || url.scheme != checkedScheme || !url.host.equals(checkedHost, ignoreCase = true)) {
        throw RelayException.ProtocolViolation("URL is invalid")
    }
    return url
}

/** Ids go into URL paths: accept only what the relay issues (UUIDs and the like), 1–64 of `[0-9A-Za-z_-]`. */
internal fun isSafeSegment(id: String): Boolean =
    id.length in 1..64 && id.all { it in '0'..'9' || it in 'A'..'Z' || it in 'a'..'z' || it == '-' || it == '_' }

/**
 * A JSON object from the relay, read strictly: each reader throws [RelayApiException.BadResponse] when its field is
 * missing, `null` or of another JSON type.
 */
internal class ApiJson private constructor(private val o: JsonObject) {
    fun str(name: String): String {
        val p = o[name] as? JsonPrimitive ?: bad()
        if (!p.isString) bad()
        return p.content
    }

    fun long(name: String): Long {
        val p = o[name] as? JsonPrimitive ?: bad()
        if (p.isString || !INTEGER.matches(p.content)) bad()
        return p.content.toLongOrNull() ?: bad()
    }

    fun bool(name: String): Boolean {
        val p = o[name] as? JsonPrimitive ?: bad()
        if (p.isString) bad()
        return when (p.content) {
            "true" -> true
            "false" -> false
            else -> bad()
        }
    }

    /** An array whose elements are all objects. */
    fun array(name: String): List<ApiJson> {
        val a = o[name] as? JsonArray ?: bad()
        return a.map { ApiJson(it as? JsonObject ?: bad()) }
    }

    fun obj(name: String): ApiJson = optObj(name) ?: bad()

    /** Null when the field is missing or `null`. */
    fun optObj(name: String): ApiJson? = when (val e = o[name]) {
        null, JsonNull -> null
        is JsonObject -> ApiJson(e)
        else -> bad()
    }

    companion object {
        private val INTEGER = Regex("-?(0|[1-9][0-9]*)")
        private val NUMBER = Regex("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?")

        /** The body as a JSON object, or [RelayApiException.BadResponse]. */
        fun parse(bytes: ByteArray): ApiJson = parseOrNull(bytes) ?: bad()

        /**
         * The body as a JSON object, or null when it is not strict UTF-8, not JSON, or not an object. kotlinx keeps any
         * bare token (`nope`, `01`, `NaN`) as a literal, so every non-string literal must also be `true`, `false`,
         * `null` or a JSON number, as in link-core's codec.
         */
        fun parseOrNull(bytes: ByteArray): ApiJson? {
            val text = try {
                bytes.decodeToString(throwOnInvalidSequence = true)
            } catch (_: CharacterCodingException) {
                return null
            }
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
                    is JsonPrimitive ->
                        if (!e.isString && e.content != "true" && e.content != "false" && !NUMBER.matches(e.content)) {
                            return null
                        }
                }
            }
            return (root as? JsonObject)?.let(::ApiJson)
        }

        private fun bad(): Nothing = throw RelayApiException.BadResponse()
    }
}
