package com.shellx.app.ui.workspaces

import android.content.res.Resources
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.components.WaitingBorder
import com.shellx.app.ui.components.waitingBorder
import com.shellx.app.ui.theme.AgentStateStyle
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.theme.StatusDot
import com.shellx.app.ui.theme.color
import com.shellx.core.home.AgentStatusRow
import com.shellx.core.pending.AgentLabel
import com.shellx.core.workspaces.WorkspacePane
import kotlin.math.abs

private const val CHIP_RADIUS = 10

/** Frames [centre] waits for the row's first layout. */
private const val FIRST_LAYOUT_FRAMES = 10

/**
 * The row of chips under the workspace screen's top bar (`PaneChips.swift`): one per terminal of the workspace, in the
 * Mac's order, the one shown highlighted. An agent's chip has a dot in its state's tone, and while that agent waits for
 * the user the waiting border runs around it. The row scrolls sideways and keeps the chip shown in its middle.
 *
 * While [close] is set, a long press on a chip opens a menu with "Close Tab…" (red; the caller confirms first); without
 * it a chip has no menu. [trailing] comes after the last chip (plan 3G's "＋").
 */
@Composable
fun PaneChips(
    panes: List<WorkspacePane>,
    selected: String?,
    nowMs: Long,
    select: (String) -> Unit,
    close: ((WorkspacePane) -> Unit)? = null,
    modifier: Modifier = Modifier,
    trailing: @Composable () -> Unit = {},
) {
    val list = rememberLazyListState()
    // The first time at once, then sliding (the iPhone's `onAppear` and `onChange`).
    val placed = remember { BooleanArray(1) }
    LaunchedEffect(selected, panes.map { it.id }) {
        val index = panes.indexOfFirst { it.id == selected }
        if (index < 0) return@LaunchedEffect
        list.centre(index, animated = placed[0])
        placed[0] = true
    }
    LazyRow(
        state = list,
        modifier = modifier.testTag("workspace.chips"),
        contentPadding = PaddingValues(horizontal = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        itemsIndexed(panes, key = { _, pane -> pane.id }) { _, pane ->
            Chip(pane, pane.id == selected, nowMs, select, close)
        }
        item(key = "trailing") { trailing() }
    }
}

/** Scrolls item [index] to the middle of the row, as far as the row's ends allow. */
private suspend fun LazyListState.centre(index: Int, animated: Boolean) {
    // Before the first layout there is nothing to measure against; frames resume outside a layout pass. A row that
    // never lays out (no room) is left alone rather than asked for frames for ever.
    var frames = 0
    while (layoutInfo.visibleItemsInfo.isEmpty()) {
        if (frames++ == FIRST_LAYOUT_FRAMES) return
        withFrameNanos { }
    }
    fun shown() = layoutInfo.visibleItemsInfo.firstOrNull { it.index == index }
    val item = shown() ?: run {
        if (animated) animateScrollToItem(index) else scrollToItem(index)
        shown()
    } ?: return
    val info = layoutInfo
    val off = item.offset + item.size / 2f - (info.viewportStartOffset + info.viewportEndOffset) / 2f
    if (abs(off) < 1f) return
    if (animated) animateScrollBy(off) else scrollBy(off)
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Chip(pane: WorkspacePane, isSelected: Boolean, nowMs: Long, select: (String) -> Unit, close: ((WorkspacePane) -> Unit)?) {
    val res = LocalContext.current.resources
    val label = PaneChips.label(pane, res)
    val state = PaneChips.state(pane, nowMs, res)
    val waiting = PaneChips.showsWaitingBorder(pane)
    val colors = ShellXTheme.colors
    val shape = RoundedCornerShape(CHIP_RADIUS.dp)
    var menu by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    Box {
        // The touch row is 48 dp tall; the chip itself is smaller.
        Box(
            modifier = Modifier
                .heightIn(min = 48.dp)
                .clip(shape)
                .combinedClickable(
                    onClick = { select(pane.id) },
                    onLongClick = close?.let {
                        {
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            menu = true
                        }
                    },
                )
                .testTag("workspace.chip.${pane.id}")
                .clearAndSetSemantics {
                    contentDescription = label
                    state?.text?.let { stateDescription = it }
                    selected = isSelected
                    role = Role.Tab
                },
            contentAlignment = Alignment.Center,
        ) {
            Row(
                modifier = Modifier
                    .background(if (isSelected) colors.accent.copy(alpha = 0.12f) else MaterialTheme.colorScheme.surfaceContainer, shape)
                    .then(
                        // The waiting border is 2 dp and covers the 1 dp outline, which is left out under it.
                        if (waiting) {
                            Modifier
                        } else {
                            Modifier.border(
                                1.dp, if (isSelected) colors.accent.copy(alpha = 0.45f) else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f),
                                shape,
                            )
                        },
                    )
                    .waitingBorder(waiting, CHIP_RADIUS.dp)
                    .padding(horizontal = 12.dp, vertical = 7.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                state?.tone?.let { StatusDot(it.color()) }
                Text(
                    label,
                    style = MaterialTheme.typography.bodyMedium.copy(fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal),
                    color = if (isSelected) colors.accentText else MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                )
            }
        }
        if (close != null) {
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                val red = colors.statusError
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.terminal_close_menu), color = red) },
                    leadingIcon = { Icon(Icons.Filled.Close, contentDescription = null, tint = red) },
                    onClick = {
                        menu = false
                        close(pane)
                    },
                )
            }
        }
    }
}

/**
 * ＋ after the last chip (`PaneChips.swift`'s add chip): a new terminal tab in this workspace on the Mac. 3E's chip shape
 * on surfaceContainer, a 48 dp touch target, dimmed while not [enabled] (the Mac is not online, or a new tab is on its
 * way). Read as "New Terminal"; tag `workspace.chip.add`.
 */
@Composable
fun NewTerminalChip(enabled: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(CHIP_RADIUS.dp)
    val label = stringResource(R.string.terminal_new)
    Box(
        modifier = Modifier
            .heightIn(min = 48.dp)
            .widthIn(min = 48.dp)
            .clip(shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .testTag("workspace.chip.add")
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .alpha(if (enabled) 1f else 0.4f)
                .background(MaterialTheme.colorScheme.surfaceContainer, shape)
                .border(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f), shape)
                .padding(horizontal = 12.dp, vertical = 7.dp),
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurface)
        }
    }
}

object PaneChips {
    /** What a chip says: the tab's name on the Mac; for a tab with none (a Mac that shrank its list to fit), the
     *  agent's name, or "Terminal". */
    fun label(pane: WorkspacePane, res: Resources): String {
        if (pane.title.isNotEmpty()) return pane.title
        return pane.session?.let { AgentLabel.of(it.session.agent).text } ?: res.getString(R.string.workspace_chip_shell)
    }

    /** The state of the agent in the pane, as the chip's dot and spoken words; null for a shell, and for a state this
     *  app does not know. */
    fun state(pane: WorkspacePane, nowMs: Long, res: Resources): AgentStateStyle? {
        val session = pane.session ?: return null
        val style = AgentStateStyle.of(AgentStatusRow.of(session, nowMs), res)
        return if (style.tone == null) null else style
    }

    /** The waiting border runs around the chip: it runs an agent that waits for the user's answer, on a Mac that is
     *  online. Never for a shell, nor for an agent at work, done or ended. */
    fun showsWaitingBorder(pane: WorkspacePane): Boolean {
        val session = pane.session ?: return false
        return WaitingBorder.isActive(session.session.state, session.online)
    }
}
