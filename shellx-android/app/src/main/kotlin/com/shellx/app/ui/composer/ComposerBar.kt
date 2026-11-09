package com.shellx.app.ui.composer

import android.content.res.Resources
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.shellx.app.R
import com.shellx.app.ui.theme.AppLanguage
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.voice.LocalVoice
import com.shellx.core.composer.AttachmentReadException
import com.shellx.core.composer.ComposerDraft
import com.shellx.core.composer.OutgoingAttachment
import com.shellx.core.composer.PendingPicks
import com.shellx.core.home.ComposerValidation
import com.shellx.core.platform.CoreLog
import com.shellx.core.voice.DictationOutcome
import com.shellx.core.voice.VoiceInputModel
import java.text.DecimalFormat
import java.text.NumberFormat
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

/**
 * The bar at the bottom of a conversation (`ComposerBar.swift`): the text field with one round button at its end,
 * and a "+" at its start when [attachmentsEnabled].
 *
 * - With a mic (`LocalVoice`) and nothing in the bar, the button is the mic: hold to talk, release to send (through
 *   [sendVoice], else [send]), drag left to cancel; the words show above the bar. Otherwise it is Send. No recognizer,
 *   "Type instead" or a swipe up open the keyboard.
 * - The text is checked as it changes ([ComposerValidation]): past 16 384 bytes the bar says "Too long" and Send is
 *   off. A dictation stops at that limit by itself; its words then go into the field to be read before sending.
 * - Photos and files wait in a row above the field and make Send act with no text. Too many, or one too big, is said
 *   under the field. A pick still being read holds Send.
 * - While [sending], the bar is locked and Send is a ring that fills. A message with attachments stays in the bar;
 *   the owner clears it once the Mac took it. A message of text only leaves the field at once.
 *
 * [voice] is the dictation for render tests; otherwise one is made from `LocalVoice.current.service`. [state] is what the
 * bar keeps beyond its own composition (the picks still being read among it): a screen's holder passes its own, so a
 * read outlives the bar shown (a pane swiped away, a rotated screen); without one the bar keeps its own.
 */
