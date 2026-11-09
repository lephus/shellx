package com.shellx.app.ui.pending

import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.outlined.Laptop
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.shellx.app.R
import com.shellx.app.ui.components.PrimaryButton
import com.shellx.app.ui.components.SecondaryButton
import com.shellx.app.ui.components.isLargeText
import com.shellx.app.ui.composer.MicButton
import com.shellx.app.ui.composer.VoiceStatusView
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.voice.LocalVoice
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.pending.DecisionCenter
import com.shellx.core.pending.PendingAction
import com.shellx.core.pending.actions
import com.shellx.core.pending.previewMayBeCut
import com.shellx.core.platform.CoreLog
import com.shellx.core.text.utf8Size
import com.shellx.core.voice.VoiceInputModel
import com.shellx.link.core.ExitPlanMode
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.PendingItem
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

/**
 * Reviews an agent's plan (`PlanReviewSheet.swift`): the plan as Markdown, scrolling; "Approve" (mode `manual`), the
 * other approval modes behind `⋯`, "Revise…" (sends `deny` with the user's feedback: required, at most 4096 bytes,
 * counted as it is typed) and "Deny". Only the modes the Mac offers show. When the item was decided elsewhere meanwhile,
 * the sheet says so and nothing can be sent.
 *
 * With a mic (`LocalVoice`), a mic beside the feedback field adds what the user says after what is there; it never
 * sends. The revise step and the feedback survive a recreated screen (RF 3). [revising], [feedback] and [voice] start a
 * render test in the feedback step.
 */
