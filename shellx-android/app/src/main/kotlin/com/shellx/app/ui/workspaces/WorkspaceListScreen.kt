package com.shellx.app.ui.workspaces

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.ArrowCircleUp
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.components.ActionRow
import com.shellx.app.ui.components.ConfirmDialog
import com.shellx.app.ui.components.RowActionKind
import com.shellx.app.ui.components.RowActionPlan
import com.shellx.app.ui.components.RowActions
import com.shellx.app.ui.components.SectionTitle
import com.shellx.app.ui.components.SessionRefSaver
import com.shellx.app.ui.components.WorkspaceRefSaver
import com.shellx.app.ui.components.menuAction
import com.shellx.app.ui.components.shellXCard
import com.shellx.app.ui.components.swipeAction
import com.shellx.app.ui.home.FocusKind
import com.shellx.app.ui.home.FocusRowView
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.home.FocusItem
import com.shellx.core.home.HomeFocus
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.MachineSession
import com.shellx.core.link.SessionRef
import com.shellx.core.workspaces.WorkspaceRef
import kotlinx.coroutines.launch

/** What the home's controls do (`WorkspaceListScreen.Actions`). */
class WorkspaceListScreenActions(
    val openWorkspace: (WorkspaceRef) -> Unit = {},
    /** ＋ on the Mac with this id. */
    val create: (String) -> Unit = {},
    /** The workspace's new name, cleaned and not empty. */
    val rename: (WorkspaceRef, String) -> Unit = { _, _ -> },
    /** Confirmed: close the workspace and its terminals. */
    val close: (WorkspaceRef) -> Unit = {},
    /** Confirmed: close the terminal tab the agent runs in on its Mac. */
    val closeAgent: (SessionRef) -> Unit = {},
    /** Hide a session gone from its Mac on this phone; nothing is sent to the Mac. */
    val removeFromPhone: (MachineSession) -> Unit = {},
    val openAgent: (SessionRef) -> Unit = {},
    val openPending: () -> Unit = {},
    val openSettings: () -> Unit = {},
    val openMachines: () -> Unit = {},
    val openOtherSessions: (String) -> Unit = {},
    /** The "Ended · N" fold. */
    val openEnded: () -> Unit = {},
    /** Pull to refresh: runs until the Macs answered. */
    val refresh: suspend () -> Unit = {},
)

/** The room around a card, here and in the session lists, so a card sits the same distance from the edges on every
 *  page. */
internal val CardInsets = PaddingValues(horizontal = 12.dp, vertical = 3.dp)

