package com.shellx.app.ui.composer

import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.annotation.StringRes
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.MicOff
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.changedToUp
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.voice.LocalVoice
import com.shellx.core.voice.DictationOutcome
import com.shellx.core.voice.MicHold
import com.shellx.core.voice.VoiceInputModel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

/**
 * The mic (`MicButton.swift`, S3 §7.3): a round button held to talk. At rest it is accent at 15 % with a thin accent
 * border and an outline mic; while listening it is solid accent with a waveform, and two thin rings grow with the
 * voice (still, at a middle size, when animations are off).
 *
 * - Lifting the finger hands what was said to [onOutcome]; dragging left past 80 dp arms cancel; swiping up before any
 *   word asks for the keyboard (the host watches `wantsKeyboard`).
 * - Only a lift sends (3C's [MicHold]): a hold taken away without one (the pager or a list claimed the touch, the
 *   system cancelled it, the mic left while held) cancels, so half-spoken words never reach the agent (RF 1).
 * - Haptics: a tick as listening starts, a confirm when the words are taken whole, a reject on cancel.
 * - With TalkBack the hold gesture is off and the button works by taps: the first starts, the next one finishes.
 *   Cancel (while listening) and "Type instead" are custom actions.
 *
 * Mic actions run in `LocalVoice.current.scope` (the hub's), so a stop outlives the composable. The model's active
 * state is reported to `LocalVoice.current.activity`.
 */
