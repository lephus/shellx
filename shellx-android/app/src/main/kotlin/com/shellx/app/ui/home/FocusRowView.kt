package com.shellx.app.ui.home

import android.content.res.Resources
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.components.isLargeText
import com.shellx.app.ui.components.waitingBorder
import com.shellx.app.ui.theme.AgentStateStyle
import com.shellx.app.ui.theme.AppLanguage
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.theme.StatusDot
import com.shellx.app.ui.theme.StatusTone
import com.shellx.app.ui.theme.color
import com.shellx.core.home.AgentStatusRow
import com.shellx.core.home.FocusItem
import com.shellx.core.pending.AgentLabel
import java.util.Locale
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.minutes

/** The group a session's card is in: it sets the dot, the tag and the outline. IDLE is a live session that finished
 *  its turn more than an hour ago (the agents outside workspaces). */
enum class FocusKind { NEEDS_YOU, RUNNING, JUST_DONE, ENDED, IDLE }

/** `FocusRowView.swift`'s words. [locale] is the app's language ([AppLanguage]), for the durations. */
class FocusRowText(private val res: Resources, private val locale: Locale) {
    /** "Needs you", how long the session has been running ("8 minutes"; "Running" when the Mac did not say since
     *  when), "Done", and nothing for an ended or idle session. */
    fun tag(item: FocusItem, kind: FocusKind, nowMs: Long): String? = when (kind) {
        FocusKind.NEEDS_YOU -> res.getString(R.string.agent_state_needs_you)
        FocusKind.RUNNING -> AgentStatusRow.of(item.session, nowMs).elapsed?.let(::ageText)
            ?: res.getString(R.string.agent_state_running)
        FocusKind.JUST_DONE -> res.getString(R.string.agent_state_done)
        FocusKind.ENDED, FocusKind.IDLE -> null
    }

    /** The time at the end of the sub line, null when the Mac gave none: needs you counts from when the agent began to
     *  wait ("2 minutes"); just done, ended and idle say "12 minutes ago"; running has its time in the tag. */
    fun timeText(item: FocusItem, kind: FocusKind, nowMs: Long): String? {
        val session = item.session.session
        fun since(ms: Long?): Duration? = ms?.let { maxOf(0, nowMs - it).milliseconds }
        return when (kind) {
            FocusKind.RUNNING -> null
            FocusKind.NEEDS_YOU -> (since(session.stateSinceMs) ?: since(session.lastActivityMs))?.let(::ageText)
            FocusKind.JUST_DONE -> since(item.finishedAtMs)?.let(::ago)
            FocusKind.ENDED -> (since(session.stateSinceMs) ?: since(session.lastActivityMs))?.let(::ago)
            FocusKind.IDLE -> since(session.lastActivityMs)?.let(::ago)
        }
    }

    /** "shellx · Claude Code", then the Mac's name when [showsMachineName], then the time ([timeText]). A session
     *  outside any workspace starts at the agent. */
    fun subLine(item: FocusItem, kind: FocusKind, nowMs: Long, showsMachineName: Boolean): String {
        val session = item.session
        return listOfNotNull(
            session.session.workspaceTitle,
            AgentLabel.of(session.session.agent).text,
            session.machineName.takeIf { showsMachineName },
            timeText(item, kind, nowMs),
        ).filter { it.isNotEmpty() }.joinToString(" · ")
    }

    /** A duration in whole minutes, at least one: the cards redraw every 30 seconds, so a seconds count would freeze
     *  between redraws, and a clock older than the start would show a negative age. */
    fun ageText(elapsed: Duration): String =
        AgentStateStyle.elapsedText(maxOf(1L, elapsed.inWholeSeconds.coerceAtLeast(0) / 60).minutes, locale)

    private fun ago(elapsed: Duration): String = res.getString(R.string.home_ago, ageText(elapsed))

