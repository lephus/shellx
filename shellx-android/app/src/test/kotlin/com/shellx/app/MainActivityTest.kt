package com.shellx.app

import android.content.Intent
import android.net.Uri
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.platform.PushNotifier
import com.shellx.app.platform.PushTapInbox
import com.shellx.app.testing.TestShellXApplication
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** A `shellx-link` link opened from another app reaches the pairing inbox (contracts §5), once. */
@RunWith(AndroidJUnit4::class)
@Config(application = TestShellXApplication::class)
class MainActivityTest {
    @Test
    fun aShellXLinkFromAnotherAppReachesTheInbox() {
        val app: ShellXApplication = ApplicationProvider.getApplicationContext()
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("shellx-link://pair?v=1&m=m1"))

        Robolectric.buildActivity(MainActivity::class.java, intent).setup()

        val deadline = System.nanoTime() + 10_000_000_000
        while (app.composition.value?.inbox?.hasLink?.value != true && System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(10)
        }
        assertTrue("the link waits in the inbox", app.composition.value?.inbox?.hasLink?.value == true)
    }

    /**
     * Review D m-1: a task started by a link keeps it as its base intent. After a Back exit, Recents relaunches that
     * intent with FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY and no saved state; the old link must not open pairing again.
     */
    @Test
    fun aLinkRelaunchedFromRecentsIsNotDeliveredAgain() {
        val app: ShellXApplication = ApplicationProvider.getApplicationContext()
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("shellx-link://pair?v=1&m=m1"))
            .addFlags(Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY)

        Robolectric.buildActivity(MainActivity::class.java, intent).setup()

        val deadline = System.nanoTime() + 10_000_000_000
        while (app.composition.value == null && System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(10)
        }
        val composition = app.composition.value
        assertNotNull("the composition is built", composition)
        // Let a delivery that waited for the composition run.
        repeat(20) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(10)
        }
        assertFalse("the old link stays out of the inbox", composition!!.inbox.hasLink.value)
    }

    private fun tap(): Intent = Intent(ApplicationProvider.getApplicationContext(), MainActivity::class.java)
        .setAction(PushNotifier.ACTION_OPEN_PENDING)

    /** A tap on a "needs you" alert waits in the push taps until the signed-in screens take it. */
    @Test
    fun aTapOnANeedsYouAlertIsHeldForTheSignedInScreens() {
        val app: ShellXApplication = ApplicationProvider.getApplicationContext()
        Robolectric.buildActivity(MainActivity::class.java, tap()).setup()
        assertTrue(app.platform.pushTaps.hasTap.value)
    }

    /** 3D note 5: a task an alert started keeps it as its base intent; Recents must not open Needs you again. */
    @Test
    fun aTapRelaunchedFromRecentsIsNotTakenAgain() {
        val app: ShellXApplication = ApplicationProvider.getApplicationContext()
        Robolectric.buildActivity(MainActivity::class.java, tap().addFlags(Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY)).setup()
        assertFalse(app.platform.pushTaps.hasTap.value)
    }

    @Test
    fun aTapThatReachesTheOpenAppIsHeldToo() {
        val app: ShellXApplication = ApplicationProvider.getApplicationContext()
        val controller = Robolectric.buildActivity(MainActivity::class.java).setup()
        assertFalse(app.platform.pushTaps.hasTap.value)
        controller.newIntent(tap())
        assertTrue(app.platform.pushTaps.hasTap.value)
        assertTrue("the activity keeps the new intent", PushTapInbox.isOpenPending(controller.get().intent))
    }

    /** 3D review D m-2: a link that opened the app is kept by the application, so it reaches the inbox even when the
     *  activity goes (a recreation, a finish) before the composition exists. */
    @Test
    fun aColdStartLinkOutlivesItsActivity() {
        val app: ShellXApplication = ApplicationProvider.getApplicationContext()
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("shellx-link://pair?v=1&m=m1"))

        Robolectric.buildActivity(MainActivity::class.java, intent).create().destroy()

        val deadline = System.nanoTime() + 10_000_000_000
        while (app.composition.value?.inbox?.hasLink?.value != true && System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(10)
        }
        assertTrue("the link waits in the inbox", app.composition.value?.inbox?.hasLink?.value == true)
    }
}
