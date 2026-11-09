package com.shellx.app.ui.pending

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
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
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.shellx.app.R
import com.shellx.app.ui.components.PrimaryButton
import com.shellx.app.ui.components.SecondaryButton
import com.shellx.app.ui.composer.MicButton
import com.shellx.app.ui.composer.VoiceStatusView
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.voice.LocalVoice
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.pending.DecisionStatus
import com.shellx.core.pending.QuestionDraft
import com.shellx.core.platform.CoreLog
import com.shellx.core.voice.VoiceInputModel
import com.shellx.core.voice.optionMatching
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.PendingQuestion
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

/**
 * Answers an agent's questions (`QuestionAnswerSheet.swift`): one page per question, its options as a checklist, and an
 * "Other…" row that opens a field for an answer in the user's own words. "Send" turns on once every question has an
 * answer that fits the wire (1024 bytes each): a field holding more, or picks that join to more, is counted and said,
 * never cut silently. When the item was decided elsewhere meanwhile, the sheet says so and nothing can be sent.
 *
 * With a mic (`LocalVoice`), "Answer by voice" (in the bottom bar, outside the list) listens: words that pick exactly one
 * option mark it; anything else becomes the "Other…" answer, shown in its field with "That didn't match an option".
 * Nothing is sent until Send. Focusing the "Other…" field cancels a dictation; so does leaving, and an answer that can
 * no longer change. Page, picks and typed text survive a recreated screen (RF 3).
 *
 * The initial-state parameters start a render test anywhere ([draft], [page], [typing], [freeText] by question id,
 * [voice], [unmatched]).
 */
