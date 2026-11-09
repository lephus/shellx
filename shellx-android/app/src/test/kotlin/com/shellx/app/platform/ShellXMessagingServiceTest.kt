package com.shellx.app.platform

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.service.notification.StatusBarNotification
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.firebase.messaging.RemoteMessage
import com.shellx.app.MainActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** FCM data messages (contracts §8) become tagged, grouped "needs you" alerts; `resolved` removes one. */
@RunWith(AndroidJUnit4::class)
@Config(application = PushTestApplication::class)
class ShellXMessagingServiceTest {
    private val app: PushTestApplication = ApplicationProvider.getApplicationContext()
    private val shown get() = app.getSystemService(NotificationManager::class.java).activeNotifications.toList()
    private lateinit var service: ShellXMessagingService

    @Before
    fun setUp() {
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        service = Robolectric.buildService(ShellXMessagingService::class.java).create().get()
    }

    private fun receive(vararg data: Pair<String, String>) =
        service.onMessageReceived(RemoteMessage.Builder("shellx@fcm.googleapis.com").setData(mapOf(*data)).build())

    private fun needsYou(request: String, title: String = "shellx") = receive(
        "kind" to "needs_you", "machine_id" to "m1", "request_id" to request, "agent" to "Claude Code", "workspace_title" to title,
    )

    private fun StatusBarNotification.text() = notification.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()

    private val alerts get() = shown.filter { it.id == PushNotifier.NOTIFICATION_ID }

    @Test
    fun needsYouIsTaggedByRequestGroupedByMacAndWorded() {
        needsYou("r1")
        val alert = alerts.single()
        assertEquals("r1", alert.tag)
        assertEquals("m1", alert.notification.group)
        assertEquals("ShellX", alert.notification.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString())
        assertEquals("Claude Code in shellx is waiting for you", alert.text())
        assertEquals(PushNotifier.CHANNEL_ID, alert.notification.channelId)
        val summary = shown.single { it.id == PushNotifier.SUMMARY_ID }
        assertEquals("m1", summary.tag)
        assertTrue(summary.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0)
    }

    @Test
    fun aBlankOrMissingWorkspaceUsesTheShortWords() {
        needsYou("r1", title = "   ")
        receive("kind" to "needs_you", "machine_id" to "m1", "request_id" to "r2", "agent" to "Codex")
        assertEquals(
            listOf("Claude Code is waiting for you", "Codex is waiting for you"),
            alerts.sortedBy { it.tag }.map { it.text() },
        )
    }

    @Test
    @Config(qualifiers = "vi")
    fun vietnameseAlertsUseTheVietnameseWords() {
        needsYou("r1")
        assertEquals("Claude Code ở shellx đang chờ bạn xác nhận", alerts.single().text())
    }

    @Test
    fun resolvedRemovesThatAlertOnly() {
        needsYou("r1")
        needsYou("r2")
        receive("kind" to "resolved", "machine_id" to "m1", "request_id" to "r1")
        assertEquals(listOf("r2"), alerts.map { it.tag })
        assertEquals(1, shown.count { it.id == PushNotifier.SUMMARY_ID })
    }

    @Test
    fun aTapOpensTheWaitingRequests() {
        needsYou("r1")
        val intent = shadowOf(alerts.single().notification.contentIntent).savedIntent
        assertEquals(PushNotifier.ACTION_OPEN_PENDING, intent.action)
        assertEquals(MainActivity::class.java.name, intent.component?.className)
        assertTrue(PushTapInbox.isOpenPending(intent))
    }

    @Test
    fun messagesAreDataOnlyAndOtherKindsAreIgnored() {
        val message = RemoteMessage.Builder("shellx@fcm.googleapis.com")
            .setData(mapOf("kind" to "teleport", "machine_id" to "m1", "request_id" to "r1")).build()
        assertNull(message.notification)
        service.onMessageReceived(message)
        assertTrue(shown.isEmpty())
    }

    @Test
    fun aNewTokenGoesToTheRegistration() {
        service.onNewToken("fcm-9")
        assertEquals(listOf("fcm-9"), app.tokens)
    }
}
