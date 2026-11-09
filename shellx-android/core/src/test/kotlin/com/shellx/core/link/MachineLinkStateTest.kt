package com.shellx.core.link

import com.shellx.core.testing.ManualClock
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MachineLinkStateTest {
    /** A Mac that removed this phone, or whose key changed, cannot take messages until it is paired again: it is not
     *  offered as the default. */
    @Test fun canBeDefault() {
        val usable: List<MachineLinkState> = listOf(
            MachineLinkState.Connecting, MachineLinkState.Online, MachineLinkState.Reconnecting,
            MachineLinkState.Offline(ManualClock().wallMs), MachineLinkState.NeedsUpdate,
        )
        for (state in usable) assertTrue(state.canBeDefault, "$state")
        assertFalse(MachineLinkState.Revoked.canBeDefault)
        assertFalse(MachineLinkState.HostKeyChanged.canBeDefault)
    }
}
