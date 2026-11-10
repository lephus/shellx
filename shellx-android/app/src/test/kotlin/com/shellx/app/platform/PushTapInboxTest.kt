package com.shellx.app.platform

import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** A tap on a "needs you" alert is held until the signed-in screens take it (`PushTapInbox`). */
@RunWith(AndroidJUnit4::class)
class PushTapInboxTest {
    @Test
    fun aTapIsTakenOnce() {
        val inbox = PushTapInbox()
        inbox.receive()
        assertTrue(inbox.hasTap.value)
        assertTrue(inbox.take())
        assertFalse(inbox.take())
        assertFalse(inbox.hasTap.value)
    }

    @Test
    fun onlyTheOpenPendingActionCounts() {
        assertTrue(PushTapInbox.isOpenPending(Intent(PushNotifier.ACTION_OPEN_PENDING)))
        assertFalse(PushTapInbox.isOpenPending(Intent(Intent.ACTION_MAIN)))
        assertFalse(PushTapInbox.isOpenPending(null))
    }
}