@Composable
fun ComposerBar(
    draft: ComposerDraft,
    onDraftChange: (ComposerDraft) -> Unit,
    send: (String, List<OutgoingAttachment>) -> Unit,
    modifier: Modifier = Modifier,
    attachmentsEnabled: Boolean = false,
    sending: Double? = null,
    sendVoice: ((String) -> Unit)? = null,
    voice: VoiceInputModel? = null,
    state: ComposerBarState? = null,
) {
    val env = LocalVoice.current
    val service = env?.service
    val own = remember(service, voice == null) { if (voice == null) service?.makeModel() else null }
    val model = voice ?: own
    val localScope = rememberCoroutineScope()
    val voiceScope = env?.scope ?: localScope
    val kept = state ?: remember { ComposerBarState(localScope, draft) }
    val picks = kept.picks
    val loading by picks.ids.collectAsStateWithLifecycle()
    val voiceState = model?.let { it.state.collectAsStateWithLifecycle().value }
    // A dictation cut at the limit, put in the field: the limit line shows while the field holds it.
    var cutText by rememberSaveable { mutableStateOf<String?>(null) }
    val focus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    val res = LocalContext.current.resources
    val locale = AppLanguage.current()
    val colors = ShellXTheme.colors
    // Every edit starts from the newest draft, the one an edit made a moment before included (review A I-1).
    val live = kept.live
    SideEffect { live.hosted(draft) }
    val hostChange by rememberUpdatedState(onDraftChange)
    val sendNow by rememberUpdatedState(send)
    val sendSpoken by rememberUpdatedState(sendVoice)
    val side: Dp = 48.dp * LocalDensity.current.fontScale.coerceAtLeast(1f)

    val validation = ComposerValidation.message(draft.text, draft.attachments)
    val mic = model?.takeIf {
        draft.text.isEmpty() && draft.attachments.isEmpty() && loading.isEmpty() && sending == null &&
            voiceState?.phase != VoiceInputModel.Phase.Unavailable
    }

    /** Hands [next] to the host, after making it the draft the next edit starts from: a pick read or a keystroke before
     *  the bar recomposes builds on it instead of on the draft the bar last drew. */
    fun change(next: ComposerDraft) {
        live.edit(next)
        hostChange(next)
    }

    /** The keyboard comes up at once; a dictation in progress is cancelled, so nothing heard while typing is sent. */
    fun openKeyboard() {
        try {
            focus.requestFocus()
        } catch (e: IllegalStateException) {
            CoreLog.log("composer_focus_failed")
        }
        keyboard?.show()
        model?.let { m -> voiceScope.launch { m.typeInstead() } }
    }

    fun said(outcome: DictationOutcome) {
        when (outcome) {
            is DictationOutcome.Complete -> sendSpoken?.invoke(outcome.words) ?: sendNow(outcome.words, emptyList())
            is DictationOutcome.CutAtLimit -> {
                change(live.value.copy(text = outcome.words))
                cutText = outcome.words
                openKeyboard()
            }
        }
    }

    fun sendTyped() {
        val current = live.value
        val checked = ComposerValidation.message(current.text, current.attachments)
        // A pick still being read would arrive after its message left.
        if (checked !is ComposerValidation.Ok || picks.count > 0) return
        val carried = current.attachments
        sendNow(checked.text, carried)
        kept.attachNote = null
        // With attachments the bar keeps the message while it goes up; the owner clears it.
        if (carried.isNotEmpty()) return
        change(live.value.copy(text = ""))
        cutText = null
    }

    LaunchedEffect(model, voiceState?.wantsKeyboard) {
        if (model != null && voiceState?.wantsKeyboard == true) {
            model.wantsKeyboard = false
            openKeyboard()
        }
    }
    LaunchedEffect(model, draft.text) {
        if (model == null || draft.text.isEmpty()) return@LaunchedEffect
        // Typing replaces a "can't listen" message; text in the field hides the mic, so a dictation still listening
        // is cancelled.
        model.dismiss()
        if (model.isActive) voiceScope.launch { model.typeInstead() }
    }
    // The bar went away (another screen covers it): the microphone never stays on behind it.
    DisposableEffect(model) { onDispose { model?.let { m -> voiceScope.launch { m.cancel() } } } }

    val divider = MaterialTheme.colorScheme.outlineVariant
    Column(
        modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.background)
            .drawBehind { drawLine(divider, Offset.Zero, Offset(size.width, 0f), 1.dp.toPx()) }
            .padding(start = 16.dp, end = 16.dp, top = 6.dp, bottom = 8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (model != null) {
            val level by (env?.meter?.level ?: remember { MutableStateFlow(0f) }).collectAsStateWithLifecycle()
            VoiceStatusView(model, level, Modifier.padding(bottom = 2.dp))
        }
        if (attachmentsEnabled && (draft.attachments.isNotEmpty() || loading.isNotEmpty())) {
            AttachmentStrip(
                draft.attachments,
                onRemove = { id ->
                    change(live.value.let { d -> d.copy(attachments = d.attachments.filterNot { it.id == id }) })
                    kept.attachNote = null
                },
                locked = sending != null,
                loading = loading,
                cancelLoading = picks::cancel,
            )
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (attachmentsEnabled) {
                AttachMenu(
                    draft.attachments,
                    onAdd = { a -> change(live.value.let { d -> d.copy(attachments = d.attachments + a) }) },
                    picks, side, enabled = sending == null, note = { kept.attachNote = it },
                    attached = { live.value.attachments },
                )
            }
            Field(draft.text, { change(live.value.copy(text = it)) }, enabled = sending == null, side, focus, Modifier.weight(1f))
            when {
                mic != null -> MicButton(mic, R.string.voice_mic, diameter = side, onOutcome = ::said, onKeyboard = ::openKeyboard)
                sending != null -> SendProgress(sending, side)
                else -> SendButton(enabled = validation is ComposerValidation.Ok && loading.isEmpty(), side, ::sendTyped)
            }
        }
        val problem = ComposerBar.problem(validation, res) ?: kept.attachNote
        when {
            validation is ComposerValidation.TooLong -> Text(
                stringResource(
                    R.string.composer_too_long, ComposerValidation.byteCount(validation.bytes, locale),
                    ComposerValidation.byteCount(ComposerValidation.MAX_BYTES, locale),
                ),
                style = MaterialTheme.typography.labelSmall.copy(fontFeatureSettings = "tnum"),
                color = colors.statusError,
                modifier = Modifier.testTag("composer.tooLong"),
            )
            problem != null -> Text(
                problem, style = MaterialTheme.typography.labelSmall, color = colors.statusError,
                modifier = Modifier.testTag("composer.attachProblem"),
            )
            cutText != null && cutText == draft.text -> Text(
                stringResource(R.string.voice_limit, ComposerValidation.byteCount(ComposerValidation.MAX_BYTES, locale)),
                style = MaterialTheme.typography.labelSmall, color = colors.statusError,
                modifier = Modifier.testTag("composer.voiceLimit"),
            )
        }
    }
}

object ComposerBar {
    /** The red line for too many attachments or one too big; null otherwise. */
    fun problem(validation: ComposerValidation, res: Resources): String? = when (validation) {
        ComposerValidation.TooManyAttachments -> res.getString(R.string.composer_attach_too_many)
        is ComposerValidation.AttachmentTooLarge -> AttachmentPreparer.message(AttachmentReadException.TooLarge(validation.name), res)
        else -> null
    }
}

