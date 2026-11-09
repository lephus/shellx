package com.shellx.app.ui.home

import android.content.res.Resources
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.components.isLargeText
import com.shellx.app.ui.pending.PendingCardView
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.theme.StatusDot
import com.shellx.core.link.MachinePendingItem

/**
 * "Needs you · N" over a conversation (`NeedsYouBar.swift`): one line with the newest request's headline. A tap opens
 * the "Needs You" page, where the cards are; nothing is decided from here, so the conversation keeps its room. The
 * owner shows it only while something is pending. One TalkBack button (tag `home.needsYou`).
 */
@Composable
fun NeedsYouBar(items: List<MachinePendingItem>, showsMachineName: Boolean, open: () -> Unit, modifier: Modifier = Modifier) {
    val res = LocalContext.current.resources
    val large = isLargeText()
    val newest = items.maxByOrNull { it.item.createdAtMs }
    val title = stringResource(R.string.pending_section_title, items.size)
    val spoken = newest?.let { title + ", " + PendingCardView.spokenHeadline(it, showsMachineName, res) } ?: title
    val hint = stringResource(R.string.home_needs_you_hint)
    val shape = RoundedCornerShape(14.dp)
    val colors = ShellXTheme.colors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clip(shape)
            .background(colors.accent.copy(alpha = 0.12f), shape)
            .border(1.dp, colors.accent.copy(alpha = 0.35f), shape)
            .clickable(onClick = open)
            .testTag("home.needsYou")
            .clearAndSetSemantics {
                contentDescription = spoken
                role = Role.Button
                onClick(label = hint) { open(); true }
            }
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val heading = @Composable {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                StatusDot(colors.statusNeedsYou)
                Text(
                    title,
                    style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                    color = colors.accentText,
                    maxLines = 1,
                    softWrap = false,
                )
            }
        }
        val headline = @Composable { line: Modifier ->
            newest?.let {
                Text(
                    NeedsYouBar.headline(it, showsMachineName, res, MaterialTheme.colorScheme.onSurfaceVariant),
                    modifier = line,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = if (large) 2 else 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        if (large) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                heading()
                headline(Modifier.fillMaxWidth())
            }
        } else {
            heading()
            headline(Modifier.weight(1f))
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, modifier = Modifier.size(20.dp),
            tint = colors.accentText,
        )
    }
}

object NeedsYouBar {
    /** "web · wants to run Bash": the card's headline without the agent, so what is asked fits on the one line
     *  (TalkBack still hears the agent). */
    fun headline(item: MachinePendingItem, showsMachineName: Boolean, res: Resources, secondary: Color): AnnotatedString {
        val parts = listOfNotNull(item.machineName.takeIf { showsMachineName }, PendingCardView.kindText(item.item, res))
        return PendingCardView.workspaceThen(item.item.workspaceTitle, parts, secondary)
    }
}
