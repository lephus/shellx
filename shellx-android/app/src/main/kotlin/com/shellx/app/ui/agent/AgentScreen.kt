package com.shellx.app.ui.agent

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.platform.AndroidClock
import com.shellx.app.ui.components.ConfirmDialog
import com.shellx.app.ui.components.HomeTicks
import com.shellx.app.ui.components.Spinner
import com.shellx.app.ui.components.rememberNowMs
import com.shellx.app.ui.composer.ComposerBar
import com.shellx.app.ui.composer.ComposerBarState
import com.shellx.app.ui.home.NeedsYouBar
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.workspaces.AgentCloseConfirmation
import com.shellx.app.ui.workspaces.NoticeCapsule
import com.shellx.core.agent.AgentThreadModel
import com.shellx.core.agent.ChatFollow
import com.shellx.core.composer.ComposerDraft
import com.shellx.core.composer.OutgoingAttachment
import com.shellx.core.home.AgentStatusRow
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.SessionRef
import com.shellx.core.pending.AgentLabel
import com.shellx.core.platform.Clock
import com.shellx.link.core.ChatEntry
import java.util.UUID
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch

/** A short line over the composer: what became of the last send or stop (iPhone `AgentScreen.Notice`). */
data class AgentNotice(val text: String, val id: String = UUID.randomUUID().toString()) {
    override fun toString(): String = "AgentNotice(text=<redacted>, id=$id)"
}

/** The agent screen's actions (`AgentScreen.Actions`). */
class AgentScreenActions(
    /** The composer's trimmed, valid text (empty with attachments only) and its attachments. */
    val send: (String, List<OutgoingAttachment>) -> Unit = { _, _ -> },
    /** What the user said into the mic (trimmed, not empty). */
    val sendVoice: (String) -> Unit = {},
    val stop: () -> Unit = {},
    /** Force Stop, once confirmed. */
    val forceStop: () -> Unit = {},
    /** Asks for older entries (also the retry after a failure). */
    val loadOlder: () -> Unit = {},
    /** Asks for the newest page again after it failed. */
    val retry: () -> Unit = {},
    /** The "Needs you" bar: this workspace's pending cards. */
    val seeAllPending: () -> Unit = {},
    /** Close Agent, once confirmed. */
    val closeAgent: () -> Unit = {},
    /** Remove from This Phone: hides the session gone from its Mac on this phone, then goes back. */
    val removeFromPhone: () -> Unit = {},
)

/** The key of the chat's bottom item, whose visibility drives [ChatFollow]. */
private const val BOTTOM = "bottom"
private const val OLDER = "older"

