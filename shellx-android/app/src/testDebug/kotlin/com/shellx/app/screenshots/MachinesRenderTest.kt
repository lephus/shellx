package com.shellx.app.screenshots

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.ui.machines.MachineList
import com.shellx.app.ui.machines.MachineListItem
import com.shellx.core.link.MachineLinkState
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Your Macs in every link state, and at large text (MachinesRenderTests). */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
class MachinesRenderTest {
    private val everyState = listOf(
        MachineListItem("m1", "MacBook Pro", MachineLinkState.Online),
        MachineListItem("m2", "Mac mini", MachineLinkState.Connecting),
        MachineListItem("m3", "iMac", MachineLinkState.Reconnecting),
        MachineListItem("m4", "Mac Studio", MachineLinkState.Offline(1_700_000_000_000)),
        MachineListItem("m5", "Mac của Lan", MachineLinkState.Revoked),
        MachineListItem("m6", "Mac Pro", MachineLinkState.HostKeyChanged),
        MachineListItem("m7", "MacBook Air", MachineLinkState.NeedsUpdate),
    )

    @Test
    fun everyState() {
        assertRenders("machines") {
            MachineList(everyState, defaultId = "m1", makeDefault = {}, unpair = {}, pair = {}, back = {})
        }
    }

    @Test
    fun largeText() {
        val items = everyState.take(3) + everyState[5]
        assertRenders("machines-large-text") {
            LargeText { MachineList(items, defaultId = "m1", makeDefault = {}, unpair = {}, pair = {}, back = {}) }
        }
    }
}