@Composable
fun QuestionAnswerSheet(
    item: MachinePendingItem,
    state: PendingSheetState,
    send: (LinkDecision) -> Unit,
    close: () -> Unit,
    draft: QuestionDraft? = null,
    page: Int = 0,
    typing: Set<String> = emptySet(),
    freeText: Map<String, String> = emptyMap(),
    voice: VoiceInputModel? = null,
    unmatched: Set<String> = emptySet(),
) {
    val questionList = item.item.questions.orEmpty()
    var answers by rememberSaveable(stateSaver = QuestionAnswerSheet.draftSaver(questionList)) {
        mutableStateOf(freeText.entries.fold(draft ?: QuestionDraft(questionList)) { d, (id, text) -> d.setFreeText(id, text) })
    }
    var shownPage by rememberSaveable { mutableIntStateOf(page) }
    var open by rememberSaveable(stateSaver = StringSetSaver) { mutableStateOf(typing) }
    var typed by rememberSaveable(stateSaver = StringMapSaver) { mutableStateOf(freeText) }
    var noMatch by rememberSaveable(stateSaver = StringSetSaver) { mutableStateOf(unmatched) }
    // What TalkBack is told after a spoken answer (a polite live region).
    var announcement by remember { mutableStateOf("") }

    val env = LocalVoice.current
    val own = remember(env?.service, voice == null) {
        if (voice == null) env?.service?.makeModel(QuestionDraft.MAX_ANSWER_BYTES) else null
    }
    val model = voice ?: own
    val localScope = rememberCoroutineScope()
    val voiceScope = env?.scope ?: localScope
    val voiceState = model?.state?.collectAsStateWithLifecycle()?.value
    val focusManager = LocalFocusManager.current
    val fields = remember { HashMap<String, FocusRequester>() }
    var focusAsk by remember { mutableStateOf<String?>(null) }
    val res = LocalContext.current.resources

    val questions = answers.questions
    val question = questions.getOrNull(shownPage)
    val isLastPage = shownPage >= questions.size - 1
    // Answers can change until the decision is out or the item is gone.
    val editable = !state.handledElsewhere && state.status != DecisionStatus.Sending && state.status != DecisionStatus.Done
    val tooLong = QuestionAnswerSheet.tooLong(answers, typed)

    fun fieldText(q: PendingQuestion): String = typed[q.id] ?: answers.freeText(q.id)

    /** Opens the question's "Other…" field and its keyboard at once; a dictation in progress is then cancelled. */
    fun openOther(q: PendingQuestion) {
        open = open + q.id
        focusAsk = q.id
        model?.let { m -> voiceScope.launch { m.typeInstead() } }
    }

    /** A spoken answer marks the one option it picks; otherwise it is the "Other…" answer, in its field to be read. */
    fun answer(q: PendingQuestion, words: String) {
        focusManager.clearFocus()
        val option = q.optionMatching(words)
        if (option != null) {
            if (!answers.isSelected(q.id, option.label)) answers = answers.toggle(q.id, option.label)
            typed = typed - q.id
            noMatch = noMatch - q.id
            announcement = option.label
        } else {
            typed = typed + (q.id to words)
            answers = answers.setFreeText(q.id, words)
            open = open + q.id
            noMatch = noMatch + q.id
            announcement = res.getString(R.string.pending_question_voice_no_match)
        }
    }

    fun sendDraft() {
        val decision = answers.decision
        if (tooLong || decision == null) return
        focusManager.clearFocus()
        send(decision)
    }

    LaunchedEffect(focusAsk) {
        val id = focusAsk ?: return@LaunchedEffect
        try {
            fields[id]?.requestFocus()
        } catch (e: IllegalStateException) {
            CoreLog.log("question_focus_failed")
        }
        focusAsk = null
    }
    // A swipe up on the mic opens the "Other…" field.
    LaunchedEffect(model, voiceState?.wantsKeyboard) {
        if (model != null && voiceState?.wantsKeyboard == true) {
            model.wantsKeyboard = false
            question?.let { openOther(it) }
        }
    }
    // The answers can no longer change (the mic goes): the microphone stops.
    LaunchedEffect(model, editable) { if (!editable) model?.let { m -> voiceScope.launch { m.cancel() } } }
    // The sheet closed: the microphone never stays on behind it.
    DisposableEffect(model) { onDispose { model?.let { m -> voiceScope.launch { m.cancel() } } } }

    val title = if (questions.size > 1) {
        stringResource(R.string.pending_question_page, shownPage + 1, questions.size)
    } else {
        stringResource(R.string.pending_question_title)
    }
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        SheetTopBar(title, close)
        CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurface) {
            Column(
                Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text(
                    PendingCardView.headline(item, false, res, MaterialTheme.colorScheme.onSurfaceVariant),
                    style = MaterialTheme.typography.bodyMedium,
                )
                if (question != null) {
                    Prompt(question)
                    Options(
                        question, answers, editable, fieldText(question), question.id in open,
                        tooLongPicks = answers.isTooLong(question.id), unmatched = question.id in noMatch,
                        field = fields.getOrPut(question.id) { FocusRequester() },
                        pick = { label ->
                            answers = answers.toggle(question.id, label)
                            // A pick replaces the typed answer, in the field too.
                            typed = typed - question.id
                            noMatch = noMatch - question.id
                            focusManager.clearFocus()
                        },
                        other = { openOther(question) },
                        edit = { text ->
                            typed = typed + (question.id to text)
                            answers = answers.setFreeText(question.id, text)
                        },
                        focused = { model?.let { m -> voiceScope.launch { m.typeInstead() } } },
                    )
                }
            }
            BottomBar {
                if (model != null && editable && question != null) {
                    val level by (env?.meter?.level ?: remember { MutableStateFlow(0f) }).collectAsStateWithLifecycle()
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        VoiceStatusView(model, level)
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            MicButton(
                                model, R.string.pending_question_voice,
                                onOutcome = { answer(question, it.words) }, onKeyboard = { openOther(question) },
                            )
                            Text(
                                stringResource(R.string.pending_question_voice),
                                // The mic carries the same words for TalkBack.
                                modifier = Modifier.weight(1f).clearAndSetSemantics { },
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                PendingCardStatusLine(state.shownStatus, state.actionable, item.machineName, state.linkNote, retry = ::sendDraft)
                if (tooLong && !state.handledElsewhere) {
                    ErrorLine(stringResource(R.string.pending_question_too_long))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (shownPage > 0 && !state.handledElsewhere) {
                        SecondaryButton(onClick = { shownPage -= 1 }, modifier = Modifier.weight(1f)) {
                            Text(stringResource(R.string.pending_question_back), style = MaterialTheme.typography.bodyLarge)
                        }
                    }
                    when {
                        state.handledElsewhere -> PrimaryButton(onClick = close, modifier = Modifier.weight(1f)) {
                            Text(stringResource(R.string.common_close), style = MaterialTheme.typography.titleMedium)
                        }
                        !isLastPage -> PrimaryButton(
                            onClick = {
                                focusManager.clearFocus()
                                shownPage += 1
                            },
                            modifier = Modifier.weight(1f).testTag("pending.next"),
                            enabled = question?.let { answers.isAnswered(it.id) } ?: false,
                        ) { Text(stringResource(R.string.pending_question_next), style = MaterialTheme.typography.titleMedium) }
                        else -> PrimaryButton(
                            onClick = ::sendDraft,
                            modifier = Modifier.weight(1f).testTag("pending.send"),
                            enabled = state.canSend && answers.isComplete && !tooLong,
                        ) { Text(stringResource(R.string.pending_send), style = MaterialTheme.typography.titleMedium) }
                    }
                }
            }
        }
        Announcement(announcement)
    }
}

