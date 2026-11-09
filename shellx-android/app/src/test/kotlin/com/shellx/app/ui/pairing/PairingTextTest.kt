package com.shellx.app.ui.pairing

import android.content.Context
import android.content.res.Resources
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.pairing.PairingFailure
import com.shellx.core.pairing.PairingModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** What the pairing page says for each failure and step (MachinesRenderTests' pairing checks). */
@RunWith(AndroidJUnit4::class)
class PairingTextTest {
    private val res: Resources = ApplicationProvider.getApplicationContext<Context>().resources

    @Test
    fun eachFailureSaysSomethingDifferent() {
        val failures = listOf(
            PairingFailure.NotShellXCode, PairingFailure.NeedsUpdate, PairingFailure.DamagedCode, PairingFailure.Denied,
            PairingFailure.Expired, PairingFailure.OtherAccount, PairingFailure.Network, PairingFailure.Server("internal"),
        )
        val messages = failures.map { PairingText.message(it, res) }
        assertEquals("each failure says something different", failures.size, messages.toSet().size)
        assertTrue(messages.last().contains("internal"))
    }

    @Test
    fun announcementsFollowTheStep() {
        assertNull(PairingText.announcement(PairingModel.Step.Idle, res))
        assertNull(PairingText.announcement(PairingModel.Step.Confirm("Mac"), res))
        assertEquals(
            PairingText.message(PairingFailure.Denied, res),
            PairingText.announcement(PairingModel.Step.Failed(PairingFailure.Denied), res),
        )
        assertTrue(PairingText.announcement(PairingModel.Step.WaitingForMac("Studio"), res)!!.contains("Studio"))
        assertTrue(PairingText.announcement(PairingModel.Step.Paired("Studio"), res)!!.contains("Studio"))
    }
}
