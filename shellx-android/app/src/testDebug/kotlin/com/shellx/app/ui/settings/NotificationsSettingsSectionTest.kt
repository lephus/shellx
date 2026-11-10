package com.shellx.app.ui.settings

import android.Manifest
import android.app.NotificationManager
import android.os.Build
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.LocalActivityResultRegistryOwner
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.platform.NotificationPermission
import com.shellx.app.testing.FakeResultRegistry
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.platform.MemoryKeyValueStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

/** Settings › Notifications (S3 §7.4c; ledger A-1, A-28): on or off, Turn On, and the late-notifications guide. */
@RunWith(AndroidJUnit4::class)
class NotificationsSettingsSectionTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val activity get() = rule.activity
    private fun string(id: Int) = activity.getString(id)

    @Test
    fun onSaysOn() {
        shadowOf(activity.application).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        shadowOf(activity.getSystemService(NotificationManager::class.java)).setNotificationsEnabled(true)
        rule.setContent { ShellXTheme { NotificationsSettingsSection() } }

        rule.onNodeWithText(string(R.string.settings_notifications_on)).assertIsDisplayed()
        rule.onNodeWithText(string(R.string.settings_notifications_on_footer)).assertIsDisplayed()
        rule.onNodeWithTag("settings.notifications.turnOn").assertDoesNotExist()
    }

    /** Android no longer shows its dialog (denied twice): the answer comes at once, the rationale flag off before and
     *  after, and only the system page can turn alerts on. */
    @Test
    fun offTurnOnAsksForThePermissionThenOpensSettings() {
        shadowOf(activity.application).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        val registry = FakeResultRegistry().apply { answer = { false } }
        rule.setContent {
            CompositionLocalProvider(LocalActivityResultRegistryOwner provides registry.owner) {
                ShellXTheme { NotificationsSettingsSection() }
            }
        }
        rule.onNodeWithText(string(R.string.settings_notifications_off)).assertIsDisplayed()
        rule.onNodeWithText(string(R.string.settings_notifications_off_footer)).assertIsDisplayed()

        rule.onNodeWithTag("settings.notifications.turnOn").performClick()
        rule.waitForIdle()

        assertTrue("Robolectric runs API 33+ here", Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
        val launch = registry.launches.single()
        assertTrue(launch.contract is ActivityResultContracts.RequestPermission)
        assertEquals(Manifest.permission.POST_NOTIFICATIONS, launch.input)
        val opened = shadowOf(activity).nextStartedActivity
        assertEquals(Settings.ACTION_APP_NOTIFICATION_SETTINGS, opened.action)
        assertEquals(activity.packageName, opened.getStringExtra(Settings.EXTRA_APP_PACKAGE))
    }

    /** Turn On whose dialog [deny] answers "Don't allow", with the rationale flag [before] the launch and [after]. */
    private fun turnOnAndDeny(before: Boolean, after: Boolean) {
        shadowOf(activity.application).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        val packages = shadowOf(activity.packageManager)
        packages.setShouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS, before)
        val registry = FakeResultRegistry().apply {
            answer = {
                packages.setShouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS, after)
                false
            }
        }
        rule.setContent {
            CompositionLocalProvider(LocalActivityResultRegistryOwner provides registry.owner) {
                ShellXTheme { NotificationsSettingsSection() }
            }
        }
        rule.onNodeWithTag("settings.notifications.turnOn").performClick()
        rule.waitForIdle()
        assertEquals(1, registry.launches.size)
    }

    /** iPhone parity: "Don't allow" tapped in the first dialog (the flag turns on) just leaves alerts off. */
    @Test
    fun dontAllowInTheFirstDialogLeavesItOff() {
        turnOnAndDeny(before = false, after = true)
        assertNull("no system page", shadowOf(activity).nextStartedActivity)
        rule.onNodeWithText(string(R.string.settings_notifications_off)).assertIsDisplayed()
        rule.onNodeWithTag("settings.notifications.turnOn").assertIsDisplayed()
    }

    /** The same in Android's second and last dialog (the flag turns off). */
    @Test
    fun dontAllowInTheLastDialogLeavesItOff() {
        turnOnAndDeny(before = true, after = false)
        assertNull("no system page", shadowOf(activity).nextStartedActivity)
        rule.onNodeWithText(string(R.string.settings_notifications_off)).assertIsDisplayed()
    }

    /** Review C m-8: Turn On shows Android's dialog, which spends one of its two showings, so the automatic ask (when
     *  the first Mac is paired) is spent too and does not use the last one. */
    @Test
    fun turnOnSpendsTheAutomaticAsk() {
        shadowOf(activity.application).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        val registry = FakeResultRegistry().apply { answer = { false } }
        val settings = MemoryKeyValueStore()
        rule.setContent {
            CompositionLocalProvider(LocalActivityResultRegistryOwner provides registry.owner) {
                ShellXTheme { NotificationsSettingsSection(settings) }
            }
        }
        rule.onNodeWithTag("settings.notifications.turnOn").performClick()
        rule.waitForIdle()

        assertEquals(1, registry.launches.size)
        assertTrue(settings.getBoolean(NotificationPermission.ASKED_KEY))
    }

    @Test
    fun theLateRowOpensTheGuideAndTheAppsSettings() {
        rule.setContent { ShellXTheme { NotificationsSettingsSection() } }

        rule.onNodeWithTag("settings.notifications.late").performClick()
        rule.onNodeWithText(string(R.string.settings_notifications_late_intro)).assertIsDisplayed()
        rule.onNodeWithText(string(OemGuide.of(Build.MANUFACTURER).text)).assertIsDisplayed()

        rule.onNodeWithTag("settings.notifications.openAppSettings").performClick()
        rule.waitForIdle()
        val opened = shadowOf(activity).nextStartedActivity
        assertEquals(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, opened.action)
        assertEquals("package:" + activity.packageName, opened.dataString)
    }
}