/**
 * The app's home, "ShellX" (`WorkspaceListScreen.swift`, mockup A), from plain values so render tests can show any
 * state; [WorkspaceListView] feeds it.
 * - The top bar: the bell with how many requests wait, ＋ (a menu of the Macs when several take commands) and Settings.
 * - "Needs you · N", "Running · N" and "Just finished · N": a [FocusRowView] card per session, each group only while it
 *   has some; [HomeFocus.isQuiet] shows one muted line. A card opens its session; it swipes to Close (asks first) for
 *   [closableAgents] and to "Remove from This Phone" (does not ask) for [removableAgents].
 * - "Workspaces": per Mac its header (opens Your Macs), then its workspace cards (swipe to close, long press to rename
 *   or close, on Macs that take commands), then "Agents outside workspaces · N".
 * - Last, "Ended · N" while some sessions ended in the last hours.
 *
 * Pulling the list down asks the Macs for their workspaces again. An open confirmation or rename keeps its target
 * across recreation; a target that went away closes it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkspaceListScreen(
    groups: List<WorkspaceGroup>,
    focus: HomeFocus,
    pending: List<MachinePendingItem>,
    nowMs: Long,
    creating: Boolean = false,
    notice: Notice? = null,
    showsMachineNames: Boolean = false,
    closableAgents: Set<SessionRef> = emptySet(),
    removableAgents: Set<SessionRef> = emptySet(),
    actions: WorkspaceListScreenActions = WorkspaceListScreenActions(),
    alert: WorkspaceAlert? = null,
    onAlertDismissed: () -> Unit = {},
) {
    var renamingRef by rememberSaveable(stateSaver = WorkspaceRefSaver) { mutableStateOf<WorkspaceRef?>(null) }
    var closingRef by rememberSaveable(stateSaver = WorkspaceRefSaver) { mutableStateOf<WorkspaceRef?>(null) }
    var closingAgentRef by rememberSaveable(stateSaver = SessionRefSaver) { mutableStateOf<SessionRef?>(null) }
    val rows = groups.flatMap { it.rows }
    val renaming = renamingRef?.let { ref -> rows.firstOrNull { it.id == ref } }
    val closing = closingRef?.let { ref -> rows.firstOrNull { it.id == ref } }
    val closingAgent = closingAgentRef?.let { ref ->
        (focus.needsYou + focus.running + focus.justDone).firstOrNull { it.id == ref }
    }
    // A target that has gone (closed on the Mac, ended) closes its dialog for good.
    LaunchedEffect(renamingRef, renaming == null) { if (renaming == null) renamingRef = null }
    LaunchedEffect(closingRef, closing == null) { if (closing == null) closingRef = null }
    LaunchedEffect(closingAgentRef, closingAgent == null) { if (closingAgent == null) closingAgentRef = null }

    val background = MaterialTheme.colorScheme.background
    Scaffold(
        containerColor = background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.root_title)) },
                actions = {
                    Bell(pending.size, actions.openPending)
                    Create(groups.filter { it.canControl }, creating, actions.create)
                    IconButton(onClick = actions.openSettings, modifier = Modifier.testTag("root.settings")) {
                        Icon(Icons.Outlined.Settings, contentDescription = stringResource(R.string.settings_title))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = background),
            )
        },
    ) { padding ->
        val scope = rememberCoroutineScope()
        var refreshing by remember { mutableStateOf(false) }
        Box(Modifier.fillMaxSize().padding(padding)) {
            PullToRefreshBox(
                isRefreshing = refreshing,
                onRefresh = {
                    refreshing = true
                    scope.launch {
                        try {
                            actions.refresh()
                        } finally {
                            refreshing = false
                        }
                    }
                },
                modifier = Modifier.fillMaxSize(),
            ) {
                LazyColumn(
                    modifier = Modifier.fillMaxSize().testTag("workspaces.list"),
                    contentPadding = PaddingValues(bottom = 24.dp),
                ) {
                    agents(focus, nowMs, showsMachineNames, closableAgents, removableAgents, actions) { closingAgentRef = it }
                    item(key = "title-workspaces") { Title(stringResource(R.string.home_workspaces)) }
                    for (group in groups) {
                        group(group, showsDefault = groups.size > 1, actions, rename = { renamingRef = it }, close = { closingRef = it })
                    }
                    if (focus.ended.isNotEmpty()) item(key = "ended") { EndedFold(focus.ended.size, actions.openEnded) }
                }
            }
            notice?.let { NoticeCapsule(it.text, Modifier.align(Alignment.BottomCenter)) }
        }
    }

    closing?.let { row ->
        ConfirmDialog(
            title = stringResource(R.string.workspaces_close_title, row.title),
            text = stringResource(R.string.workspaces_close_confirm),
            confirmLabel = stringResource(R.string.workspaces_close),
            onConfirm = { actions.close(row.id) },
            onDismiss = { closingRef = null },
        )
    }
    val agent = closingAgent
    AgentCloseConfirmation(agent?.name, close = { agent?.let { actions.closeAgent(it.id) } }, dismiss = { closingAgentRef = null })
    renaming?.let { row ->
        WorkspaceRenameSheet(
            current = row.title,
            save = { title ->
                renamingRef = null
                actions.rename(row.id, title)
            },
            cancel = { renamingRef = null },
        )
    }
    WorkspaceAlertDialog(alert, onAlertDismissed)
}

/**
 * The bell: opens the requests page, with how many wait on it in a badge ("99+" above 99). The badge's digits keep
 * their size at large text, so they stay inside the button's round touch area; TalkBack hears the count in the label.
 */
