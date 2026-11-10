package com.shellx.app.ui.workspaces

import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.FolderOff
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.SignedInScope
import com.shellx.app.ui.agent.AgentNotice
import com.shellx.app.ui.components.CompactHeight
import com.shellx.app.ui.components.ConfirmDialog
import com.shellx.app.ui.components.SecondaryButton
import com.shellx.app.ui.components.Spinner
import com.shellx.app.ui.components.isCompactHeight
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.link.MachineSession
import com.shellx.core.workspaces.WorkspaceCommandResult
import com.shellx.core.workspaces.WorkspacePane
import com.shellx.core.workspaces.WorkspaceScreenModel
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async

/** What the workspace screen's controls do (`WorkspaceScreenActions`). */
class WorkspaceScreenActions(
    /** The user swiped to, or tapped, the chip with this terminal id. */
    val select: (String) -> Unit = {},
    /** The workspace's new name, cleaned and not empty. */
    val rename: (String) -> Unit = {},
    /** Confirmed: close the workspace and its terminals. */
    val close: () -> Unit = {},
    /** Confirmed: close the terminal tab with this id on the Mac, and stop what runs in it. */
    val closeTab: (String) -> Unit = {},
) {
    companion object {
        /**
         * The controls wired to [scope]'s hub (iPhone `WorkspaceScreenActions.make`): each command runs in `hub.scope`
         * (it outlives the screen), and [WorkspaceFeedback] says what follows: a workspace that is gone refreshes the
         * list, anything that did not work goes to [alert], "done" shows nothing (the Mac's push renames the workspace,
         * removes a tab, or removes the workspace and the screen leaves). [closing] is called when the user's close goes
         * out; [done] gets each command's task (tests wait on it). A Close Tab while the same tab's close waits sends
         * nothing.
         */
        fun make(
            scope: SignedInScope,
            model: WorkspaceScreenModel,
            alert: (WorkspaceAlert) -> Unit,
            closing: () -> Unit = {},
            done: (Deferred<WorkspaceFeedback>) -> Unit = {},
        ): WorkspaceScreenActions {
            val hub = scope.hub
            val ref = model.ref
            fun run(command: WorkspaceCommand, call: suspend () -> WorkspaceCommandResult) {
                done(
                    hub.scope.async {
                        val feedback = WorkspaceFeedback.of(call(), command, ref.machineId)
                        when (feedback) {
                            WorkspaceFeedback.None, is WorkspaceFeedback.Open -> Unit
                            WorkspaceFeedback.Refresh -> hub.refreshWorkspaces(ref.machineId)
                            is WorkspaceFeedback.Alert -> alert(feedback.alert)
                        }
                        feedback
                    },
                )
            }
            return WorkspaceScreenActions(
                select = { model.select(it) },
                rename = { title -> run(WorkspaceCommand.RENAME) { hub.renameWorkspace(ref, title) } },
                close = {
                    closing()
                    run(WorkspaceCommand.CLOSE) { hub.closeWorkspace(ref) }
                },
                closeTab = { terminalId ->
                    // Not `closing`: the workspace stays unless the tab was its last. The model knows the user closed it
                    // here, so neither the tab's leaving nor the workspace's says "closed on the Mac".
                    model.closesHere(terminalId)
                    WorkspaceListActions.closeTab(ref.machineId, ref.workspaceId, terminalId, hub) { kind ->
                        model.keeps(terminalId)
                        alert(kind)
                    }?.let(done)
                },
            )
        }
    }
}

/** What `⋮` offers. Plan 3G adds "View as Terminal" here. */
enum class WorkspaceMenuItem(@StringRes val title: Int) {
    RENAME(R.string.workspace_menu_rename),

    /** The tab of the chip shown, agent or shell; it asks to confirm first. */
    CLOSE_TAB(R.string.terminal_close_menu),
    CLOSE_WORKSPACE(R.string.workspace_menu_close),
    ;

    /** Shown red: every item but Rename. */
    val isDestructive: Boolean get() = this != RENAME

    companion object {
        /** The items in the menu's order; Close Tab… only while a chip shows and its Mac takes `terminal.close`. */
        fun items(canCloseTab: Boolean): List<WorkspaceMenuItem> = entries.filter { it != CLOSE_TAB || canCloseTab }
    }
}

