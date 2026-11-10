@file:OptIn(ExperimentalCoroutinesApi::class)

package com.shellx.app.platform

import android.Manifest
import android.app.Application
import android.app.NotificationManager
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.push.PushPayload
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

/** Review Focus 4: pushes that must not show, or must not break anything (RF 4). */
@RunWith(AndroidJUnit4::class)
class PushNotifierTest {
    private val app: Application = ApplicationProvider.getApplicationContext()
    private val manager = app.getSystemService(NotificationManager::class.java)
    private val shown get() = manager.activeNotifications.toList()
    private var foreground = false
    private var machines: Set<String>? = setOf("m1", "m2")
    private val notifier = PushNotifier(app, { foreground }, { machines })

    private fun needsYou(machine: String, request: String) = PushPayload.NeedsYou(machine, request, "Codex", "")

    @Before
    fun setUp() {
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
    }

    @Test
    fun nothingShowsWhileTheAppIsInFront() {
        runTest {
            foreground = true
            notifier.handle(needsYou("m1", "r1"))
            assertTrue(shown.isEmpty())
        }
    }

    /** Review C m-2: the app came to the front while the paired Macs were read, so its clearAll ran first; the alert
     *  must not post after it and stay while the app is in front. */
    @Test
    fun theAppComingToTheFrontDuringTheMacCheckPostsNothing() {
        runTest {
            val notifier = PushNotifier(app, { foreground }, {
                foreground = true
                setOf("m1")
            })
            notifier.handle(needsYou("m1", "r1"))
            assertTrue(shown.isEmpty())
        }
    }

    @Test
    fun aMacThisPhoneDoesNotHaveIsIgnored() {
        runTest {
            machines = setOf("m2")
            notifier.handle(needsYou("m1", "r1"))
            assertTrue("m1 is not paired here", shown.isEmpty())

            machines = null
            notifier.handle(needsYou("m1", "r1"))
            assertEquals("unknown Macs: the alert posts", listOf("r1"), shown.filter { it.id == PushNotifier.NOTIFICATION_ID }.map { it.tag })

            manager.cancelAll()
            val stuck = PushNotifier(app, { false }, { awaitCancellation() })
            val handled = async { stuck.handle(needsYou("m1", "r2")) }
            advanceTimeBy(PushNotifier.KNOWN_MACHINES_TIMEOUT.inWholeMilliseconds - 1)
            runCurrent()
            assertTrue("still asking the vault", shown.isEmpty())
            advanceTimeBy(2)
            runCurrent()
            assertTrue(handled.isCompleted)
            assertEquals("posted after 2 s", listOf("r2"), shown.filter { it.id == PushNotifier.NOTIFICATION_ID }.map { it.tag })
        }
    }

    @Test
    fun withoutPermissionNothingIsPosted() {
        runTest {
            shadowOf(app).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
            notifier.handle(needsYou("m1", "r1"))
            assertTrue(shown.isEmpty())
        }
    }

    @Test
    fun theSummaryLeavesWithTheLastAlertOfItsMac() {
        runTest {
            notifier.handle(needsYou("m1", "r1"))
            notifier.handle(needsYou("m1", "r2"))
            notifier.handle(needsYou("m2", "r3"))

            notifier.handle(PushPayload.Resolved("m1", "r1"))
            assertTrue("m1's summary stays", shown.any { it.id == PushNotifier.SUMMARY_ID && it.tag == "m1" })

            notifier.handle(PushPayload.Resolved("m1", "r2"))
            assertFalse(shown.any { it.tag == "m1" || it.tag == "r1" || it.tag == "r2" })
            assertTrue(shown.any { it.id == PushNotifier.NOTIFICATION_ID && it.tag == "r3" })
            assertTrue(shown.any { it.id == PushNotifier.SUMMARY_ID && it.tag == "m2" })
        }
    }

    /**
     * Review C m-1: Android lists a posted alert only once its service got to it, so in a burst (`needs_you r2`, then
     * `resolved r1`) the list may not show r2 yet. The notifier's own record keeps the summary, whose cancel would take
     * r2 with it; clearAll empties the record too.
     */
    @Test
    fun theSummaryStaysForAnAlertAndroidDoesNotListYet() {
        runTest {
            val notifier = PushNotifier(app, { false }, { machines }, active = { emptyList() })
            notifier.handle(needsYou("m1", "r1"))
            notifier.handle(needsYou("m1", "r2"))

            notifier.handle(PushPayload.Resolved("m1", "r1"))
            assertTrue("r2 is still on the record", shown.any { it.id == PushNotifier.SUMMARY_ID && it.tag == "m1" })
            assertEquals(listOf("r2"), shown.filter { it.id == PushNotifier.NOTIFICATION_ID }.map { it.tag })

            notifier.handle(PushPayload.Resolved("m1", "r2"))
            assertTrue(shown.isEmpty())

            notifier.handle(needsYou("m1", "r3"))
            notifier.clearAll()
            notifier.handle(needsYou("m1", "r4"))
            notifier.handle(PushPayload.Resolved("m1", "r4"))
            assertTrue("clearAll forgot r3", shown.isEmpty())
        }
    }

    @Test
    fun comingToTheFrontClearsEveryAlertAndAStrayResolvedIsHarmless() {
        runTest {
            notifier.handle(needsYou("m1", "r1"))
            notifier.handle(needsYou("m2", "r2"))
            assertEquals(2, shown.count { it.id == PushNotifier.NOTIFICATION_ID })

            notifier.clearAll()
            assertTrue(shown.isEmpty())

            notifier.handle(PushPayload.Resolved("m1", "zz"))
            assertTrue(shown.isEmpty())
        }
    }
}
