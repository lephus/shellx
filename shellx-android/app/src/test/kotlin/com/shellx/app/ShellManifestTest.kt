package com.shellx.app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** The shell's manifest entries (3E's ManifestTest checks its own permissions). */
@RunWith(AndroidJUnit4::class)
class ShellManifestTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun shellxLinkLinksOpenTheOneActivity() {
        val view = Intent(Intent.ACTION_VIEW, Uri.parse("shellx-link://pair?v=1&m=m1")).addCategory(Intent.CATEGORY_BROWSABLE)
        assertEquals(
            listOf("com.shellx.app.MainActivity"),
            context.packageManager.queryIntentActivities(view, 0).map { it.activityInfo.name },
        )
    }

    @Test
    fun theOneActivityIsSingleTask() {
        val info = context.packageManager.getActivityInfo(ComponentName(context, "com.shellx.app.MainActivity"), 0)
        assertEquals(ActivityInfo.LAUNCH_SINGLE_TASK, info.launchMode)
    }

    @Test
    fun noRelayOverrideWithoutTheGradleProperty() {
        assertEquals("", BuildConfig.SHELLX_API_BASE)
    }

    @Test
    fun theWebClientIdIsThePlaceholderOrAWebClient() {
        val id = context.getString(R.string.google_web_client_id)
        assertTrue(
            id,
            id == "0-shellx-placeholder.apps.googleusercontent.com" ||
                Regex("^[0-9]+-[a-z0-9]+\\.apps\\.googleusercontent\\.com$").matches(id),
        )
    }
}