/**
 * One workspace's screen from plain values (`WorkspaceScreen.swift`), so render tests can show any state;
 * [WorkspaceView] feeds it from the hub.
 *
 * - Top bar: a back arrow, the workspace's name over its git branch in monospace, and `⋮` (off unless [canControl])
 *   with Rename Workspace, then in red, each asking first, Close Tab… for the chip shown (while [canCloseTab]) and
 *   Close Workspace….
 * - Under it, the chips ([PaneChips]); a long press on one offers Close Tab… while [canCloseTab] and [canControl].
 * - Below, one page per chip, swiped sideways like the chips are tapped; [pane] draws a page ([PaneContent]). While a
 *   mic listens ([pagingLocked]) the pages stay put.
 * - [notice] floats over the top of the pages (a polite live region).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkspaceScreen(
    title: String,
    branch: String?,
    panes: List<WorkspacePane>,
    selected: String?,
    nowMs: Long,
    canControl: Boolean = true,
    canCloseTab: Boolean = false,
    pagingLocked: Boolean = false,
    notice: AgentNotice? = null,
    alert: WorkspaceAlert? = null,
    onAlertDismiss: () -> Unit = {},
    actions: WorkspaceScreenActions = WorkspaceScreenActions(),
    back: () -> Unit = {},
    pane: @Composable (pane: WorkspacePane, shown: Boolean) -> Unit,
) {
    var renaming by rememberSaveable { mutableStateOf(false) }
    var closing by rememberSaveable { mutableStateOf(false) }
    // The tab the user chose to close, until the user confirms or cancels.
    var closingTab by rememberSaveable { mutableStateOf<String?>(null) }
    val res = LocalContext.current.resources
    // The chip shown: the one selected, else the first.
    val shownPane = panes.firstOrNull { it.id == (selected ?: panes.firstOrNull()?.id) }
    val background = MaterialTheme.colorScheme.background
    // A short window (a phone in landscape): the chips sit in the compact top bar, beside the name, so the pane keeps
    // room for its chat.
    val compact = isCompactHeight()
    val chips = @Composable { modifier: Modifier ->
        PaneChips(
            panes, selected, nowMs, actions.select,
            close = if (canCloseTab && canControl) ({ closingTab = it.id }) else null,
            modifier = modifier,
        )
    }

    val backButton = @Composable {
        IconButton(onClick = back) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.nav_back))
        }
    }
    val menu = @Composable {
        Menu(WorkspaceMenuItem.items(canCloseTab && shownPane != null), canControl) { item ->
            when (item) {
                WorkspaceMenuItem.RENAME -> renaming = true
                WorkspaceMenuItem.CLOSE_TAB -> closingTab = shownPane?.id
                WorkspaceMenuItem.CLOSE_WORKSPACE -> closing = true
            }
        }
    }

    Scaffold(
        containerColor = background,
        topBar = {
            if (compact) {
                // One compact row: back, the name, the chips (they take the rest) and `⋮`.
                Row(
                    Modifier
                        .fillMaxWidth()
                        .background(background)
                        .windowInsetsPadding(TopAppBarDefaults.windowInsets)
                        .height(CompactHeight.TOP_BAR)
                        .padding(horizontal = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    backButton()
                    TitleBlock(title, branch, Modifier.padding(start = 4.dp, end = 4.dp).widthIn(max = COMPACT_TITLE_WIDTH))
                    chips(Modifier.weight(1f))
                    menu()
                }
            } else {
                TopAppBar(
                    title = { TitleBlock(title, branch) },
                    navigationIcon = { backButton() },
                    actions = { menu() },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = background),
                )
            }
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding)) {
            if (!compact) chips(Modifier)
            Box(Modifier.weight(1f).fillMaxWidth()) {
                if (panes.isEmpty()) {
                    Text(
                        stringResource(R.string.workspace_no_terminals),
                        modifier = Modifier.align(Alignment.Center).padding(24.dp).testTag("workspace.noTerminals"),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                } else {
                    Pager(panes, selected, pagingLocked, actions.select, pane)
                }
                notice?.let { NoticeCapsule(it.text, Modifier.align(Alignment.TopCenter)) }
            }
        }
    }

    if (renaming) {
        WorkspaceRenameSheet(
            current = title,
            save = { name ->
                renaming = false
                actions.rename(name)
            },
            cancel = { renaming = false },
        )
    }
    if (closing) {
        ConfirmDialog(
            title = stringResource(R.string.workspaces_close_title, title),
            text = stringResource(R.string.workspaces_close_confirm),
            confirmLabel = stringResource(R.string.workspaces_close),
            onConfirm = actions.close,
            onDismiss = { closing = false },
        )
    }
    panes.firstOrNull { it.id == closingTab }?.let { tab ->
        ConfirmDialog(
            title = stringResource(R.string.terminal_close_title, PaneChips.label(tab, res)),
            text = stringResource(R.string.terminal_close_confirm),
            confirmLabel = stringResource(R.string.terminal_close),
            onConfirm = { actions.closeTab(tab.id) },
            onDismiss = { closingTab = null },
        )
    }
    WorkspaceAlertDialog(alert, onAlertDismiss)
}

/** The name's widest in a compact top bar, where the chips take the rest. */
private val COMPACT_TITLE_WIDTH = 220.dp

