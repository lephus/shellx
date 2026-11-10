package com.shellx.app.ui.workspaces

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import com.shellx.app.ui.components.isLargeText
import com.shellx.app.ui.components.shellXCard
import com.shellx.core.workspaces.WorkspaceRow

/**
 * One workspace as a one-line card on the home (`WorkspaceRowView.swift`): its name, and its git branch in monospace at
 * the end. At large text the branch goes under the name. [dimmed]: the Mac is not online, so this is its last known
 * list. The card is not a button itself: the row that holds it takes the click and merges its words.
 */
@Composable
fun WorkspaceRowView(row: WorkspaceRow, dimmed: Boolean = false, modifier: Modifier = Modifier) {
    val large = isLargeText()
    val branch = row.branch?.takeIf { it.isNotEmpty() }
    val content = modifier
        .testTag("workspace.row.${row.id.workspaceId}")
        .alpha(if (dimmed) 0.55f else 1f)
        .shellXCard(RoundedCornerShape(12.dp))
        .fillMaxWidth()
        .heightIn(min = 48.dp)
        .padding(horizontal = 12.dp, vertical = 10.dp)
    if (large) {
        Column(content, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Title(row.title, maxLines = 3)
            branch?.let { Branch(it, maxLines = 2, align = TextAlign.Start) }
        }
    } else {
        TitleAndBranch(content, title = { Title(row.title, maxLines = 1) }, branch = branch?.let { { Branch(it, 1, TextAlign.End) } })
    }
}

@Composable
private fun Title(title: String, maxLines: Int) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.onSurface,
        maxLines = maxLines,
        overflow = TextOverflow.Ellipsis,
    )
}

@Composable
private fun Branch(branch: String, maxLines: Int, align: TextAlign) {
    Text(
        text = branch,
        style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        maxLines = maxLines,
        overflow = if (maxLines == 1) TextOverflow.MiddleEllipsis else TextOverflow.Ellipsis,
        textAlign = align,
    )
}

/**
 * The name first and the branch at the end, on one baseline: the name takes what it needs while the branch keeps at
 * least 72 dp, then the branch gets the rest (cut in the middle).
 */
@Composable
private fun TitleAndBranch(modifier: Modifier, title: @Composable () -> Unit, branch: (@Composable () -> Unit)?) {
    Layout(content = { title(); branch?.invoke() }, modifier = modifier) { measurables, constraints ->
        val spacing = 8.dp.roundToPx()
        val minBranch = 72.dp.roundToPx()
        val width = constraints.maxWidth
        val hasBranch = measurables.size > 1
        val titleMax = if (hasBranch) (width - spacing - minBranch).coerceAtLeast(0) else width
        val titlePlaceable = measurables[0].measure(Constraints(maxWidth = titleMax))
        val branchPlaceable = if (hasBranch) {
            val room = (width - titlePlaceable.width - spacing).coerceAtLeast(minOf(minBranch, width))
            measurables[1].measure(Constraints(maxWidth = room))
        } else {
            null
        }
        val titleBaseline = titlePlaceable[FirstBaseline]
        val branchBaseline = branchPlaceable?.get(FirstBaseline) ?: titleBaseline
        val top = maxOf(titleBaseline, branchBaseline)
        val height = maxOf(
            top - titleBaseline + titlePlaceable.height,
            branchPlaceable?.let { top - branchBaseline + it.height } ?: 0,
        ).coerceAtLeast(constraints.minHeight)
        layout(width, height) {
            titlePlaceable.placeRelative(0, top - titleBaseline)
            branchPlaceable?.placeRelative(width - branchPlaceable.width, top - branchBaseline)
        }
    }
}
