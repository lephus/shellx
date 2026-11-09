package com.shellx.link.account

import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Test

class RelayApiAccountTest {
    private val clientKey = ByteArray(32) { (0x20 + it).toByte() }
    private val signInReply = """{"user_id":"u1","device_id":"d1","token":"tok-secret","email":"a@b.c"}"""

    @Test
    fun nonceIsAskedWithAnEmptyObject() {
        runBlocking {
            ApiServer().use { s ->
                val nonce = "aB3_-".repeat(8) + "xyz"
                s.reply(201, """{"nonce":"$nonce","expires_in":600}""")
                assertEquals(nonce, s.api().nonce())
                val request = s.take()
                assertEquals("POST", request.method)
                assertEquals("/v1/auth/nonce", request.url.encodedPath)
                assertEquals("{}", request.body?.utf8())
                assertEquals("application/json", request.headers["Content-Type"])
                assertNull(request.headers["Authorization"])
                s.reply(201, "{}")
                assertFailsWith<RelayApiException.BadResponse> { s.api().nonce() }
            }
        }
    }

    @Test
    fun nonceOutsideBase64UrlIsRefused() {
        runBlocking {
            ApiServer().use { s ->
                for (bad in listOf("", "has space", "slash/es", "a".repeat(129), "plus+")) {
                    s.reply(201, """{"nonce":"$bad","expires_in":600}""")
                    assertFailsWith<RelayApiException.BadResponse>(bad) { s.api().nonce() }
                }
                s.reply(201, """{"nonce":7,"expires_in":600}""")
                assertFailsWith<RelayApiException.BadResponse> { s.api().nonce() }
            }
        }
    }

    @Test
    fun signInWithGoogleSendsTheAndroidDevice() {
        runBlocking {
            ApiServer().use { s ->
                s.reply(200, signInReply)
                val signIn = s.api().signInWithGoogle("id-1", "n-1", "Pixel 9", clientKey)
                assertEquals(AccountSignIn(AccountSession("u1", "d1", "tok-secret"), "a@b.c"), signIn)
                assertFalse(signIn.session.toString().contains("tok-secret"))
                assertFalse(signIn.toString().contains("tok-secret") || signIn.toString().contains("a@b.c"))
                val request = s.take()
                assertEquals("POST", request.method)
                assertEquals("/v1/auth/google", request.url.encodedPath)
                assertNull(request.headers["Authorization"])
                val body = request.json()
                assertEquals(setOf("id_token", "nonce", "device"), body.keys)
                assertEquals("id-1", body.text("id_token"))
                assertEquals("n-1", body.text("nonce"))
                val device = body["device"] as JsonObject
                assertEquals(
                    mapOf(
                        "kind" to "mobile",
                        "name" to "Pixel 9",
                        "platform" to "android",
                        "public_key" to "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8",
                    ),
                    device.keys.associateWith { device.text(it) },
                )
            }
        }
    }

    @Test
    fun signInNeedsEveryReplyField() {
        runBlocking {
            ApiServer().use { s ->
                for (reply in listOf(
                    """{"user_id":"u1","device_id":"d1","token":"t"}""",
                    """{"user_id":"u1","device_id":"d1","token":null,"email":"a@b.c"}""",
                    """{"user_id":1,"device_id":"d1","token":"t","email":"a@b.c"}""",
                )) {
                    s.reply(200, reply)
                    assertFailsWith<RelayApiException.BadResponse>(reply) { s.api().signInWithGoogle("i", "n", "p", clientKey) }
                }
            }
        }
    }

    @Test
    fun signInErrorsSurface() {
        runBlocking {
            ApiServer().use { s ->
                for ((status, code) in listOf(
                    401 to "invalid_credentials",
                    409 to "switch_from_signed_in_device",
                    400 to "invalid_device",
                    429 to "rate_limited",
                )) {
                    s.reply(status, """{"error":{"code":"$code","message":"x"}}""")
                    assertEquals(
                        RelayApiException.Http(status, code),
                        assertFailsWith<RelayApiException.Http> { s.api().signInWithGoogle("i", "n", "p", clientKey) },
                    )
                }
            }
        }
    }

    @Test
    fun deleteAccountSendsTheFreshIdToken() {
        runBlocking {
            ApiServer().use { s ->
                s.reply(204)
                s.api().deleteAccount("fresh-id", "n-2", "tok")
                val request = s.take()
                assertEquals("DELETE", request.method)
                assertEquals("/v1/account", request.url.encodedPath)
                assertEquals("Bearer tok", request.headers["Authorization"])
                assertEquals("""{"id_token":"fresh-id","nonce":"n-2"}""", request.body?.utf8())
                s.reply(401, """{"error":{"code":"reauth_required","message":"x"}}""")
                assertEquals(
                    RelayApiException.Http(401, "reauth_required"),
                    assertFailsWith<RelayApiException.Http> { s.api().deleteAccount("old-id", "n-3", "tok") },
                )
            }
        }
    }

    @Test
    fun setPushTokenPutsTheAndroidToken() {
        runBlocking {
            ApiServer().use { s ->
                s.reply(204)
                s.api().setPushToken("fcm-1", "tok")
                val request = s.take()
                assertEquals("PUT", request.method)
                assertEquals("/v1/devices/me/push-token", request.url.encodedPath)
                assertEquals("Bearer tok", request.headers["Authorization"])
                assertEquals("""{"token":"fcm-1","platform":"android"}""", request.body?.utf8())
            }
        }
    }

    @Test
    fun unsetPushTokenDeletes() {
        runBlocking {
            ApiServer().use { s ->
                s.reply(204)
                s.api().unsetPushToken("tok")
                val request = s.take()
                assertEquals("DELETE", request.method)
                assertEquals("/v1/devices/me/push-token", request.url.encodedPath)
                assertEquals("Bearer tok", request.headers["Authorization"])
                assertEquals(0L, request.bodySize)
            }
        }
    }

    @Test
    fun logoutPostsBearer() {
        runBlocking {
            ApiServer().use { s ->
                s.reply(204)
                s.api().logout("tok")
                val request = s.take()
                assertEquals("POST", request.method)
                assertEquals("/v1/auth/logout", request.url.encodedPath)
                assertEquals("Bearer tok", request.headers["Authorization"])
                assertEquals(0L, request.bodySize)
                s.reply(500)
                assertEquals(RelayApiException.Http(500, "unknown"), assertFailsWith<RelayApiException.Http> { s.api().logout("tok") })
            }
        }
    }

    @Test
    fun publicKeyUsesTheBase64UrlAlphabet() {
        runBlocking {
            ApiServer().use { s ->
                // Standard base64 of this key starts with "+/+/" and ends with "=".
                val key = byteArrayOf(0xFB.toByte(), 0xFF.toByte(), 0xBF.toByte()) + ByteArray(29)
                s.reply(200, signInReply)
                s.api().signInWithGoogle("i", "n", "p", key)
                val device = s.take().json()["device"] as JsonObject
                assertEquals("-_-_" + "A".repeat(39), device.text("public_key"))
            }
        }
    }
}
