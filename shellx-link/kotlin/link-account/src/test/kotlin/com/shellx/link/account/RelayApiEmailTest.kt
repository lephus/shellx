package com.shellx.link.account

import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Test

/** The relay's email-code calls: asking for a code, signing in with it, and deleting the account with one. */
class RelayApiEmailTest {
    private val clientKey = ByteArray(32) { (0x20 + it).toByte() }
    private val challenge = "aB3_-".repeat(8) + "xyz"
    private val signInReply = """{"user_id":"u1","device_id":"d1","token":"tok-secret","email":"a@b.c"}"""

    private fun codeReply(
        challengeId: String = "\"$challenge\"",
        expiresIn: String = "600",
        resendIn: String = "60",
        email: String? = "\"foo@bar.com\"",
    ): String = buildString {
        append("""{"challenge_id":$challengeId,"expires_in":$expiresIn,"resend_in":$resendIn""")
        if (email != null) append(""","email":$email""")
        append("}")
    }

    private fun error(code: String) = """{"error":{"code":"$code","message":"x"}}"""

    @Test
    fun requestEmailCodeSendsTheEmailAndTheLocale() {
        runBlocking {
            ApiServer().use { s ->
                s.reply(202, codeReply())
                assertEquals(EmailChallenge(challenge, 600, 60, "foo@bar.com"), s.api().requestEmailCode("Foo@Bar.com", "vi"))
                val request = s.take()
                assertEquals("POST", request.method)
                assertEquals("/v1/auth/email/code", request.url.encodedPath)
                assertNull(request.headers["Authorization"])
                assertEquals("""{"email":"Foo@Bar.com","locale":"vi"}""", request.body?.utf8())
            }
        }
    }

    @Test
    fun theChallengeNeverPrints() {
        val printed = EmailChallenge(challenge, 600, 60, "foo@bar.com").toString()
        assertFalse(printed.contains(challenge), printed)
        assertFalse(printed.contains("foo@bar.com"), printed)
        assertEquals("EmailChallenge(expiresIn=600, resendIn=60, <redacted>)", printed)
    }

    @Test
    fun aCodeReplyNeedsEveryFieldInRange() {
        runBlocking {
            ApiServer().use { s ->
                for (reply in listOf(
                    codeReply(email = null),
                    codeReply(challengeId = "7"),
                    codeReply(challengeId = "\"has space\""),
                    codeReply(challengeId = "\"\""),
                    codeReply(challengeId = "\"${"a".repeat(129)}\""),
                    codeReply(expiresIn = "0"),
                    codeReply(expiresIn = "\"600\""),
                    codeReply(resendIn = "-1"),
                    codeReply(resendIn = "86401"),
                )) {
                    s.reply(202, reply)
                    assertFailsWith<RelayApiException.BadResponse>(reply) { s.api().requestEmailCode("a@b.c", "en") }
                }
                // The edges that are in range.
                s.reply(202, codeReply(challengeId = "\"${"a".repeat(128)}\"", expiresIn = "86400", resendIn = "0"))
                assertEquals(EmailChallenge("a".repeat(128), 86_400, 0, "foo@bar.com"), s.api().requestEmailCode("a@b.c", "en"))
            }
        }
    }

    @Test
    fun codeRequestErrorsSurface() {
        runBlocking {
            ApiServer().use { s ->
                for ((status, code) in listOf(
                    400 to "invalid_email",
                    400 to "disposable_email",
                    429 to "rate_limited",
                    503 to "email_sign_in_disabled",
                    502 to "email_send_failed",
                    404 to "not_found",
                )) {
                    s.reply(status, error(code))
                    assertEquals(
                        RelayApiException.Http(status, code),
                        assertFailsWith<RelayApiException.Http> { s.api().requestEmailCode("a@b.c", "en") },
                    )
                }
            }
        }
    }

    @Test
    fun signInWithEmailCodeSendsTheAndroidDevice() {
        runBlocking {
            ApiServer().use { s ->
                s.reply(200, signInReply)
                val signIn = s.api().signInWithEmailCode("c-1", "123456", "Pixel 9", clientKey)
                assertEquals(AccountSignIn(AccountSession("u1", "d1", "tok-secret"), "a@b.c"), signIn)
                val request = s.take()
                assertEquals("POST", request.method)
                assertEquals("/v1/auth/email/verify", request.url.encodedPath)
                assertNull(request.headers["Authorization"])
                val body = request.json()
                assertEquals(setOf("challenge_id", "code", "device"), body.keys)
                assertEquals("c-1", body.text("challenge_id"))
                assertEquals("123456", body.text("code"))
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
    fun verifyNeedsEveryReplyField() {
        runBlocking {
            ApiServer().use { s ->
                for (reply in listOf(
                    """{"user_id":"u1","device_id":"d1","token":"t"}""",
                    """{"user_id":"u1","device_id":"d1","token":null,"email":"a@b.c"}""",
                    """{"user_id":1,"device_id":"d1","token":"t","email":"a@b.c"}""",
                )) {
                    s.reply(200, reply)
                    assertFailsWith<RelayApiException.BadResponse>(reply) { s.api().signInWithEmailCode("c", "123456", "p", clientKey) }
                }
            }
        }
    }

    @Test
    fun verifyErrorsSurface() {
        runBlocking {
            ApiServer().use { s ->
                for ((status, code) in listOf(
                    401 to "invalid_code",
                    410 to "code_expired",
                    409 to "switch_from_signed_in_device",
                    400 to "invalid_device",
                    429 to "rate_limited",
                )) {
                    s.reply(status, error(code))
                    assertEquals(
                        RelayApiException.Http(status, code),
                        assertFailsWith<RelayApiException.Http> { s.api().signInWithEmailCode("c", "123456", "p", clientKey) },
                    )
                }
            }
        }
    }

    @Test
    fun deleteAccountWithEmailCodeSendsTheChallengeAndTheCode() {
        runBlocking {
            ApiServer().use { s ->
                s.reply(204)
                s.api().deleteAccountWithEmailCode("c-1", "123456", "tok")
                val request = s.take()
                assertEquals("DELETE", request.method)
                assertEquals("/v1/account", request.url.encodedPath)
                assertEquals("Bearer tok", request.headers["Authorization"])
                assertEquals("""{"challenge_id":"c-1","code":"123456"}""", request.body?.utf8())
                for ((status, code) in listOf(401 to "invalid_code", 410 to "code_expired", 401 to "reauth_required")) {
                    s.reply(status, error(code))
                    assertEquals(
                        RelayApiException.Http(status, code),
                        assertFailsWith<RelayApiException.Http> { s.api().deleteAccountWithEmailCode("c-1", "123456", "tok") },
                    )
                }
            }
        }
    }
}
