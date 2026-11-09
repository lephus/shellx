package com.shellx.app.ui.components

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.ui.components.RowActionKind.CLOSE_AGENT
import com.shellx.app.ui.components.RowActionKind.CLOSE_WORKSPACE
import com.shellx.app.ui.components.RowActionKind.MAKE_DEFAULT
import com.shellx.app.ui.components.RowActionKind.PAIR_AGAIN
import com.shellx.app.ui.components.RowActionKind.REMOVE_ENDED
import com.shellx.app.ui.components.RowActionKind.REMOVE_FROM_PHONE
import com.shellx.app.ui.components.RowActionKind.REMOVE_MAC
import com.shellx.app.ui.components.RowActionKind.RENAME_WORKSPACE
import com.shellx.app.ui.components.RowActionKind.UNPAIR
import com.shellx.core.link.MachineLinkState
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/** Which swipe and which long-press menu each row has (the iPhone's swipe and context-menu actions). */
@RunWith(AndroidJUnit4::class)
class RowActionsTest {
    @Test
    fun agentCards() {
        assertEquals(RowActionPlan(CLOSE_AGENT, listOf(CLOSE_AGENT)), RowActions.agentCard(closable = true, removable = false))
        assertEquals(
            RowActionPlan(REMOVE_FROM_PHONE, listOf(REMOVE_FROM_PHONE)),
            RowActions.agentCard(closable = false, removable = true),
        )
        assertEquals(
            RowActionPlan(CLOSE_AGENT, listOf(CLOSE_AGENT, REMOVE_FROM_PHONE)),
            RowActions.agentCard(closable = true, removable = true),
        )
        assertEquals(RowActionPlan(null, emptyList()), RowActions.agentCard(closable = false, removable = false))
    }

    @Test
    fun workspaceCards() {
        assertEquals(
            RowActionPlan(CLOSE_WORKSPACE, listOf(RENAME_WORKSPACE, CLOSE_WORKSPACE)),
            RowActions.workspaceCard(canControl = true),
        )
        assertEquals(RowActionPlan(null, emptyList()), RowActions.workspaceCard(canControl = false))
    }

    @Test
    fun sessionListCards() {
        assertEquals(RowActionPlan(REMOVE_ENDED, listOf(REMOVE_ENDED)), RowActions.endedCard())
        assertEquals(RowActionPlan(null, emptyList()), RowActions.otherSessionCard(removable = false))
        assertEquals(
            RowActionPlan(REMOVE_FROM_PHONE, listOf(REMOVE_FROM_PHONE)),
            RowActions.otherSessionCard(removable = true),
        )
    }

    @Test
    fun macRows() {
        assertEquals(
            RowActionPlan(UNPAIR, listOf(MAKE_DEFAULT, UNPAIR)),
            RowActions.machine(MachineLinkState.Online, offersMakeDefault = true),
        )
        assertEquals(
            RowActionPlan(UNPAIR, listOf(PAIR_AGAIN, UNPAIR)),
            RowActions.machine(MachineLinkState.HostKeyChanged, offersMakeDefault = false),
        )
        assertEquals(
            RowActionPlan(REMOVE_MAC, listOf(REMOVE_MAC)),
            RowActions.machine(MachineLinkState.Revoked, offersMakeDefault = false),
        )
        assertEquals(
            RowActionPlan(UNPAIR, listOf(MAKE_DEFAULT, UNPAIR)),
            RowActions.machine(MachineLinkState.Offline(1), offersMakeDefault = true),
        )
    }
}
