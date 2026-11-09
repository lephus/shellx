package com.shellx.app

import android.content.Intent
import android.net.Uri
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
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
@Config(application = ShellXApplication::class)
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
}