@Composable
private fun Bell(count: Int, open: () -> Unit) {
    val badgeStyle = with(LocalDensity.current) {
        MaterialTheme.typography.labelSmall.copy(fontSize = 11.dp.toSp(), lineHeight = 16.dp.toSp())
    }
    val description = if (count == 0) {
        stringResource(R.string.workspaces_bell)
    } else {
        stringResource(R.string.pending_section_title, count)
    }
    val colors = ShellXTheme.colors
    IconButton(onClick = open, modifier = Modifier.semantics { contentDescription = description }.testTag("workspaces.bell")) {
        BadgedBox(
            badge = {
                if (count > 0) {
                    Badge(containerColor = colors.accent, contentColor = colors.onAccent) {
                        Text(if (count > 99) "99+" else "$count", modifier = Modifier.clearAndSetSemantics {}, style = badgeStyle)
                    }
                }
            },
        ) { Icon(Icons.Outlined.Notifications, contentDescription = null) }
    }
}

/** ＋: one Mac that takes commands, a button; several, a menu headed "Create on"; none (or while creating), off. */
@Composable
private fun Create(targets: List<WorkspaceGroup>, creating: Boolean, create: (String) -> Unit) {
    var menuOpen by remember { mutableStateOf(false) }
    Box {
        IconButton(
            onClick = {
                if (targets.size > 1) menuOpen = true else targets.firstOrNull()?.let { create(it.id) }
            },
            enabled = targets.isNotEmpty() && !creating,
            modifier = Modifier.testTag("workspaces.create"),
        ) { Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.workspaces_create)) }
        DropdownMenu(expanded = menuOpen && targets.size > 1 && !creating, onDismissRequest = { menuOpen = false }) {
            Text(
                text = stringResource(R.string.workspaces_create_pick_mac),
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            for (group in targets) {
                DropdownMenuItem(
                    text = { Text(group.name) },
                    onClick = {
                        menuOpen = false
                        create(group.id)
                    },
                )
            }
        }
    }
}

/** A group's title over its cards: 16 dp above, 4 dp below. */
@Composable
private fun Title(text: String) {
    SectionTitle(text, Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp))
}