@Composable
fun PlanReviewSheet(
    item: MachinePendingItem,
    state: PendingSheetState,
    send: (LinkDecision) -> Unit,
    close: () -> Unit,
    revising: Boolean = false,
    feedback: String = "",
    voice: VoiceInputModel? = null,
) {
    var inRevise by rememberSaveable { mutableStateOf(revising) }
    var text by rememberSaveable { mutableStateOf(feedback) }
    // The decision last sent from here, for "Try again".
    var last by remember { mutableStateOf<LinkDecision?>(null) }
    val env = LocalVoice.current
    val own = remember(env?.service, voice == null) {
        if (voice == null) env?.service?.makeModel(DecisionCenter.MAX_FEEDBACK_BYTES) else null
    }
    val model = voice ?: own
    val localScope = rememberCoroutineScope()
    val voiceScope = env?.scope ?: localScope
    val voiceState = model?.state?.collectAsStateWithLifecycle()?.value
    val focusManager = LocalFocusManager.current
    val field = remember { FocusRequester() }
    var focusAsked by remember { mutableStateOf(false) }
    val res = LocalContext.current.resources

    val actions = item.item.actions
    val approvals = actions.mapNotNull { (it as? PendingAction.ApprovePlan)?.mode }
    val trimmed = text.trim()
    val bytes = trimmed.utf8Size
    val canSendFeedback = state.canSend && trimmed.isNotEmpty() && bytes <= DecisionCenter.MAX_FEEDBACK_BYTES

    fun decide(decision: LinkDecision) {
        last = decision
        send(decision)
    }

    fun cancelMic() {
        model?.let { m -> voiceScope.launch { m.cancel() } }
    }

    /** The keyboard for the feedback field, at once; a dictation in progress is then cancelled. */
    fun typeFeedback() {
        focusAsked = true
        model?.let { m -> voiceScope.launch { m.typeInstead() } }
    }

    LaunchedEffect(focusAsked, inRevise) {
        if (!focusAsked || !inRevise) return@LaunchedEffect
        try {
            field.requestFocus()
        } catch (e: IllegalStateException) {
            CoreLog.log("plan_focus_failed")
        }
        focusAsked = false
    }
    // A swipe up on the mic, or no recognizer: the keyboard instead.
    LaunchedEffect(model, voiceState?.wantsKeyboard) {
        if (model != null && voiceState?.wantsKeyboard == true) {
            model.wantsKeyboard = false
            typeFeedback()
        }
    }
    // The item was handled elsewhere (the mic goes): the microphone stops.
    LaunchedEffect(model, state.handledElsewhere) { if (state.handledElsewhere) cancelMic() }
    // The sheet closed: the microphone never stays on behind it.
    DisposableEffect(model) { onDispose { model?.let { m -> voiceScope.launch { m.cancel() } } } }

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        SheetTopBar(stringResource(R.string.pending_plan_title), close)
        CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurface) {
            Column(
                Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text(
                    PendingCardView.headline(item, false, res, MaterialTheme.colorScheme.onSurfaceVariant),
                    style = MaterialTheme.typography.bodyMedium,
                )
                val plan = item.item.planPreview
                if (!plan.isNullOrEmpty()) {
                    PlanMarkdownText(plan, color = MaterialTheme.colorScheme.onSurface)
                    if (PendingItem.previewMayBeCut(plan)) CutNotice()
                } else {
                    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.Laptop, contentDescription = null, tint = secondary)
                        Text(stringResource(R.string.pending_plan_missing), color = secondary)
                    }
                }
            }
            BottomBar {
                PendingCardStatusLine(
                    state.shownStatus, state.actionable, item.machineName, state.linkNote, retry = { last?.let(send) },
                )
                when {
                    state.handledElsewhere -> PrimaryButton(onClick = close, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.common_close), style = MaterialTheme.typography.titleMedium)
                    }
                    inRevise -> {
                        if (model != null) {
                            val level by (env?.meter?.level ?: remember { MutableStateFlow(0f) }).collectAsStateWithLifecycle()
                            VoiceStatusView(model, level)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Bottom) {
                            TextField(
                                value = text,
                                onValueChange = { text = it },
                                modifier = Modifier
                                    .weight(1f)
                                    .focusRequester(field)
                                    .onFocusChanged { if (it.isFocused) model?.let { m -> voiceScope.launch { m.typeInstead() } } }
                                    .testTag("pending.feedback"),
                                placeholder = { Text(stringResource(R.string.pending_plan_feedback)) },
                                minLines = 2,
                                maxLines = 6,
                                shape = RoundedCornerShape(10.dp),
                                colors = TextFieldDefaults.colors(
                                    focusedContainerColor = MaterialTheme.colorScheme.background,
                                    unfocusedContainerColor = MaterialTheme.colorScheme.background,
                                    focusedIndicatorColor = Color.Transparent,
                                    unfocusedIndicatorColor = Color.Transparent,
                                ),
                            )
                            if (model != null) {
                                MicButton(
                                    model, R.string.pending_plan_voice, diameter = 48.dp,
                                    onOutcome = { said ->
                                        val current = text.trim()
                                        text = if (current.isEmpty()) said.words else current + " " + said.words
                                    },
                                    onKeyboard = ::typeFeedback,
                                )
                            }
                        }
                        ByteCounter(bytes, DecisionCenter.MAX_FEEDBACK_BYTES)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            SecondaryButton(
                                onClick = {
                                    // The mic goes with this step: a dictation in progress stops with it.
                                    cancelMic()
                                    inRevise = false
                                    focusManager.clearFocus()
                                },
                                modifier = Modifier.weight(1f),
                            ) { Text(stringResource(R.string.common_cancel), style = MaterialTheme.typography.bodyLarge) }
                            PrimaryButton(
                                onClick = {
                                    if (canSendFeedback) {
                                        cancelMic()
                                        focusManager.clearFocus()
                                        decide(LinkDecision.ExitPlan(ExitPlanMode.DENY, trimmed))
                                    }
                                },
                                modifier = Modifier.weight(1f).testTag("pending.sendFeedback"),
                                enabled = canSendFeedback,
                            ) { Text(stringResource(R.string.pending_plan_send_feedback), style = MaterialTheme.typography.titleMedium) }
                        }
                    }
                    else -> DecisionButtons(
                        approvals, actions, state.canSend,
                        decide = ::decide,
                        revise = {
                            inRevise = true
                            focusAsked = true
                        },
                    )
                }
            }
        }
    }
}

