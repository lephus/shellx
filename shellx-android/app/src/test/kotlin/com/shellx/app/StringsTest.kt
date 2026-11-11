package com.shellx.app

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment

@RunWith(AndroidJUnit4::class)
class StringsTest {
    private fun text(id: Int, language: String): String {
        RuntimeEnvironment.setQualifiers("+$language")
        return ApplicationProvider.getApplicationContext<Context>().getString(id)
    }

    @Test
    fun androidWordingNamesNoApplePlatform() {
        for (id in listOf(R.string.signin_subtitle, R.string.signin_error_reauth_required, R.string.settings_account_delete_message)) {
            for (language in listOf("en", "vi")) {
                val value = text(id, language)
                for (word in listOf("iPhone", "Apple", "App Store")) assertFalse(value, value.contains(word))
            }
        }
    }

    @Test
    fun theDeletionPathReadsAsOnTheWebsite() { // contracts §12: "Settings › Account › Delete Account…"
        assertEquals(
            listOf("Settings", "Account", "Delete Account…"),
            listOf(R.string.settings_title, R.string.settings_account_title, R.string.settings_account_delete).map { text(it, "en") },
        )
        assertEquals(
            listOf("Cài đặt", "Tài khoản", "Xoá tài khoản…"),
            listOf(R.string.settings_title, R.string.settings_account_title, R.string.settings_account_delete).map { text(it, "vi") },
        )
    }

    @Test
    fun androidOnlyStringsHaveVietnamese() {
        for (id in listOf(R.string.nav_back, R.string.row_actions, R.string.action_open_agent, R.string.action_open_your_macs)) {
            assertNotEquals(text(id, "en"), text(id, "vi"))
        }
    }

    @Test
    fun theDemoAndSignInStringsCameOver() {
        assertEquals("Continue with Google", text(R.string.signin_google, "en"))
        assertEquals("Xem thử không cần tài khoản", text(R.string.signin_demo, "vi"))
        assertEquals("Thoát", text(R.string.demo_banner_exit, "vi"))
    }

    /** A string with one argument, as the app formats it. */
    private fun text(id: Int, language: String, argument: Any): String {
        RuntimeEnvironment.setQualifiers("+$language")
        return ApplicationProvider.getApplicationContext<Context>().getString(id, argument)
    }

    @Test
    fun theEmailSignInStringsCameOver() {
        assertEquals("Continue with email", text(R.string.signin_email_continue, "en"))
        assertEquals("Resend code in 42 s", text(R.string.signin_email_resend_in, "en", 42))
        assertTrue(
            text(R.string.signin_email_sent_to, "en", "phu@example.com").startsWith("We sent a 6-digit code to phu@example.com."),
        )
        assertEquals("Email code", text(R.string.settings_account_method_email, "en"))

        assertEquals("hoặc", text(R.string.signin_email_or, "vi"))
        assertEquals("Gửi lại mã sau 42 giây", text(R.string.signin_email_resend_in, "vi", 42))
        assertEquals("Xác nhận", text(R.string.signin_email_verify, "vi"))

        val plain = listOf(
            R.string.signin_email_continue, R.string.signin_email_or, R.string.signin_email_field, R.string.signin_email_send,
            R.string.signin_email_code, R.string.signin_email_verify, R.string.signin_email_resend, R.string.signin_email_change,
            R.string.signin_error_invalid_email, R.string.signin_error_disposable_email, R.string.signin_error_invalid_code,
            R.string.signin_error_code_expired, R.string.signin_error_email_send_failed, R.string.settings_account_method_email,
            R.string.settings_account_delete_code_intro, R.string.settings_account_delete_code_field,
        )
        val texts = plain.map { text(it, "en") to text(it, "vi") } + listOf(
            text(R.string.signin_email_sent_to, "en", "phu@example.com") to text(R.string.signin_email_sent_to, "vi", "phu@example.com"),
            text(R.string.signin_email_resend_in, "en", 42) to text(R.string.signin_email_resend_in, "vi", 42),
        )
        assertEquals(18, texts.size)
        for ((english, vietnamese) in texts) {
            assertTrue(english, english.isNotEmpty() && vietnamese.isNotEmpty())
            assertNotEquals(english, vietnamese)
        }
    }

    @Test
    fun theSubtitleNamesBothWaysIn() {
        for (language in listOf("en", "vi")) {
            val subtitle = text(R.string.signin_subtitle, language)
            assertTrue(subtitle, subtitle.contains("email"))
            assertTrue(subtitle, subtitle.contains("Google"))
        }
    }
}