private fun LazyListScope.agents(
    focus: HomeFocus,
    nowMs: Long,
    showsMachineNames: Boolean,
    closable: Set<SessionRef>,
    removable: Set<SessionRef>,
    actions: WorkspaceListScreenActions,
    confirmClose: (SessionRef) -> Unit,
) {
    if (focus.isQuiet) {
        item(key = "quiet") {
            Text(
                text = stringResource(R.string.home_quiet),
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .padding(start = 16.dp, end = 16.dp, top = 16.dp)
                    .testTag("home.quiet"),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        return
    }
    val sections = listOf(
        Triple(focus.needsYou, FocusKind.NEEDS_YOU, R.string.home_needs_you),
        Triple(focus.running, FocusKind.RUNNING, R.string.home_running),
        Triple(focus.justDone, FocusKind.JUST_DONE, R.string.home_just_done),
    )
    for ((items, kind, title) in sections) {
        if (items.isEmpty()) continue
        item(key = "title-$kind") { Title(stringResource(title, items.size)) }
        items(items, key = { "agent-$kind-${it.session.machineId}-${it.session.session.sessionId}" }) { item ->
            AgentCard(item, kind, nowMs, showsMachineNames, RowActions.agentCard(item.id in closable, item.id in removable), actions, confirmClose)
        }
    }
}

@Composable
private fun AgentCard(
    item: FocusItem,
    kind: FocusKind,
    nowMs: Long,
    showsMachineNames: Boolean,
    plan: RowActionPlan,
    actions: WorkspaceListScreenActions,
    confirmClose: (SessionRef) -> Unit,
) {
    val run: (RowActionKind) -> () -> Unit = { action ->
        when (action) {
            RowActionKind.CLOSE_AGENT -> ({ confirmClose(item.id) })
            RowActionKind.REMOVE_FROM_PHONE -> ({ actions.removeFromPhone(item.session) })
            else -> ({})
        }
    }
    ActionRow(
        swipe = plan.swipe?.let { it.swipeAction(run(it)) },
        menu = plan.menu.map { it.menuAction(run(it)) },
        onClick = { actions.openAgent(item.id) },
        onClickLabel = stringResource(R.string.action_open_agent),
        modifier = Modifier
            .padding(CardInsets)
            .clip(RoundedCornerShape(14.dp))
            .testTag("home.agent.${item.session.machineId}.${item.session.session.sessionId}"),
    ) { FocusRowView(item, kind, nowMs, showsMachineNames) }
}

private fun LazyListScope.group(
    group: WorkspaceGroup,
    showsDefault: Boolean,
    actions: WorkspaceListScreenActions,
    rename: (WorkspaceRef) -> Unit,
    close: (WorkspaceRef) -> Unit,
) {
    item(key = "group-${group.id}") {
        MachineGroupHeader(group, showsDefault, actions.openMachines, Modifier.padding(horizontal = 16.dp))
    }
    when (group.listing) {
        WorkspaceGroup.Listing.UPDATE_MAC -> item(key = "update-${group.id}") { UpdateMacCard(group.id) }
        WorkspaceGroup.Listing.EMPTY -> item(key = "empty-${group.id}") {
            Text(
                text = stringResource(R.string.workspaces_empty),
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .padding(horizontal = 16.dp, vertical = 12.dp)
                    .testTag("workspace.empty.${group.id}"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        WorkspaceGroup.Listing.ROWS, WorkspaceGroup.Listing.HIDDEN -> Unit
    }
    if (group.showsRows) {
        items(group.rows, key = { "row-${group.id}-${it.id.workspaceId}" }) { row ->
            val plan = RowActions.workspaceCard(group.canControl)
            val run: (RowActionKind) -> () -> Unit = { action ->
                when (action) {
                    RowActionKind.CLOSE_WORKSPACE -> ({ close(row.id) })
                    RowActionKind.RENAME_WORKSPACE -> ({ rename(row.id) })
                    else -> ({})
                }
            }
            ActionRow(
                swipe = plan.swipe?.let { it.swipeAction(run(it)) },
                menu = plan.menu.map { it.menuAction(run(it)) },
                onClick = { actions.openWorkspace(row.id) },
                onClickLabel = null,
                modifier = Modifier
                    .padding(CardInsets)
                    .clip(RoundedCornerShape(12.dp))
                    .testTag("workspace.row.${row.id.workspaceId}"),
            ) { WorkspaceRowView(row, dimmed = group.state != MachineLinkState.Online) }
        }
    }
    if (group.showsOtherSessions) {
        item(key = "other-${group.id}") {
            ChevronRow(
                text = stringResource(R.string.workspaces_other, group.otherSessionCount),
                onClick = { actions.openOtherSessions(group.id) },
                modifier = Modifier.padding(CardInsets).testTag("workspace.otherSessions.${group.id}"),
            )
        }
    }
}

/** A Mac whose ShellX lists no workspaces: a card in place of the rows. */
@Composable
private fun UpdateMacCard(machineId: String) {
    Row(
        modifier = Modifier
            .padding(CardInsets)
            .shellXCard(RoundedCornerShape(14.dp))
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .padding(horizontal = 12.dp, vertical = 6.dp)
            .semantics(mergeDescendants = true) {}
            .testTag("workspace.updateMac.$machineId"),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Outlined.ArrowCircleUp, contentDescription = null, tint = ShellXTheme.colors.accentText)
        Text(
            text = stringResource(R.string.workspaces_old_mac),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

/** "Agents outside workspaces · N ›" and the Ended fold: muted words and a chevron TalkBack skips. */
@Composable
private fun ChevronRow(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .heightIn(min = 48.dp)
            .padding(horizontal = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = text,
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
        )
    }
}

/** "Ended · N ›", the list's last row, in a dashed outline. */
@Composable
private fun EndedFold(count: Int, open: () -> Unit) {
    val dash = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.2f)
    ChevronRow(
        text = stringResource(R.string.home_ended, count),
        onClick = open,
        modifier = Modifier
            .padding(12.dp)
            .drawBehind {
                val width = 1.dp.toPx()
                drawRoundRect(
                    color = dash,
                    topLeft = androidx.compose.ui.geometry.Offset(width / 2, width / 2),
                    size = androidx.compose.ui.geometry.Size(size.width - width, size.height - width),
                    cornerRadius = CornerRadius(12.dp.toPx()),
                    style = Stroke(width = width, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx()))),
                )
            }
            .testTag("home.ended"),
    )
}