    companion object {
        /** The multicolour waiting border runs around the card: it is in the needs-you group and its Mac is online, so
         *  the answer can be given. */
        fun showsWaitingBorder(item: FocusItem, kind: FocusKind): Boolean = kind == FocusKind.NEEDS_YOU && item.session.online

        /** What the agent asks, in quotes, on a needs-you card; null otherwise. */
        fun quotedQuestion(item: FocusItem, kind: FocusKind): String? {
            val question = item.question
            if (kind != FocusKind.NEEDS_YOU || question.isNullOrEmpty()) return null
            return "“$question”"
        }

        fun tone(kind: FocusKind): StatusTone = when (kind) {
            FocusKind.NEEDS_YOU -> StatusTone.NEEDS_YOU
            FocusKind.RUNNING -> StatusTone.RUNNING
            FocusKind.JUST_DONE -> StatusTone.DONE
            FocusKind.ENDED, FocusKind.IDLE -> StatusTone.IDLE
        }
    }
}

private const val CARD_RADIUS = 14

/**
 * One agent session as a card (`FocusRowView.swift`, mockup A): a dot in the group's colour, the session's name and its
 * tag; under them `workspace · agent`, the Mac when [showsMachineName], and how long; and, while it waits for the user,
 * its question in quotes. A needs-you card of an online Mac has the waiting border; a card of a Mac that is not online
 * fades. [trailingInset] keeps room at the end for a button the list draws over the card.
 *
 * The card is not a button itself: the row that holds it ([com.shellx.app.ui.components.ActionRow]) takes the click and
 * merges the card's words into one TalkBack element, so the card adds no merge boundary of its own.
 */
@Composable
fun FocusRowView(
    item: FocusItem,
    kind: FocusKind,
    nowMs: Long,
    showsMachineName: Boolean,
    modifier: Modifier = Modifier,
    trailingInset: Dp = 0.dp,
) {
    val words = FocusRowText(LocalContext.current.resources, AppLanguage.current())
    val large = isLargeText()
    val waiting = FocusRowText.showsWaitingBorder(item, kind)
    val tone = FocusRowText.tone(kind).color()
    val shape = RoundedCornerShape(CARD_RADIUS.dp)
    val outline = if (kind == FocusKind.NEEDS_YOU) {
        ShellXTheme.colors.accent.copy(alpha = 0.45f)
    } else {
        MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f)
    }
    val tag = words.tag(item, kind, nowMs)
    Column(
        modifier = modifier
            .testTag("home.agent.${item.session.machineId}.${item.session.session.sessionId}")
            .alpha(if (item.session.online) 1f else 0.55f)
            .waitingBorder(waiting, CARD_RADIUS.dp)
            .background(ShellXTheme.colors.surface, shape)
            .then(if (waiting) Modifier else Modifier.border(1.dp, outline, shape))
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .padding(start = 12.dp, end = 12.dp + trailingInset, top = 10.dp, bottom = 10.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        if (large) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                NameLine(item.name, tone, maxLines = 3)
                tag?.let { Chip(it, tone) }
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.weight(1f)) { NameLine(item.name, tone, maxLines = 1) }
                tag?.let { Chip(it, tone) }
            }
        }
        Text(
            text = words.subLine(item, kind, nowMs, showsMachineName),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = if (large) 4 else 2,
            overflow = TextOverflow.Ellipsis,
        )
        FocusRowText.quotedQuestion(item, kind)?.let { question ->
            Text(
                text = question,
                modifier = Modifier.padding(top = 1.dp),
                style = MaterialTheme.typography.bodySmall,
                color = ShellXTheme.colors.accentText,
                maxLines = if (large) 4 else 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun NameLine(name: String, tone: androidx.compose.ui.graphics.Color, maxLines: Int) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        StatusDot(tone)
        Text(
            text = name,
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = maxLines,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** The tag: in the group's colour on 14 % of it, digits of equal width. */
@Composable
private fun Chip(text: String, tone: androidx.compose.ui.graphics.Color) {
    Text(
        text = text,
        modifier = Modifier
            .background(tone.copy(alpha = 0.14f), RoundedCornerShape(6.dp))
            .padding(horizontal = 7.dp, vertical = 2.dp),
        style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"),
        color = tone,
        maxLines = 1,
        softWrap = false,
    )
}