/**
 * One agent's screen from plain values (`AgentScreen.swift`), so render tests can show any state; [AgentView] feeds it.
 *
 * - Top bar (standalone): the workspace, "Stop" while [canStop], and `⋮` while it holds something: "Close Agent…" (red,
 *   off while offline; asks first) and "Remove from This Phone" (red, at once). [embedded] (a workspace pane): no top
 *   bar; "Stop" sits at the end of the header, and there is no `⋮` and no Remove.
 * - Top: the header (read again every second), "Remove from This Phone" (standalone, [canRemoveFromPhone]) and the
 *   "Needs you" bar of this workspace.
 * - Chat: newest at the bottom; the top asks for older entries. It follows new entries only while its bottom shows
 *   (3C's [ChatFollow]); otherwise "New messages" offers to jump down.
 * - Bottom: the notice (a polite live region), then the composer.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AgentScreen(
    ref: SessionRef,
    place: String,
    row: () -> AgentStatusRow?,
    gone: Boolean,
    offline: Boolean,
    pending: List<MachinePendingItem>,
    showsMachineName: Boolean,
    entries: List<ChatEntry>,
    emptyState: AgentThreadModel.EmptyState?,
    machineName: String,
    older: AgentThreadModel.Older,
    loadingOlder: Boolean,
    canStop: Boolean,
    notice: AgentNotice?,
    draft: ComposerDraft,
    onDraftChange: (ComposerDraft) -> Unit,
    embedded: Boolean = false,
    attachmentsEnabled: Boolean = false,
    sending: Double? = null,
    closeAgentName: String? = null,
    canRemoveFromPhone: Boolean = false,
    actions: AgentScreenActions = AgentScreenActions(),
    back: () -> Unit = {},
    /** The clock the header's "Running for" is read against, again every second. */
    clock: Clock = AndroidClock,
    /** The composer's state beyond its composition, from the screen's holder ([ComposerBar]'s `state`). */
    composer: ComposerBarState? = null,
) {
    var confirmsForceStop by rememberSaveable { mutableStateOf(false) }
    // The name in the Close Agent confirmation while it is up.
    var closing by rememberSaveable { mutableStateOf<String?>(null) }
    val agent = AgentLabel.of(ref.agent).text
    // A pane of the workspace screen offers no Remove: it shows a tab of the Mac's.
    val offersRemove = canRemoveFromPhone && !embedded
    val askForceStop = { confirmsForceStop = true }
    val background = MaterialTheme.colorScheme.background

    val body = @Composable { modifier: Modifier ->
        Column(modifier.fillMaxSize().imePadding()) {
            Top(place, row, gone, offline, pending, showsMachineName, embedded && canStop, offersRemove, actions, askForceStop, clock)
            Chat(entries, agent, emptyState, machineName, older, loadingOlder, actions, Modifier.weight(1f))
            notice?.let {
                Box(
                    Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}.testTag("agent.notice"),
                    contentAlignment = Alignment.Center,
                ) { NoticeCapsule(it.text) }
            }
            ComposerBar(
                draft, onDraftChange, send = actions.send, attachmentsEnabled = attachmentsEnabled, sending = sending,
                sendVoice = actions.sendVoice, state = composer,
            )
        }
    }
    if (embedded) {
        body(Modifier)
    } else {
        Scaffold(
            containerColor = background,
            topBar = {
                TopAppBar(
                    title = { Text(ref.workspaceTitle, maxLines = 1) },
                    navigationIcon = {
                        IconButton(onClick = back) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.nav_back))
                        }
                    },
                    actions = {
                        if (canStop) StopButton(actions.stop, askForceStop)
                        if (closeAgentName != null || offersRemove) {
                            AgentMenu(
                                online = !offline,
                                closeAgent = closeAgentName?.let { name -> { closing = name } },
                                removeFromPhone = if (offersRemove) actions.removeFromPhone else null,
                            )
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = background),
                )
            },
        ) { padding -> body(Modifier.padding(padding).consumeWindowInsets(padding)) }
    }

    if (confirmsForceStop) {
        ConfirmDialog(
            title = stringResource(R.string.agent_force_stop_title, agent, ref.workspaceTitle),
            text = stringResource(R.string.agent_force_stop_message),
            confirmLabel = stringResource(R.string.agent_force_stop),
            onConfirm = actions.forceStop,
            onDismiss = { confirmsForceStop = false },
        )
    }
    AgentCloseConfirmation(closing, close = actions.closeAgent, dismiss = { closing = null })
}

/** The header, Stop (embedded), Remove from This Phone and the "Needs you" bar, over a hairline. */
@Composable
private fun Top(
    place: String,
    row: () -> AgentStatusRow?,
    gone: Boolean,
    offline: Boolean,
    pending: List<MachinePendingItem>,
    showsMachineName: Boolean,
    showsStop: Boolean,
    offersRemove: Boolean,
    actions: AgentScreenActions,
    askForceStop: () -> Unit,
    clock: Clock,
) {
    val now = rememberNowMs(clock, remember { HomeTicks.every(1.seconds) })
    Column(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                // Read again every second, for the "Running for" time.
                val current = remember(now, row) { row() }
                AgentHeader(place, current, gone, offline, Modifier.weight(1f))
                if (showsStop) StopButton(actions.stop, askForceStop)
            }
            if (offersRemove) RemoveFromPhoneButton(actions.removeFromPhone)
            if (pending.isNotEmpty()) {
                NeedsYouBar(pending, showsMachineName, open = actions.seeAllPending, modifier = Modifier.padding(bottom = 8.dp))
            }
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
    }
}