@Composable
fun MicButton(
    model: VoiceInputModel,
    @StringRes label: Int,
    modifier: Modifier = Modifier,
    diameter: Dp = 58.dp,
    onOutcome: (DictationOutcome) -> Unit,
    onKeyboard: (() -> Unit)? = null,
    onPress: (() -> Unit)? = null,
    onNothing: (() -> Unit)? = null,
) {
    val env = LocalVoice.current
    val fallbackScope = rememberCoroutineScope()
    val scope: CoroutineScope = env?.scope ?: fallbackScope
    val state by model.state.collectAsStateWithLifecycle()
    val phase = state.phase
    val active = phase is VoiceInputModel.Phase.Listening || phase is VoiceInputModel.Phase.CancelArmed ||
        phase == VoiceInputModel.Phase.Finishing
    val armed = phase is VoiceInputModel.Phase.CancelArmed
    val level by (env?.meter?.level ?: remember { MutableStateFlow(0f) }).collectAsState()
    val haptics = LocalHapticFeedback.current
    val touchExploration by rememberTouchExploration()
    val stillRings = rememberAnimationsOff()

    val outcome by rememberUpdatedState(onOutcome)
    val pressed by rememberUpdatedState(onPress)
    val nothing by rememberUpdatedState(onNothing)
    val keyboard by rememberUpdatedState(onKeyboard)

    val actions = remember(model, scope) {
        MicActions(
            model, scope,
            starting = {
                haptics.performHapticFeedback(HapticFeedbackType.GestureThresholdActivate)
                pressed?.invoke()
            },
            sent = { result ->
                if (result is DictationOutcome.Complete) haptics.performHapticFeedback(HapticFeedbackType.Confirm)
                outcome(result)
            },
            dropped = { wasArmed ->
                if (wasArmed) haptics.performHapticFeedback(HapticFeedbackType.Reject)
                nothing?.invoke()
            },
        )
    }

    val activity = env?.activity
    SideEffect { activity?.update(model, active) }
    DisposableEffect(activity, model) { onDispose { activity?.update(model, false) } }

    val stop = stringResource(R.string.voice_mic_stop)
    val talk = stringResource(label)
    val hint = stringResource(R.string.voice_mic_hint)
    val cancelLabel = stringResource(R.string.common_cancel)
    val keyboardLabel = stringResource(R.string.voice_keyboard)
    val colors = ShellXTheme.colors
    val scale by animateFloatAsState(if (active) 1.06f else 1f, tween(150), label = "mic-scale")
    val shownLevel by animateFloatAsState(level, tween(120), label = "mic-level")

    Box(
        modifier
            .size(diameter)
            .testTag("voice.mic")
            .semantics {
                role = Role.Button
                contentDescription = if (active) stop else talk
                if (!active) stateDescription = hint
                onClick {
                    if (model.isActive) actions.finish() else actions.start()
                    true
                }
                customActions = buildList {
                    if (active) add(CustomAccessibilityAction(cancelLabel) { actions.cancel(); true })
                    if (keyboard != null) add(CustomAccessibilityAction(keyboardLabel) { keyboard?.invoke(); true })
                }
            }
            .pointerInput(actions, touchExploration) {
                // TalkBack on: taps go through the semantics only.
                if (touchExploration) return@pointerInput
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    down.consume()
                    val hold = actions.hold
                    actions.perform(hold.holdingChanged(true))
                    var lifted = false
                    try {
                        while (true) {
                            val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                            // Only a lift no one else took sends. A cancelled touch comes up consumed: not a lift.
                            if (change.changedToUp()) {
                                lifted = true
                                change.consume()
                                break
                            }
                            // Cancelled, or another handler took the touch.
                            if (!change.pressed || change.isConsumed) break
                            val moved = change.position - down.position
                            model.drag(moved.x.toDp().value.toDouble(), moved.y.toDp().value.toDouble())
                            // The pager never sees the drag.
                            change.consume()
                        }
                    } finally {
                        // Also when the mic leaves while held: the hold is cancelled, the microphone given back.
                        if (lifted) actions.perform(hold.ended())
                        actions.perform(hold.holdingChanged(false))
                        actions.perform(hold.settle())
                    }
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        if (active) {
            val ringLevel = if (stillRings) 0.4f else shownLevel
            Box(
                Modifier.size(diameter).drawBehind {
                    val radius = size.minDimension / 2
                    val outer = if (stillRings) 1.5f else 1.35f + ringLevel * 0.45f
                    val inner = if (stillRings) 1.25f else 1.15f + ringLevel * 0.25f
                    drawCircle(colors.accent.copy(alpha = 0.22f), radius * outer, style = Stroke(1.dp.toPx()))
                    drawCircle(colors.accent.copy(alpha = 0.45f), radius * inner, style = Stroke(1.5.dp.toPx()))
                },
            )
        }
        Box(
            Modifier
                .size(diameter)
                .scale(scale)
                .alpha(if (armed) 0.55f else 1f)
                .drawBehind { drawCircle(if (active) colors.accent else colors.accent.copy(alpha = 0.15f)) }
                .border(1.dp, colors.accent.copy(alpha = if (active) 0f else 0.45f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                MicButton.symbol(phase), contentDescription = null,
                tint = if (active) colors.onAccent else colors.accentText,
                modifier = Modifier.size(diameter * 0.4f),
            )
        }
    }
}

object MicButton {
    /** Idle and finishing: the mic; listening: a waveform; cancel armed: ✕; denied or unavailable: a crossed mic. */
    fun symbol(phase: VoiceInputModel.Phase): ImageVector = when (phase) {
        VoiceInputModel.Phase.Idle, VoiceInputModel.Phase.Finishing -> Icons.Outlined.Mic
        is VoiceInputModel.Phase.Listening -> Icons.Filled.GraphicEq
        is VoiceInputModel.Phase.CancelArmed -> Icons.Filled.Close
        is VoiceInputModel.Phase.Denied, VoiceInputModel.Phase.Unavailable -> Icons.Outlined.MicOff
    }
}

/** What the mic does, in [scope]: start, finish and cancel a dictation of [model], driven by the hold's steps. */
private class MicActions(
    private val model: VoiceInputModel,
    private val scope: CoroutineScope,
    private val starting: () -> Unit,
    private val sent: (DictationOutcome) -> Unit,
    private val dropped: (wasArmed: Boolean) -> Unit,
) {
    val hold = MicHold()

    fun perform(step: MicHold.Step) {
        when (step) {
            MicHold.Step.PRESS -> start()
            MicHold.Step.RELEASE -> finish()
            MicHold.Step.CANCEL -> cancel()
            MicHold.Step.NONE -> Unit
        }
    }

    fun start() {
        if (model.isActive) return
        starting()
        scope.launch { model.press() }
    }

    fun finish() {
        val armed = model.phase is VoiceInputModel.Phase.CancelArmed
        scope.launch {
            val text = model.release()
            if (text != null) sent(model.outcome(text)) else dropped(armed)
        }
    }

    /** Drops what was heard, as a drag to the left and a lift do. */
    fun cancel() {
        model.drag(-VoiceInputModel.CANCEL_DISTANCE, 0.0)
        finish()
    }
}

/** Whether TalkBack (touch exploration) is on, followed as it changes. */
@Composable
private fun rememberTouchExploration(): State<Boolean> {
    val context = LocalContext.current
    val manager = remember(context) { context.getSystemService(AccessibilityManager::class.java) }
    val enabled = remember(manager) { mutableStateOf(manager?.isTouchExplorationEnabled == true) }
    DisposableEffect(manager) {
        val listener = AccessibilityManager.TouchExplorationStateChangeListener { enabled.value = it }
        manager?.addTouchExplorationStateChangeListener(listener)
        onDispose { manager?.removeTouchExplorationStateChangeListener(listener) }
    }
    return enabled
}

/** Animations are off on the phone ("Remove animations"): the rings stand still. */
@Composable
private fun rememberAnimationsOff(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}
