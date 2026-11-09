package com.shellx.app.ui.machines

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.link.MachineLinkState
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/** Which Macs offer "Make Default" (MachinesRenderTests.testMakeDefaultOfferedOnlyForUsableMacs). */
@RunWith(AndroidJUnit4::class)
class MachineListItemTest {
    @Test
    fun makeDefaultIsOfferedOnlyForUsableMacs() {
        val everyState = listOf(
            MachineListItem("m1", "MacBook Pro", MachineLinkState.Online),
            MachineListItem("m2", "Mac mini", MachineLinkState.Connecting),
            MachineListItem("m3", "iMac", MachineLinkState.Reconnecting),
            MachineListItem("m4", "Mac Studio", MachineLinkState.Offline(1_700_000_000_000)),
            MachineListItem("m5", "Mac của Lan", MachineLinkState.Revoked),
            MachineListItem("m6", "Mac Pro", MachineLinkState.HostKeyChanged),
            MachineListItem("m7", "MacBook Air", MachineLinkState.NeedsUpdate),
        )
        val offered = everyState.map { it.offersMakeDefault(defaultId = "m2") }
        // online, the default itself, reconnecting, offline, revoked, key changed, needs update
        assertEquals(listOf(true, false, true, true, false, false, true), offered)
    }
}
