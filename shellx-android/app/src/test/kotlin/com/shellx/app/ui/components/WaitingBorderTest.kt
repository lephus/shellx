package com.shellx.app.ui.components

import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.link.core.AgentState
import kotlin.time.Duration.Companion.seconds
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** The border around an agent that waits for the user (port of WaitingBorderRenderTests.swift's logic tests). */
@RunWith(AndroidJUnit4::class)
class WaitingBorderTest {
    @Test
    fun theColoursAndStrokeAreTheSpecifiedOnes() {
        assertEquals(listOf(0xFF60A5FA, 0xFFA78BFA, 0xFFF472B6, 0xFFFBBF24, 0xFF60A5FA), WaitingBorder.PALETTE)
        assertEquals("the turn closes without a seam", WaitingBorder.PALETTE.first(), WaitingBorder.PALETTE.last())
        assertEquals(2.dp, WaitingBorder.LINE_WIDTH)
    }

    @Test
    fun theGradientTurnsOnceEveryThreeSecondsAtAConstantSpeed() {
        assertEquals(3.seconds, WaitingBorder.TURN)
        assertEquals(0f, WaitingBorder.angle(0), 0.001f)
        assertEquals(90f, WaitingBorder.angle(750), 0.001f)
        assertEquals(180f, WaitingBorder.angle(1500), 0.001f)
        assertEquals(270f, WaitingBorder.angle(2250), 0.001f)
        assertEquals("one turn, then again", 0f, WaitingBorder.angle(3000), 0.001f)
        assertEquals(180f, WaitingBorder.angle(4500), 0.001f)
        assertEquals(90f, WaitingBorder.angle(300_750), 0.001f)
        assertEquals("at most 30 frames a second, at any display rate", 30, WaitingBorder.FRAMES_PER_SECOND)
    }

    @Test
    fun onlyAnAgentThatWaitsForTheUserHasTheBorder() {
        assertTrue(WaitingBorder.isActive(AgentState.NEEDS_INPUT, online = true))
        for (state in listOf(AgentState.WORKING, AgentState.IDLE, AgentState.ENDED, AgentState("thinking"))) {
            assertFalse("${state.wire} does not wait for the user", WaitingBorder.isActive(state, online = true))
        }
        assertFalse(
            "a Mac that is not online cannot be answered",
            WaitingBorder.isActive(AgentState.NEEDS_INPUT, online = false),
        )
    }

    @Test
    fun reduceMotionKeepsTheBorderStill() {
        assertTrue(WaitingBorder.animates(animatorsEnabled = true))
        assertFalse(WaitingBorder.animates(animatorsEnabled = false))
    }
}
