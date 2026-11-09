package com.shellx.app.ui.pending

import android.content.res.Resources
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowCircleDown
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Dangerous
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.MobileOff
import androidx.compose.material.icons.outlined.WifiOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.components.Spinner
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.theme.StatusTone
import com.shellx.app.ui.theme.color
import com.shellx.core.pending.DecisionFailure
import com.shellx.core.pending.DecisionStatus
import com.shellx.core.pending.PendingSheetModel

/**
 * The line on a card (and in its sheet) that says what became of the decision, or why the buttons are off
 * (`PendingCardStatusLine.swift`). Nothing when there is nothing to say. Its words and mark are one TalkBack element;
 * "Try again" stays its own button.
 */
@Composable
fun PendingCardStatusLine(
    status: DecisionStatus?,
    actionable: Boolean,
    machineName: String,
    linkNote: PendingSheetModel.LinkNote? = null,
    retry: () -> Unit = {},
) {
    val res = LocalContext.current.resources
    val line = PendingCardStatusLine.line(status, actionable, machineName, linkNote, res = res) ?: return
    Row(
        modifier = Modifier.fillMaxWidth().heightIn(min = 20.dp).semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(Modifier.clearAndSetSemantics {}) {
            when (val mark = line.mark) {
                PendingCardStatusLine.Mark.Progress -> Spinner(Modifier.size(14.dp))
                is PendingCardStatusLine.Mark.Symbol -> Icon(mark.icon, contentDescription = null, Modifier.size(16.dp), tint = mark.tone.color())
            }
        }
        Text(
            text = line.text,
            modifier = Modifier.weight(1f, fill = false),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (line.offersRetry) {
            TextButton(onClick = retry, modifier = Modifier.heightIn(min = 48.dp).testTag("pending.retry")) {
                Text(
                    stringResource(R.string.pending_status_retry),
                    style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold),
                    color = ShellXTheme.colors.accentText,
                )
            }
        }
    }
}

object PendingCardStatusLine {
    /** The mark in front of the words: a spinner, or an icon in a status tone. */
    sealed interface Mark {
        data object Progress : Mark

        data class Symbol(val icon: ImageVector, val tone: StatusTone) : Mark
    }

    /** What the line says; also what TalkBack reads. "Try again" follows the text when [offersRetry]. */
    data class Line(val text: String, val mark: Mark, val offersRetry: Boolean = false)

    /**
     * The line for a decision's status and the card's link. A failure says more than the link, so it wins; with no
     * decision out, a card that cannot act says it is reconnecting, and a sheet says what [linkNote] gives (offline, or
     * to be paired again: never "handled elsewhere").
     */
    fun line(
        status: DecisionStatus?,
        actionable: Boolean,
        machineName: String,
        linkNote: PendingSheetModel.LinkNote? = null,
        res: Resources,
    ): Line? = when (status) {
        DecisionStatus.Sending -> Line(res.getString(R.string.pending_status_sending), Mark.Progress)
        DecisionStatus.HandledElsewhere ->
            Line(res.getString(R.string.pending_status_handled_elsewhere), Mark.Symbol(Icons.Outlined.CheckCircle, StatusTone.IDLE))
        is DecisionStatus.Failed -> when (status.failure) {
            DecisionFailure.OFFLINE -> offline(machineName, res)
            DecisionFailure.NO_ANSWER -> Line(
                res.getString(R.string.pending_status_no_answer), Mark.Symbol(Icons.Outlined.ErrorOutline, StatusTone.ERROR),
                offersRetry = actionable,
            )
            DecisionFailure.REJECTED ->
                Line(res.getString(R.string.pending_status_rejected), Mark.Symbol(Icons.Outlined.Dangerous, StatusTone.ERROR))
        }
        DecisionStatus.Done, null -> if (actionable) {
            null
        } else {
            when (linkNote) {
                PendingSheetModel.LinkNote.OFFLINE -> offline(machineName, res)
                PendingSheetModel.LinkNote.NEEDS_PAIRING -> Line(
                    res.getString(R.string.pending_status_needs_pairing, machineName), Mark.Symbol(Icons.Outlined.MobileOff, StatusTone.IDLE),
                )
                PendingSheetModel.LinkNote.NEEDS_UPDATE ->
                    Line(res.getString(R.string.machine_state_needs_update), Mark.Symbol(Icons.Outlined.ArrowCircleDown, StatusTone.IDLE))
                PendingSheetModel.LinkNote.RECONNECTING, null -> Line(res.getString(R.string.pending_status_reconnecting), Mark.Progress)
            }
        }
    }

    private fun offline(machineName: String, res: Resources): Line =
        Line(res.getString(R.string.pending_status_offline, machineName), Mark.Symbol(Icons.Outlined.WifiOff, StatusTone.IDLE))
}
