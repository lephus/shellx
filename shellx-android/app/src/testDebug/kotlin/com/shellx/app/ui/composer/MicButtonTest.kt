package com.shellx.app.ui.composer

import android.content.Context
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performCustomAccessibilityActionWithLabel
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.testing.VoiceRig
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.voice.LocalVoice
import com.shellx.core.voice.DictationOutcome
import com.shellx.core.voice.VoiceInputModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Hold-to-talk: only a lift sends; a hold taken away, or a mic that leaves while held, cancels (3C's MicHold). */
@RunWith(AndroidJUnit4::class)
class MicButtonTest {
    @get:Rule val compose = createComposeRule()

    private var outcome: DictationOutcome? = null
    private var nothing = 0
    private val mic get() = compose.onNodeWithTag("voice.mic")

    private fun show(rig: VoiceRig, model: VoiceInputModel, shown: State<Boolean> = mutableStateOf(true)) = compose.setContent {
        ShellXTheme {
            CompositionLocalProvider(LocalVoice provides rig.env) {
                if (shown.value) MicButton(model, R.string.voice_mic, onOutcome = { outcome = it }, onKeyboard = {}, onNothing = { nothing++ })
            }
        }
    }

    /** Robolectric's main looper runs only while the rule idles, so each wait idles first. */
    private fun until(condition: () -> Boolean) = compose.waitUntil(10_000) {
        compose.waitForIdle()
        condition()
    }

    @Test
    fun holdingListensAndTheLiftSendsTheWords() {
        val rig = VoiceRig.make()
        val model = rig.model()
        show(rig, model)
        mic.performTouchInput { down(center) }
        until { rig.engine.starts.size == 1 }
        rig.engine.say("chạy test")
        until { model.phase == VoiceInputModel.Phase.Listening("chạy test") }
        mic.performTouchInput { up() }
        until { outcome != null }
        assertEquals(DictationOutcome.Complete("chạy test"), outcome)
        assertEquals(listOf(rig.engine.starts[0].run), rig.engine.finishCalls)
    }

    @Test
    fun dragLeftPastEightyDpArmsCancelAndTheLiftSendsNothing() {
        val rig = VoiceRig.make()
        val model = rig.model()
        show(rig, model)
        mic.performTouchInput { down(center) }
        until { rig.engine.starts.size == 1 }
        rig.engine.say("bỏ đi")
        mic.performTouchInput { moveBy(Offset(-81.dp.toPx(), 0f)) }
        until { model.phase == VoiceInputModel.Phase.CancelArmed("bỏ đi") }
        mic.performTouchInput { up() }
        until { nothing == 1 }
        assertNull(outcome)
        assertEquals(listOf(rig.engine.starts[0].run), rig.engine.cancelCalls)
    }

    /** RF 1: the pager or a list claims the touch, or the system cancels it. */
    @Test
    fun aHoldTakenAwayCancelsAndSendsNothing() {
        val rig = VoiceRig.make()
        val model = rig.model()
        show(rig, model)
        mic.performTouchInput { down(center) }
        until { rig.engine.starts.size == 1 }
        rig.engine.say("nửa câu")
        mic.performTouchInput { cancel() }
        until { rig.engine.cancelCalls.size == 1 }
        assertNull(outcome)
        assertEquals(VoiceInputModel.Phase.Idle, model.phase)
        assertNull(rig.engine.activeRun)
    }

    /** RF 1: Back, or the pane swiped away, while the finger is down. */
    @Test
    fun leavingWhileHoldingGivesTheMicrophoneBack() {
        val rig = VoiceRig.make()
        val model = rig.model()
        val shown = mutableStateOf(true)
        show(rig, model, shown)
        mic.performTouchInput { down(center) }
        until { rig.engine.starts.size == 1 }
        rig.engine.say("đang nói")
        shown.value = false
        until { rig.engine.activeRun == null }
        assertEquals(1, rig.engine.cancelCalls.size)
        assertNull(outcome)
        assertEquals(VoiceInputModel.Phase.Idle, model.phase)
        assertFalse(rig.env.activity.anyActive.value)
    }

    @Test
    fun swipingUpBeforeAnyWordAsksForTheKeyboard() {
        val rig = VoiceRig.make()
        val model = rig.model()
        show(rig, model)
        mic.performTouchInput { down(center) }
        until { rig.engine.starts.size == 1 }
        mic.performTouchInput { moveBy(Offset(0f, -61.dp.toPx())) }
        until { model.wantsKeyboard }
        mic.performTouchInput { up() }
        compose.waitForIdle()
        assertNull(outcome)
    }

    @Test
    fun talkBackTapsStartAndFinishAndCancelIsAnAction() {
        val rig = VoiceRig.make()
        val model = rig.model()
        show(rig, model)
        mic.performSemanticsAction(SemanticsActions.OnClick)
        until { rig.engine.starts.size == 1 }
        rig.engine.say("một hai")
        until { model.phase == VoiceInputModel.Phase.Listening("một hai") }
        mic.performSemanticsAction(SemanticsActions.OnClick)
        until { outcome != null }
        assertEquals(DictationOutcome.Complete("một hai"), outcome)
        mic.performSemanticsAction(SemanticsActions.OnClick)
        until { rig.engine.starts.size == 2 }
        val cancelLabel = ApplicationProvider.getApplicationContext<Context>().getString(R.string.common_cancel)
        mic.performCustomAccessibilityActionWithLabel(cancelLabel)
        until { rig.engine.cancelCalls.size == 1 }
    }
}