/** A byte count in the app's language: "16,384" in English, "16 384" (a no-break space) in Vietnamese, where the
 *  locale's own grouping would give "16.384". */
fun ComposerValidation.Companion.byteCount(count: Int, locale: Locale): String {
    val format = NumberFormat.getIntegerInstance(locale)
    if (locale.language == "vi" && format is DecimalFormat) {
        format.decimalFormatSymbols = format.decimalFormatSymbols.apply { groupingSeparator = ' ' }
    }
    return format.format(count)
}

/**
 * What a [ComposerBar] keeps beyond one composition (final review m-3): the picks still being read ([picks], in
 * [scope]), the draft its edits start from, and why a pick was not added ([attachNote]). A screen's holder makes one
 * on its own scope, so a read that ends after its bar left (a pane swiped away, a rotated screen) still lands: its
 * result goes onto this draft and through the host's draft change, which reach the holder, not the bar that left.
 */
class ComposerBarState(scope: CoroutineScope, initial: ComposerDraft = ComposerDraft()) {
    val picks: PendingPicks = PendingPicks(scope)
    internal val live: LiveDraft = LiveDraft(initial)

    /** Why something picked was not added; a new pick or a send clears it. */
    var attachNote: String? by mutableStateOf(null)
}

/**
 * The draft the composer's edits start from (review A I-1). The host's draft reaches the bar only when it recomposes,
 * up to a frame after an edit, while picks are read and keys typed in between. So an edit is taken at once ([edit]),
 * and the host's draft only when it changes ([hosted]): an outside change (the owner cleared the bar) wins, and a host
 * whose state comes a frame late never rolls an edit back.
 */
internal class LiveDraft(initial: ComposerDraft) {
    var value: ComposerDraft = initial
        private set
    private var fromHost: ComposerDraft = initial

    fun edit(next: ComposerDraft) {
        value = next
    }

    fun hosted(draft: ComposerDraft) {
        if (draft === fromHost) return
        fromHost = draft
        value = draft
    }
}

@Composable
private fun Field(text: String, onText: (String) -> Unit, enabled: Boolean, side: Dp, focus: FocusRequester, modifier: Modifier) {
    val scheme = MaterialTheme.colorScheme
    val style = MaterialTheme.typography.bodyLarge.copy(color = if (enabled) scheme.onSurface else scheme.onSurfaceVariant)
    val placeholder = stringResource(R.string.composer_placeholder)
    BasicTextField(
        value = text,
        onValueChange = onText,
        enabled = enabled,
        textStyle = style,
        cursorBrush = SolidColor(ShellXTheme.colors.accent),
        maxLines = 5,
        modifier = modifier.focusRequester(focus).testTag("composer.field"),
        decorationBox = { inner ->
            Box(
                Modifier
                    .heightIn(min = side)
                    .background(scheme.surfaceContainerHigh, RoundedCornerShape(24.dp))
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                contentAlignment = Alignment.CenterStart,
            ) {
                if (text.isEmpty()) Text(placeholder, style = style.copy(color = scheme.onSurfaceVariant))
                inner()
            }
        },
    )
}

@Composable
private fun SendButton(enabled: Boolean, side: Dp, onClick: () -> Unit) {
    val colors = ShellXTheme.colors
    val label = stringResource(R.string.composer_send)
    Box(
        Modifier
            .size(side)
            .alpha(if (enabled) 1f else 0.4f)
            .clip(CircleShape)
            .background(colors.accent)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label }
            .testTag("composer.send"),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.Filled.ArrowUpward, contentDescription = null, tint = colors.onAccent)
    }
}

/** The send button while a message's attachments go up: its arrow, dimmed, in a ring that fills with the bytes sent. */
@Composable
private fun SendProgress(fraction: Double, side: Dp) {
    val accent = ShellXTheme.colors.accent
    val label = stringResource(R.string.composer_sending)
    val shown = fraction.toFloat().coerceIn(0f, 1f)
    Box(
        Modifier
            .size(side)
            .semantics {
                contentDescription = label
                progressBarRangeInfo = ProgressBarRangeInfo(shown, 0f..1f)
            }
            .testTag("composer.sending")
            .drawBehind {
                val stroke = 3.dp.toPx()
                val inset = 2.dp.toPx() + stroke / 2
                drawCircle(accent.copy(alpha = 0.16f))
                val arcSize = Size(size.width - inset * 2, size.height - inset * 2)
                drawArc(accent.copy(alpha = 0.25f), 0f, 360f, false, Offset(inset, inset), arcSize, style = Stroke(stroke))
                drawArc(accent, -90f, 360f * shown, false, Offset(inset, inset), arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
            },
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.Filled.ArrowUpward, contentDescription = null, tint = accent)
    }
}