/** "Approve" with the other modes behind `⋯` beside it (as on a permission card), then "Revise…" and "Deny"; stacked
 *  at large text. */
@Composable
private fun DecisionButtons(
    approvals: List<ExitPlanMode>,
    actions: List<PendingAction>,
    enabled: Boolean,
    decide: (LinkDecision) -> Unit,
    revise: () -> Unit,
) {
    val stacked = isLargeText()
    val rows = @Composable { content: @Composable (Modifier) -> Unit ->
        if (stacked) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) { content(Modifier.fillMaxWidth()) }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                content(Modifier.weight(1f))
            }
        }
    }
    approvals.firstOrNull()?.let { first ->
        rows { wide ->
            PrimaryButton(
                onClick = { decide(LinkDecision.ExitPlan(first, null)) },
                modifier = wide.testTag("pending.approve"),
                enabled = enabled,
            ) { Text(stringResource(PlanReviewSheet.title(first)), style = MaterialTheme.typography.titleMedium) }
            if (approvals.size > 1) OtherModes(approvals.drop(1), enabled, stacked, decide)
        }
    }
    val revises = PendingAction.RevisePlan in actions
    val rejects = PendingAction.RejectPlan in actions
    if (revises || rejects) {
        rows { wide ->
            if (revises) {
                SecondaryButton(onClick = revise, modifier = wide.testTag("pending.revise"), enabled = enabled) {
                    Text(stringResource(R.string.pending_plan_revise), style = MaterialTheme.typography.bodyLarge)
                }
            }
            if (rejects) {
                SecondaryButton(
                    onClick = { decide(LinkDecision.ExitPlan(ExitPlanMode.DENY, null)) },
                    modifier = wide.testTag("pending.reject"),
                    enabled = enabled,
                    color = ShellXTheme.colors.statusError,
                ) { Text(stringResource(R.string.pending_deny), style = MaterialTheme.typography.bodyLarge) }
            }
        }
    }
}

/** `⋯` with the other approval modes, under an "Other modes" heading. */
@Composable
private fun OtherModes(modes: List<ExitPlanMode>, enabled: Boolean, wide: Boolean, decide: (LinkDecision) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val accent = ShellXTheme.colors.accentText
    Box {
        IconButton(
            onClick = { open = true },
            enabled = enabled,
            modifier = Modifier
                .then(if (wide) Modifier.fillMaxWidth() else Modifier)
                .sizeIn(minWidth = 50.dp, minHeight = 50.dp)
                .alpha(if (enabled) 1f else 0.4f)
                .background(accent.copy(alpha = 0.14f), RoundedCornerShape(12.dp))
                .testTag("pending.otherModes"),
            shape = RoundedCornerShape(12.dp),
            colors = IconButtonDefaults.iconButtonColors(contentColor = accent, disabledContentColor = accent),
        ) {
            Icon(Icons.Filled.MoreHoriz, contentDescription = stringResource(R.string.pending_plan_other_modes))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            Text(
                stringResource(R.string.pending_plan_other_modes),
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            HorizontalDivider()
            for (mode in modes) {
                DropdownMenuItem(
                    text = { Text(stringResource(PlanReviewSheet.title(mode))) },
                    onClick = {
                        open = false
                        decide(LinkDecision.ExitPlan(mode, null))
                    },
                )
            }
        }
    }
}

object PlanReviewSheet {
    /** `auto_accept` → "Auto-accept edits", `ultraplan` → "Ultraplan", anything else → "Approve". */
    @StringRes
    fun title(mode: ExitPlanMode): Int = when (mode) {
        ExitPlanMode.AUTO_ACCEPT -> R.string.pending_plan_auto_accept
        ExitPlanMode.ULTRAPLAN -> R.string.pending_plan_ultraplan
        else -> R.string.pending_plan_approve
    }
}