@Composable
private fun Chat(
    entries: List<ChatEntry>,
    agent: String,
    emptyState: AgentThreadModel.EmptyState?,
    machineName: String,
    older: AgentThreadModel.Older,
    loadingOlder: Boolean,
    actions: AgentScreenActions,
    modifier: Modifier,
) {
    val olderRows = if (older == AgentThreadModel.Older.NONE) 0 else 1
    val emptyRows = if (entries.isEmpty()) 1 else 0
    // Opens at the bottom, as the iPhone's default scroll anchor.
    val list = rememberLazyListState(initialFirstVisibleItemIndex = olderRows + emptyRows + entries.size)
    val scope = rememberCoroutineScope()
    // Kept with the scroll position, so a rebuilt chat (rotation, theme, a page on top, a pane swiped away and back)
    // neither pulls a reader down nor forgets the entries they have not seen.
    val place = rememberSaveable(saver = ChatPlace.Saver) { ChatPlace() }
    val follow = place.follow
    var hasUnseen by remember { mutableStateOf(follow.hasUnseen) }
    // The first entry when older ones were asked for: the chat stays on it when they arrive.
    var olderAnchor by rememberSaveable { mutableStateOf<String?>(null) }
    val newestId by rememberUpdatedState(entries.lastOrNull()?.id)
    val currentEntries by rememberUpdatedState(entries)
    val currentOlderRows by rememberUpdatedState(olderRows)
    val askOlder by rememberUpdatedState(actions.loadOlder)
    val loadingNow by rememberUpdatedState(loadingOlder)

    fun bottomIndex(): Int = (list.layoutInfo.totalItemsCount - 1).coerceAtLeast(0)

    fun bottomShows(): Boolean = list.layoutInfo.visibleItemsInfo.any { it.key == BOTTOM }

    fun loadOlder() {
        olderAnchor = currentEntries.firstOrNull()?.id
        askOlder()
    }

    // A new newest entry is followed only while the bottom shows; otherwise "New messages". The newest entry is looked
    // at before the bottom's visibility, so an entry that pushed the bottom off screen is still followed.
    LaunchedEffect(list) {
        // The scroll down to the newest entry, while it runs. The bottom is off screen on the way down, which is not the
        // user leaving it; once the scroll ends, or a touch stops it, the chat looks again where it is.
        var following: Job? = null
        snapshotFlow { Triple(newestId, bottomShows(), list.layoutInfo.totalItemsCount) }
            .collect { (id, visible, total) ->
                if (total == 0) return@collect
                if (id != place.seen) {
                    place.seen = id
                    if (follow.newest(id)) {
                        hasUnseen = follow.hasUnseen
                        // Its own coroutine: a touch that interrupts the scroll ends the scroll, never this loop.
                        val job = launch(start = CoroutineStart.LAZY) {
                            try {
                                list.animateScrollToItem(bottomIndex())
                            } finally {
                                if (following === coroutineContext[Job]) {
                                    following = null
                                    follow.bottomVisible(bottomShows())
                                    hasUnseen = follow.hasUnseen
                                }
                            }
                        }
                        following = job
                        job.start()
                        return@collect
                    }
                }
                if (following?.isActive == true) return@collect
                follow.bottomVisible(visible)
                hasUnseen = follow.hasUnseen
            }
    }
    // The top asks for older entries each time it scrolls into view, unless a page is already on its way.
    LaunchedEffect(list, older) {
        if (older != AgentThreadModel.Older.LOADABLE) return@LaunchedEffect
        snapshotFlow { list.layoutInfo.visibleItemsInfo.any { it.key == OLDER } }
            .distinctUntilChanged()
            .filter { it }
            .collect { if (!loadingNow) loadOlder() }
    }
    // Older entries came in above: stay on the entry that was first.
    var wasLoadingOlder by remember { mutableStateOf(loadingOlder) }
    LaunchedEffect(loadingOlder) {
        if (wasLoadingOlder && !loadingOlder) {
            val anchor = olderAnchor
            olderAnchor = null
            val index = currentEntries.indexOfFirst { it.id == anchor }
            if (index >= 0) list.scrollToItem(currentOlderRows + index)
        }
        wasLoadingOlder = loadingOlder
    }

    Box(modifier.fillMaxWidth()) {
        LazyColumn(
            state = list,
            modifier = Modifier.fillMaxSize().testTag("agent.chat"),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            // A short chat sits at the bottom, by the composer (the iPhone's bottom scroll anchor).
            verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.Bottom),
        ) {
            when (older) {
                AgentThreadModel.Older.NONE -> Unit
                AgentThreadModel.Older.LOADABLE -> item(key = OLDER) {
                    Box(Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("agent.loadOlder"), contentAlignment = Alignment.Center) {
                        Spinner(Modifier.size(24.dp))
                    }
                }
                AgentThreadModel.Older.FAILED -> item(key = OLDER) {
                    FailedRow(stringResource(R.string.agent_older_failed), retry = ::loadOlder, Modifier.testTag("agent.older.failed"))
                }
                AgentThreadModel.Older.ONLY_ON_MAC -> item(key = OLDER) {
                    Text(
                        stringResource(R.string.agent_older_on_mac),
                        modifier = Modifier.fillMaxWidth().testTag("agent.olderOnMac"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
            }
            if (entries.isEmpty() && emptyState != null) {
                item(key = "empty") { EmptyRow(emptyState, machineName, actions.retry) }
            }
            items(entries, key = { it.id }) { entry -> ChatEntryRow(entry, agent) }
            item(key = BOTTOM) { Spacer(Modifier.fillMaxWidth().height(1.dp)) }
        }
        if (hasUnseen) {
            Box(Modifier.align(Alignment.BottomCenter).padding(bottom = 8.dp)) {
                NewMessagesButton {
                    follow.jumpedToBottom()
                    hasUnseen = false
                    scope.launch { list.animateScrollToItem(bottomIndex()) }
                }
            }
        }
    }
}

/**
 * Where a chat is in its entries: 3C's [ChatFollow] and the newest entry it was told of. Saved with the screen and
 * rebuilt by telling a new [ChatFollow] the same things again.
 */
private class ChatPlace(val follow: ChatFollow = ChatFollow(), var seen: String? = null) {
    companion object {
        val Saver: Saver<ChatPlace, Any> = Saver(
            save = { arrayListOf(it.follow.atBottom, it.follow.hasUnseen, it.seen.orEmpty()) },
            restore = { saved ->
                val (atBottom, hasUnseen, seen) = saved as List<*>
                val id = (seen as String).ifEmpty { null }
                val follow = ChatFollow()
                if (hasUnseen == true) {
                    // Unseen entries came while the user read older ones.
                    follow.bottomVisible(false)
                    follow.newest(id)
                } else {
                    follow.newest(id)
                    follow.bottomVisible(atBottom == true)
                }
                ChatPlace(follow, id)
            },
        )
    }
}

/** What the chat says while it has no entries. */
@Composable
private fun EmptyRow(state: AgentThreadModel.EmptyState, machineName: String, retry: () -> Unit) {
    val text = @Composable { words: String, tag: String ->
        Text(
            words,
            modifier = Modifier.fillMaxWidth().padding(vertical = 32.dp).testTag(tag),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
    when (state) {
        AgentThreadModel.EmptyState.LOADING ->
            Box(Modifier.fillMaxWidth().padding(vertical = 32.dp).testTag("agent.loading"), contentAlignment = Alignment.Center) {
                Spinner(Modifier.size(28.dp))
            }
        AgentThreadModel.EmptyState.NO_MESSAGES -> text(stringResource(R.string.agent_empty), "agent.empty")
        AgentThreadModel.EmptyState.OFFLINE -> text(stringResource(R.string.agent_empty_offline, machineName), "agent.empty.offline")
        AgentThreadModel.EmptyState.FAILED ->
            FailedRow(stringResource(R.string.agent_empty_failed), retry, Modifier.padding(vertical = 32.dp).testTag("agent.empty.failed"))
        AgentThreadModel.EmptyState.GONE -> text(stringResource(R.string.agent_gone), "agent.empty.gone")
    }
}

/** What failed, and "Try again". */
@Composable
private fun FailedRow(text: String, retry: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        TextButton(onClick = retry, modifier = Modifier.heightIn(min = 48.dp)) {
            Text(
                stringResource(R.string.pending_status_retry),
                style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold),
                color = ShellXTheme.colors.accentText,
            )
        }
    }
}

/**
 * "Remove from This Phone" under the gone line: hides the session on this phone at once (nothing is asked: nothing stops
 * on the Mac, and the session shows again when its Mac reports a change). At least 48 dp tall.
 */
@Composable
fun RemoveFromPhoneButton(remove: () -> Unit) {
    val accent = ShellXTheme.colors.accentText
    TextButton(
        onClick = remove,
        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("agent.removeFromPhone"),
        contentPadding = PaddingValues(horizontal = 0.dp, vertical = 8.dp),
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.Delete, contentDescription = null, tint = accent, modifier = Modifier.size(20.dp))
            Text(
                stringResource(R.string.agent_remove_from_phone),
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                color = accent,
            )
        }
    }
}

