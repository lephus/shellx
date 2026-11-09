package com.shellx.link.account

import com.shellx.link.core.PairingOffer
import com.shellx.link.core.RelayException
import com.shellx.link.core.RelaySocketFactory
import com.shellx.link.core.RelayTicket
import com.shellx.link.core.RelayTransportPolicy
import java.net.URI
import java.net.URISyntaxException
import java.util.Base64
import java.util.concurrent.TimeUnit
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * The phone's side of the ShellX relay HTTP API: pairing (`/v2/phone-pairings`), grants (`/v2/phone-grants`) and
 * connect tickets (`/v2/relay/tickets`). `*_b64` request fields are standard base64.
 *
 * [baseUrl] must be `https`, or `http` to a loopback host ([RelayException.InsecureTransport] otherwise;
 * [RelayException.ProtocolViolation] for a URL that does not parse). Routes are joined under its path once, with or
 * without a trailing slash. Redirects are never followed: a 3xx is a [RelayApiException.Http]. Every call throws
 * [RelayApiException], or the transport's `IOException` unchanged.
 *
 * The API derives its own client from [okHttpClient] (`newBuilder()`), so it keeps that client's interceptors: never
 * pass one with a header or body logging interceptor, which would log bearer tokens.
 */
class RelayApi(val baseUrl: String, okHttpClient: OkHttpClient, private val clientVersion: String) {
    private val base: HttpUrl
    private val http: OkHttpClient

    /** Relay sockets over this API's client: no redirects, the same connect and write timeouts. */
    val relaySockets: RelaySocketFactory

    init {
        val uri = try {
            URI(baseUrl)
        } catch (_: URISyntaxException) {
            throw RelayException.ProtocolViolation("URL is invalid")
        }
        RelayTransportPolicy.requireHttps(uri)
        base = uri.toCheckedHttpUrl()
        // A redirect could carry the bearer token to another host: never follow one.
        http = okHttpClient.newBuilder()
            .followRedirects(false)
            .followSslRedirects(false)
            .connectTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .writeTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .build()
        relaySockets = OkHttpRelaySockets(http)
    }

    /** Asks the machine in [offer] to approve this phone; returns the pairing id to poll. */
    suspend fun requestPairing(offer: PairingOffer, clientKey: ByteArray, token: String): String {
        val body = buildJsonObject {
            put("machine_id", offer.machineId)
            put("client_key_b64", Base64.getEncoder().encodeToString(clientKey))
            put("proof_b64", Base64.getEncoder().encodeToString(offer.proof(clientKey)))
        }
        val id = sendJson("POST", "/v2/phone-pairings", token, body).str("pairing_id")
        if (!isSafeSegment(id)) throw RelayApiException.BadResponse()
        return id
    }

    suspend fun pairingStatus(id: String, token: String): PhonePairingStatus {
        requireSafe(id)
        val reply = sendJson("GET", "/v2/phone-pairings/$id", token, null)
        return when (reply.str("status")) {
            "pending" -> PhonePairingStatus.Pending
            "denied" -> PhonePairingStatus.Denied
            "expired" -> PhonePairingStatus.Expired
            "approved" -> {
                val machine = reply.obj("machine")
                PhonePairingStatus.Approved(machine.str("machine_id"), machine.str("name"), machine.str("link_slot"))
            }
            else -> throw RelayApiException.BadResponse()
        }
    }

    /** Withdraws a pending pairing request (`POST /v2/phone-pairings/<id>/deny`, which the sending phone may call). */
    suspend fun cancelPairing(id: String, token: String) {
        requireSafe(id)
        send("POST", "/v2/phone-pairings/$id/deny", token, null)
    }

    /** The machines this phone was approved for. */
    suspend fun machines(token: String): List<PairedMachineListing> =
        sendJson("GET", "/v2/phone-grants", token, null).array("grants").map {
            PairedMachineListing(
                grantId = it.str("grant_id"),
                machineId = it.str("machine_id"),
                name = it.str("name"),
                platform = it.str("platform"),
                online = it.bool("online"),
                linkSlot = it.str("link_slot"),
                fingerprint = it.str("fingerprint"),
            )
        }

    /**
     * Mints a link-lane connect ticket for [machineId]. The ticket must carry the `connect` permission
     * ([RelayApiException.NotConnectTicket]) and be for [expectedSlot], the slot pinned at pairing
     * ([RelayApiException.SlotMismatch]).
     */
    suspend fun mintConnectTicket(machineId: String, expectedSlot: String, token: String): MintedTicket {
        val body = buildJsonObject {
            put("permission", "connect")
            put("lane", "link")
            put("target_machine_id", machineId)
        }
        val reply = sendJson("POST", "/v2/relay/tickets", token, body)
        val ticket = RelayTicket(reply.str("ticket"), reply.long("expires_at_unix"))
        val relayUrl = try {
            URI(reply.str("relay_url"))
        } catch (_: URISyntaxException) {
            null
        }
        val claims = ticket.claims
        if (claims == null || relayUrl?.host == null) throw RelayApiException.BadResponse()
        if (claims.permission != "connect") throw RelayApiException.NotConnectTicket()
        if (claims.slot != expectedSlot) throw RelayApiException.SlotMismatch()
        return MintedTicket(ticket, relayUrl)
    }

