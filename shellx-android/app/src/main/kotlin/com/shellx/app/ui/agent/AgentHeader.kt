package com.shellx.app.ui.agent

import android.content.res.Resources
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.theme.AgentStateStyle
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.theme.StatusDot
import com.shellx.app.ui.theme.StatusTone
import com.shellx.app.ui.theme.color
import com.shellx.core.home.AgentStatusRow
import com.shellx.link.core.AgentState

/**
 * The top of an agent's screen, under the workspace in the top bar (`AgentHeader.swift`): "Claude Code · MacBook Pro",
 * then the state's dot and words ("Running for 4 minutes", "Needs you", "Mac offline"). A session the Mac no longer has
 * says so. One line when both fit, otherwise the state under the place (never cut). One TalkBack element.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AgentHeader(place: String, row: AgentStatusRow?, gone: Boolean, offline: Boolean, modifier: Modifier = Modifier) {
    val res = LocalContext.current.resources
    val status = AgentHeader.status(row, gone, offline, res)
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    FlowRow(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .padding(vertical = 2.dp)
            // The tag goes before the clearing: a tag after it is cleared with the rest.
            .testTag("agent.header")
            .clearAndSetSemantics { contentDescription = listOfNotNull(place, status.text).joinToString(", ") },
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
        itemVerticalAlignment = Alignment.CenterVertically,
    ) {
        Text(place, modifier = Modifier.padding(end = 8.dp), style = MaterialTheme.typography.bodyMedium, color = secondary)
        status.text?.let { text ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                StatusDot(status.tone?.color() ?: Color.Transparent)
                val waiting = row?.online == true && row.state == AgentState.NEEDS_INPUT
                Text(text, style = MaterialTheme.typography.bodyMedium, color = if (waiting) ShellXTheme.colors.accentText else secondary)
            }
        }
    }
}

object AgentHeader {
    /** The words and the dot's tone (null: nothing to say). */
    data class Status(val text: String?, val tone: StatusTone?)

    /** Gone first, then the session's state (offline when its Mac is), then a Mac that is offline before it ever listed
     *  the session. */
    fun status(row: AgentStatusRow?, gone: Boolean, offline: Boolean, res: Resources): Status {
        if (gone) return Status(res.getString(R.string.agent_gone), StatusTone.IDLE)
        if (row != null) {
            val style = AgentStateStyle.of(row, res)
            return Status(style.text, style.tone)
        }
        if (offline) return Status(res.getString(R.string.agent_state_offline), StatusTone.IDLE)
        return Status(null, null)
    }
}
