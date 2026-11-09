@file:OptIn(ExperimentalCoroutinesApi::class)

package com.shellx.app.platform

import android.Manifest
import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import androidx.activity.result.contract.ActivityResultContracts
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.FakeResultRegistry
import com.shellx.app.testing.TestOwner
import com.shellx.core.platform.MemoryKeyValueStore
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

/** POST_NOTIFICATIONS is asked once by itself, from Android 13 (iPhone `registerIfAllowed`; ledger A-26). */
@RunWith(AndroidJUnit4::class)
class NotificationPermissionTest {
    private val app: Application = ApplicationProvider.getApplicationContext()
    private val registry = FakeResultRegistry().apply { answer = { true } }
    private val owner = TestOwner()
    private val requester = PermissionRequester(app).also { it.attach(registry, owner) }
    private val settings = MemoryKeyValueStore()

    @Test
    fun asksOnceFromAndroid13() {
        runTest {
            owner.resume()
            NotificationPermission.requestOnce(requester, settings, sdkInt = 33)
            val launch = registry.launches.single()
            assertTrue(launch.contract is ActivityResultContracts.RequestPermission)
            assertEquals(Manifest.permission.POST_NOTIFICATIONS, launch.input)
            assertTrue(settings.getBoolean(NotificationPermission.ASKED_KEY))

            NotificationPermission.requestOnce(requester, settings, sdkInt = 33)
            assertEquals(1, registry.launches.size)
        }
    }

    @Test
    fun neverAsksBelowAndroid13OrWhenGranted() {
        runTest {
            owner.resume()
            NotificationPermission.requestOnce(requester, settings, sdkInt = 32)
            assertTrue(registry.launches.isEmpty())

            shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
            NotificationPermission.requestOnce(requester, settings, sdkInt = 33)
            assertTrue(registry.launches.isEmpty())
        }
    }

    /** Chunk A's deferred PermissionRequester gap: nothing is asked while the activity is not in front, and an ask
     *  whose caller left before the prompt showed does not count as the one ask. */
    @Test
    fun theOneAskIsSpentOnlyWhenThePromptShows() {
        runTest {
            owner.start()
            val first = launch { NotificationPermission.requestOnce(requester, settings, sdkInt = 33) }
            runCurrent()
            assertTrue("not asked while the activity is not resumed", registry.launches.isEmpty())
            assertFalse(settings.getBoolean(NotificationPermission.ASKED_KEY))

            first.cancel()
            owner.resume()
            runCurrent()
            assertTrue("a dropped ask never shows later", registry.launches.isEmpty())

            NotificationPermission.requestOnce(requester, settings, sdkInt = 33)
            assertEquals(1, registry.launches.size)
            assertTrue(settings.getBoolean(NotificationPermission.ASKED_KEY))
        }
    }

    @Test
    fun isOnFollowsTheAppAndTheChannel() {
        val manager = app.getSystemService(NotificationManager::class.java)
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        PushNotifier.ensureChannel(app)
        assertEquals(NotificationManager.IMPORTANCE_HIGH, manager.getNotificationChannel(PushNotifier.CHANNEL_ID).importance)
        assertTrue(NotificationPermission.isOn(app))

        shadowOf(manager).setNotificationsEnabled(false)
        assertFalse(NotificationPermission.isOn(app))

        shadowOf(manager).setNotificationsEnabled(true)
        manager.createNotificationChannel(NotificationChannel(PushNotifier.CHANNEL_ID, "Needs you", NotificationManager.IMPORTANCE_NONE))
        assertFalse(NotificationPermission.isOn(app))
    }
}
