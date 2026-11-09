package com.shellx.app.ui.agent

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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.outlined.Build
import androidx.compose.material.icons.outlined.Psychology
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.pending.PlanMarkdownText
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.link.core.ChatEntry
import com.shellx.link.core.ChatEntryKind
import com.shellx.link.core.ChatEntryRole

/**
 * One entry of an agent's chat, drawn by its kind (`ChatEntryRow.swift`):
 * - prose: the user's on the right in a bubble, as typed; the agent's on the left from its Markdown ([PlanMarkdownText]);
 *   another role's in `onSurfaceVariant`;
 * - thought: collapsed under "Thinking"; a tap shows the text;
 * - tool use: one line, the tool's name and its input in monospace; a tap shows all of it;
 * - status: centred, small; anything else: small, grey.
 *
 * An entry the Mac cut short ends with "… (cut; see it in full on the Mac)" (tag `agent.entry.cut`), hidden from
 * TalkBack: the marker is part of the entry's one element ([ChatEntryRow.accessibilityText]). The row is tagged
 * `agent.entry.<id>`.
 */
@Composable
fun ChatEntryRow(entry: ChatEntry, agent: String, modifier: Modifier = Modifier, initiallyExpanded: Boolean = false) {
    val res = LocalContext.current.resources
    val label = ChatEntryRow.accessibilityText(entry, agent, res)
    val mine = entry.role == ChatEntryRole.USER && entry.kind == ChatEntryKind.PROSE
    val status = entry.kind == ChatEntryKind.STATUS
    var expanded by rememberSaveable(entry.id) { mutableStateOf(initiallyExpanded) }
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Column(
        modifier = modifier.fillMaxWidth().padding(start = if (mine) 40.dp else 0.dp).testTag("agent.entry.${entry.id}"),
        horizontalAlignment = when {
            mine -> Alignment.End
            status -> Alignment.CenterHorizontally
            else -> Alignment.Start
        },
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        val spoken = Modifier.clearAndSetSemantics { contentDescription = label }
        when {
            mine -> SelectionContainer(spoken) {
                Text(
                    entry.text,
                    modifier = Modifier
                        .background(ShellXTheme.colors.bubbleMine, RoundedCornerShape(14.dp, 14.dp, 4.dp, 14.dp))
                        .padding(horizontal = 12.dp, vertical = 9.dp),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                )
            }
            entry.kind == ChatEntryKind.PROSE -> Box(spoken) {
                PlanMarkdownText(
                    entry.text,
                    color = if (entry.role == ChatEntryRole.AGENT) MaterialTheme.colorScheme.onSurface else secondary,
                )
            }
            entry.kind == ChatEntryKind.THOUGHT -> Thought(entry, label, expanded) { expanded = !expanded }
            entry.kind == ChatEntryKind.TOOL_USE -> ToolUse(entry, label, expanded) { expanded = !expanded }
            status -> SelectionContainer(spoken) {
                Text(entry.text, style = MaterialTheme.typography.bodySmall, color = secondary, textAlign = TextAlign.Center)
            }
            else -> SelectionContainer(spoken) { Text(entry.text, style = MaterialTheme.typography.bodySmall, color = secondary) }
        }
        if (entry.truncated == true) {
            // TalkBack hears it once, at the end of the entry's own element.
            Text(
                stringResource(R.string.agent_cut),
                modifier = Modifier.testTag("agent.entry.cut").clearAndSetSemantics { },
                style = MaterialTheme.typography.labelSmall,
                color = secondary,
                textAlign = if (mine) TextAlign.End else TextAlign.Start,
            )
        }
    }
}

/** "Thinking", collapsed; its text, once opened, is read on its own. */
@Composable
private fun Thought(entry: ChatEntry, label: String, expanded: Boolean, toggle: () -> Unit) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Column(Modifier.fillMaxWidth().testTag("agent.entry.thought")) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .clip(RoundedCornerShape(8.dp))
                .clickable(onClick = toggle)
                .clearAndSetSemantics {
                    contentDescription = label
                    role = Role.Button
                    onClick { toggle(); true }
                },
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Outlined.Psychology, contentDescription = null, modifier = Modifier.size(20.dp), tint = secondary)
            Text(stringResource(R.string.agent_thought), modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, color = secondary)
            Icon(if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, contentDescription = null, tint = secondary)
        }
        if (expanded) {
            SelectionContainer {
                Text(entry.text, modifier = Modifier.fillMaxWidth().padding(top = 2.dp), style = MaterialTheme.typography.bodyMedium, color = secondary)
            }
        }
    }
}

/** One line: the tool's name in SemiBold, its input in monospace; a tap shows all of it. */
@Composable
private fun ToolUse(entry: ChatEntry, label: String, expanded: Boolean, toggle: () -> Unit) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val hint = stringResource(R.string.agent_tool_expand_hint)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f))
            .clickable(onClick = toggle)
            .testTag("agent.entry.tool")
            .clearAndSetSemantics {
                contentDescription = label
                role = Role.Button
                if (!expanded) stateDescription = hint
                onClick { toggle(); true }
            }
            .padding(horizontal = 10.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = if (expanded) Alignment.Top else Alignment.CenterVertically,
    ) {
        Icon(Icons.Outlined.Build, contentDescription = null, modifier = Modifier.size(16.dp), tint = secondary)
        entry.toolName?.takeIf { it.isNotEmpty() }?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = MaterialTheme.colorScheme.onSurface)
        }
        Text(
            entry.text,
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
            color = secondary,
            maxLines = if (expanded) Int.MAX_VALUE else 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

object ChatEntryRow {
    /**
     * What TalkBack reads for the entry's one element: who wrote it, its text, and the cut marker when the Mac cut it
     * (the marker's own text is hidden). A thought's element is its "Thinking" row.
     */
    fun accessibilityText(entry: ChatEntry, agent: String, res: Resources): String {
        val parts = ArrayList<String>()
        parts += when {
            entry.role == ChatEntryRole.USER && entry.kind == ChatEntryKind.PROSE -> "${res.getString(R.string.home_sender_you)}: ${entry.text}"
            entry.role == ChatEntryRole.AGENT && entry.kind == ChatEntryKind.PROSE -> "$agent: ${entry.text}"
            entry.kind == ChatEntryKind.TOOL_USE -> listOfNotNull(entry.toolName, entry.text).filter { it.isNotEmpty() }.joinToString(": ")
            entry.kind == ChatEntryKind.THOUGHT -> res.getString(R.string.agent_thought)
            else -> entry.text
        }
        if (entry.truncated == true) parts += res.getString(R.string.agent_cut)
        return parts.joinToString(" ")
    }
}