/**
 * `⋮` in the top bar: "Close Agent…", red, which the owner confirms first and is off while the Mac is not online; and
 * "Remove from This Phone", red, at once, also while the Mac is away. Off when nothing in it works.
 */
@Composable
private fun AgentMenu(online: Boolean, closeAgent: (() -> Unit)?, removeFromPhone: (() -> Unit)?) {
    var open by remember { mutableStateOf(false) }
    val red = ShellXTheme.colors.statusError
    Box {
        IconButton(
            onClick = { open = true },
            enabled = online || removeFromPhone != null,
            modifier = Modifier.testTag("agent.menu"),
        ) { Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.agent_menu)) }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            closeAgent?.let { close ->
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.agent_close_menu), color = if (online) red else red.copy(alpha = 0.4f)) },
                    leadingIcon = { Icon(Icons.Filled.Close, contentDescription = null, tint = if (online) red else red.copy(alpha = 0.4f)) },
                    enabled = online,
                    onClick = {
                        open = false
                        close()
                    },
                )
            }
            removeFromPhone?.let { remove ->
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.agent_remove_from_phone), color = red) },
                    leadingIcon = { Icon(Icons.Outlined.Delete, contentDescription = null, tint = red) },
                    onClick = {
                        open = false
                        remove()
                    },
                )
            }
        }
    }
}