    /** Removes this phone's access to a machine. */
    suspend fun unpair(grantId: String, token: String) {
        requireSafe(grantId)
        send("DELETE", "/v2/phone-grants/$grantId", token, null)
    }

    // Account (contracts §2, §5, §8). Android has no password login, no Apple sign-in and no Google link.

    /** A fresh single-use nonce for the next sign-in: 1–128 characters of the base64url alphabet. */
    suspend fun nonce(): String {
        val nonce = sendJson("POST", "/v1/auth/nonce", null, JsonObject(emptyMap())).str("nonce")
        if (nonce.length !in 1..128 || !nonce.all { it in '0'..'9' || it in 'A'..'Z' || it in 'a'..'z' || it == '-' || it == '_' }) {
            throw RelayApiException.BadResponse()
        }
        return nonce
    }

    /** Signs this phone in with a Google ID token minted for [nonce]; [clientKey] is the phone's Noise public key. */
    suspend fun signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: ByteArray): AccountSignIn {
        val body = buildJsonObject {
            put("id_token", idToken)
            put("nonce", nonce)
            put(
                "device",
                buildJsonObject {
                    put("kind", "mobile")
                    put("name", deviceName)
                    put("platform", "android")
                    put("public_key", Base64.getUrlEncoder().withoutPadding().encodeToString(clientKey))
                },
            )
        }
        val reply = sendJson("POST", "/v1/auth/google", null, body)
        return AccountSignIn(AccountSession(reply.str("user_id"), reply.str("device_id"), reply.str("token")), reply.str("email"))
    }

    /** Deletes the account, proven by a fresh ID token of its identity (`DELETE /v1/account`). */
    suspend fun deleteAccount(idToken: String, nonce: String, token: String) {
        val body = buildJsonObject {
            put("id_token", idToken)
            put("nonce", nonce)
        }
        send("DELETE", "/v1/account", token, body)
    }

    /** Gives the relay this phone's FCM registration token, so paired Macs can reach it while the app is closed. */
    suspend fun setPushToken(fcmToken: String, token: String) {
        val body = buildJsonObject {
            put("token", fcmToken)
            put("platform", "android")
        }
        send("PUT", "/v1/devices/me/push-token", token, body)
    }

    /** Removes this phone's push token from the relay. */
    suspend fun unsetPushToken(token: String) {
        send("DELETE", "/v1/devices/me/push-token", token, null)
    }

    /** Signs this phone out: the relay deletes the token and this device's push token. */
    suspend fun logout(token: String) {
        send("POST", "/v1/auth/logout", token, null)
    }

    // Transport

    internal suspend fun sendJson(method: String, path: String, token: String?, body: JsonObject?): ApiJson =
        ApiJson.parse(send(method, path, token, body))

    /** The 2xx body. Any other status is [RelayApiException.Http]. */
    internal suspend fun send(method: String, path: String, token: String?, body: JsonObject?): ByteArray {
        val url = base.newBuilder().addPathSegments(path.removePrefix("/")).build()
        val request = Request.Builder()
            .url(url)
            .header("X-ShellX-Version", clientVersion)
            .header("Accept", "application/json")
            .apply { if (token != null) header("Authorization", "Bearer $token") }
            .method(method, requestBody(method, body))
            .build()
        val response = http.newCall(request).await()
        val bytes = response.body.bytes()
        if (response.code !in 200..299) throw RelayApiException.Http(response.code, errorCode(bytes))
        return bytes
    }

    private fun requestBody(method: String, body: JsonObject?): RequestBody? = when {
        body != null -> body.toString().encodeToByteArray().toRequestBody(JSON)
        method == "POST" || method == "PUT" -> ByteArray(0).toRequestBody(null)
        else -> null
    }

    private fun errorCode(bytes: ByteArray): String = try {
        ApiJson.parseOrNull(bytes)?.obj("error")?.str("code")
    } catch (_: RelayApiException.BadResponse) {
        null
    } ?: "unknown"

    private fun requireSafe(id: String) {
        if (!isSafeSegment(id)) throw RelayApiException.BadResponse()
    }

    private companion object {
        const val TIMEOUT_SECONDS = 15L
        val JSON = "application/json".toMediaType()
    }
}
