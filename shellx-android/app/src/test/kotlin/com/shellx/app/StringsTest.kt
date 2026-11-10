package com.shellx.app

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
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
}