@Composable
private fun Prompt(question: PendingQuestion) {
    val accent = ShellXTheme.colors.accentText
    Column(
        Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(12.dp)).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        question.header?.takeIf { it.isNotEmpty() }?.let { header ->
            Text(
                header,
                modifier = Modifier.background(accent.copy(alpha = 0.14f), RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 2.dp),
                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                color = accent,
            )
        }
        Text(question.prompt, modifier = Modifier.semantics { heading() }, style = MaterialTheme.typography.titleMedium)
        Text(
            stringResource(if (question.multiSelect) R.string.pending_question_pick_many else R.string.pending_question_pick_one),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** The options as a checklist on a card, then "Other…" and its field, then what is wrong with the answer. */
@Composable
private fun Options(
    question: PendingQuestion,
    answers: QuestionDraft,
    editable: Boolean,
    text: String,
    typing: Boolean,
    tooLongPicks: Boolean,
    unmatched: Boolean,
    field: FocusRequester,
    pick: (String) -> Unit,
    other: () -> Unit,
    edit: (String) -> Unit,
    focused: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(12.dp))) {
            for (option in question.options) {
                val selected = answers.isSelected(question.id, option.label)
                ChoiceRow(
                    selected,
                    Modifier
                        .selectable(selected, enabled = editable, role = if (question.multiSelect) Role.Checkbox else Role.RadioButton) {
                            pick(option.label)
                        }
                        .testTag("pending.option")
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                ) {
                    Text(option.label, style = MaterialTheme.typography.bodyLarge)
                    option.description?.takeIf { it.isNotEmpty() }?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                HorizontalDivider(Modifier.padding(start = 12.dp), color = MaterialTheme.colorScheme.outlineVariant)
            }
            val answeredByText = QuestionDraft.freeTextBytes(text) > 0
            ChoiceRow(
                answeredByText,
                Modifier
                    .selectable(answeredByText, enabled = editable, role = Role.Button, onClick = other)
                    .testTag("pending.other")
                    .padding(horizontal = 12.dp, vertical = 6.dp),
            ) {
                Text(stringResource(R.string.pending_question_other), style = MaterialTheme.typography.bodyLarge)
            }
            if (typing || text.isNotEmpty()) {
                Column(Modifier.padding(start = 12.dp, end = 12.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    TextField(
                        value = text,
                        onValueChange = edit,
                        enabled = editable,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .focusRequester(field)
                            .onFocusChanged { if (it.isFocused) focused() }
                            .testTag("pending.otherField"),
                        placeholder = { Text(stringResource(R.string.pending_question_other_placeholder)) },
                        maxLines = 5,
                        shape = RoundedCornerShape(10.dp),
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = MaterialTheme.colorScheme.background,
                            unfocusedContainerColor = MaterialTheme.colorScheme.background,
                            disabledContainerColor = MaterialTheme.colorScheme.background,
                            focusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                            unfocusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                            disabledIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                        ),
                    )
                    ByteCounter(QuestionDraft.freeTextBytes(text), QuestionDraft.MAX_ANSWER_BYTES)
                }
            }
        }
        when {
            tooLongPicks -> Text(
                stringResource(R.string.pending_question_choices_too_long, answers.answerBytes(question.id), QuestionDraft.MAX_ANSWER_BYTES),
                style = MaterialTheme.typography.bodySmall,
                color = ShellXTheme.colors.statusError,
            )
            // Under the "Other…" field the spoken words went into.
            unmatched -> Row(
                Modifier.testTag("pending.voice.noMatch"),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                val accent = ShellXTheme.colors.accentText
                Icon(Icons.AutoMirrored.Outlined.HelpOutline, contentDescription = null, modifier = Modifier.size(16.dp), tint = accent)
                Text(stringResource(R.string.pending_question_voice_no_match), style = MaterialTheme.typography.bodySmall, color = accent)
            }
        }
    }
}