/** The pages, in step with the chips: the pager follows [selected], and a settled page selects its chip. */
@Composable
private fun Pager(
    panes: List<WorkspacePane>,
    selected: String?,
    pagingLocked: Boolean,
    select: (String) -> Unit,
    pane: @Composable (WorkspacePane, Boolean) -> Unit,
) {
    val pager = rememberPagerState(initialPage = panes.indexOfFirst { it.id == selected }.coerceAtLeast(0)) { panes.size }
    val currentSelected by rememberUpdatedState(selected)
    val currentPanes by rememberUpdatedState(panes)
    val currentSelect by rememberUpdatedState(select)
    var lastIds by remember { mutableStateOf(panes.map { it.id }) }
    LaunchedEffect(selected, panes.map { it.id }) {
        val ids = panes.map { it.id }
        val target = ids.indexOf(selected)
        if (target >= 0 && pager.currentPage != target) {
            // The chips changed under the pager (a tab left): jump; the user picked a chip: slide.
            if (ids != lastIds) pager.scrollToPage(target) else pager.animateScrollToPage(target)
        }
        lastIds = ids
    }
    LaunchedEffect(pager) {
        snapshotFlow { pager.settledPage }.collect { page ->
            currentPanes.getOrNull(page)?.id?.let { if (it != currentSelected) currentSelect(it) }
        }
    }
    HorizontalPager(
        state = pager,
        modifier = Modifier.fillMaxSize().testTag("workspace.pager"),
        userScrollEnabled = !pagingLocked,
        key = { panes[it].id },
    ) { page ->
        pane(panes[page], page == pager.settledPage)
    }
}

/** The name over the branch: one heading for TalkBack. */
@Composable
private fun TitleBlock(title: String, branch: String?, modifier: Modifier = Modifier) {
    Column(modifier.semantics(mergeDescendants = true) { heading() }.testTag("workspace.title")) {
        Text(title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (!branch.isNullOrEmpty()) {
            Text(
                branch,
                style = MaterialTheme.typography.labelSmall.copy(fontFamily = FontFamily.Monospace),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.MiddleEllipsis,
            )
        }
    }
}

/** `⋮`: the plain items, a divider, then the red ones (which ask first). */
@Composable
private fun Menu(items: List<WorkspaceMenuItem>, enabled: Boolean, pick: (WorkspaceMenuItem) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }, enabled = enabled, modifier = Modifier.testTag("workspace.menu")) {
            Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.workspace_menu))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            val plain = items.filter { !it.isDestructive }
            val red = items.filter { it.isDestructive }
            for (item in plain) MenuItem(item) { open = false; pick(item) }
            if (plain.isNotEmpty() && red.isNotEmpty()) HorizontalDivider()
            for (item in red) MenuItem(item) { open = false; pick(item) }
        }
    }
}

@Composable
private fun MenuItem(item: WorkspaceMenuItem, onClick: () -> Unit) {
    DropdownMenuItem(
        text = {
            Text(
                stringResource(item.title),
                color = if (item.isDestructive) ShellXTheme.colors.statusError else MaterialTheme.colorScheme.onSurface,
            )
        },
        onClick = onClick,
    )
}

/**
 * The pane slot (contracts §5): an agent pane shows [agent], any other shows [shell]. [shown] is true only for the
 * pager's settled page: only that pane may open a terminal view. Plan 3G passes `shell = { pane, shown ->
 * TerminalPane(…) }` from [WorkspaceView]; this function does not change.
 */
@Composable
fun PaneContent(
    pane: WorkspacePane,
    shown: Boolean,
    agent: @Composable (MachineSession) -> Unit,
    shell: @Composable (pane: WorkspacePane, shown: Boolean) -> Unit = { _, _ -> ShellPanePlaceholder() },
) {
    val session = pane.session
    if (session != null) agent(session) else shell(pane, shown)
}

/** What the workspace screen shows while the Mac has not listed the workspace yet: a new workspace's answer can come
 *  before the list that holds it. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkspaceWaitingView(back: () -> Unit) {
    PlainPage(back) {
        Spinner(Modifier.size(40.dp).testTag("workspace.loading"), strokeWidth = 3.dp)
    }
}

/** What the workspace screen shows when the workspace did not come: the Mac does not have it. */
@Composable
fun WorkspaceMissingView(back: () -> Unit) {
    PlainPage(back) {
        Column(
            Modifier.padding(24.dp).testTag("workspace.notFound"),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Icon(
                Icons.Outlined.FolderOff, contentDescription = null, modifier = Modifier.size(44.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(stringResource(R.string.workspace_not_found), style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
            SecondaryButton(onClick = back, modifier = Modifier.testTag("workspace.notFound.back")) {
                Text(stringResource(R.string.workspace_not_found_back))
            }
        }
    }
}

/** A page titled "Workspace" with a back arrow and [content] in its middle. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PlainPage(back: () -> Unit, content: @Composable () -> Unit) {
    val background = MaterialTheme.colorScheme.background
    Scaffold(
        containerColor = background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.workspaces_title)) },
                navigationIcon = {
                    IconButton(onClick = back) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.nav_back))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = background),
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { content() }
    }
}
