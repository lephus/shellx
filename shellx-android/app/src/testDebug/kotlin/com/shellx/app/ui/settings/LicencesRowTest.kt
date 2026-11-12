package com.shellx.app.ui.settings

import android.app.Application
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

/** Settings › About › Licenses opens the open-source licence notices, not shellx.pro (plan 3H; parity ledger). */
@RunWith(AndroidJUnit4::class)
class LicencesRowTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun licensesOpensTheOpenSourceLicenceNotices() {
        val app = ApplicationProvider.getApplicationContext<Application>()
        compose.setContent { ShellXTheme { AboutSection(version = versionText("1.0.0", 100)) } }
        compose.onNodeWithText("shellx.pro").assertDoesNotExist()
        compose.onNodeWithText(app.getString(R.string.settings_about_license)).performClick()
        assertEquals(LICENCES_SCREEN, shadowOf(app).nextStartedActivity?.component?.className)
    }

    private companion object {
        /** The bundled-list fallback (plan 3H Task 7, Step 14): Google's licences plugin does not fit this build. */
        const val LICENCES_SCREEN = "com.shellx.app.ui.settings.LicencesActivity"
    }
}