/** The sheets' bottom bar (the iPhone's `.bar`): on the cards' colour, a hairline over it, outside the scrolling part. */
@Composable
internal fun BottomBar(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainer)) {
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) { content() }
    }
}

/** A red line with a warning mark ("An answer is too long"). */
@Composable
internal fun ErrorLine(text: String) {
    val color = ShellXTheme.colors.statusError
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Outlined.ErrorOutline, contentDescription = null, modifier = Modifier.size(16.dp), tint = color)
        Text(text, style = MaterialTheme.typography.bodySmall, color = color)
    }
}

/** A polite live region TalkBack reads when [text] changes. */
@Composable
internal fun Announcement(text: String) {
    Box(
        Modifier.size(1.dp).semantics {
            liveRegion = LiveRegionMode.Polite
            if (text.isNotEmpty()) contentDescription = text
        },
    )
}

object QuestionAnswerSheet {
    /** Some answer does not fit: a field holds more than [QuestionDraft.MAX_ANSWER_BYTES] once trimmed, or a question's
     *  picks join to more. Send stays off and the sheet says why. */
    fun tooLong(draft: QuestionDraft, typed: Map<String, String>): Boolean = draft.questions.any { question ->
        draft.isTooLong(question.id) || QuestionDraft.freeTextBytes(typed[question.id] ?: "") > QuestionDraft.MAX_ANSWER_BYTES
    }

    /** Saves each question's picked labels and typed text; restores by replaying `toggle` / `setFreeText` on a fresh
     *  `QuestionDraft(questions)`. */
    fun draftSaver(questions: List<PendingQuestion>): Saver<QuestionDraft, Any> = Saver(
        save = { draft ->
            val picked = HashMap<String, ArrayList<String>>()
            val typed = HashMap<String, String>()
            for (question in draft.questions) {
                val labels = question.options.map { it.label }.filter { draft.isSelected(question.id, it) }.distinct()
                if (labels.isNotEmpty()) picked[question.id] = ArrayList(labels)
                draft.freeText(question.id).takeIf { it.isNotEmpty() }?.let { typed[question.id] = it }
            }
            arrayListOf<Any>(picked, typed)
        },
        restore = { saved ->
            val parts = saved as List<*>
            @Suppress("UNCHECKED_CAST")
            val picked = parts[0] as Map<String, List<String>>
            @Suppress("UNCHECKED_CAST")
            val typed = parts[1] as Map<String, String>
            var draft = QuestionDraft(questions)
            for ((id, labels) in picked) for (label in labels) draft = draft.toggle(id, label)
            for ((id, text) in typed) draft = draft.setFreeText(id, text)
            draft
        },
    )
}

/** A set of strings (question ids) kept across recreation. */
internal val StringSetSaver: Saver<Set<String>, ArrayList<String>> = Saver(save = { ArrayList(it) }, restore = { it.toSet() })

/** A map of strings (typed answers by question id) kept across recreation. */
internal val StringMapSaver: Saver<Map<String, String>, HashMap<String, String>> = Saver(save = { HashMap(it) }, restore = { it })
