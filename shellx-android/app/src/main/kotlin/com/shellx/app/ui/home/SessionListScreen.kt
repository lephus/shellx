package com.shellx.app.ui.home

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.components.ActionRow
import com.shellx.app.ui.components.RowActionKind
import com.shellx.app.ui.components.RowActions
import com.shellx.app.ui.components.SectionTitle
import com.shellx.app.ui.components.menuAction
import com.shellx.app.ui.components.swipeAction
import com.shellx.app.ui.workspaces.CardInsets
import com.shellx.core.home.FocusItem
import com.shellx.core.link.SessionRef

/** The trash's square at a card's end edge, which the card's words leave free (48 dp, the touch-target rule). */
private val RemoveSize = 48.dp

/**
 * A page of agent sessions as cards (`SessionListScreen.swift`): "Agents outside workspaces" and "Ended", from plain
 * values so render tests can show it; [EndedSessionsView] and the workspaces' `OtherSessionsView` feed it.
 *
 * It is laid out as the home is: the same room around a card ([CardInsets]). A card opens its session. With [remove]
 * each card has a trash button at its end edge, and its swipe does the same (nothing is asked). A card in
 * [removableGone] (a session gone from its Mac) swipes to "Remove from This Phone" ([removeGone]). No card offers
 * Close: neither page holds an agent the Mac can close for the phone.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SessionListScreen(
    title: String,
    header: String?,
    items: List<FocusItem>,
    kind: (FocusItem) -> FocusKind,
    nowMs: Long,
    showsMachineName: Boolean,
    @StringRes empty: Int,
    openAgent: (SessionRef) -> Unit,
    back: () -> Unit,
    remove: ((FocusItem) -> Unit)? = null,
    removableGone: Set<SessionRef> = emptySet(),
    removeGone: (FocusItem) -> Unit = {},
) {
    val background = MaterialTheme.colorScheme.background
    Scaffold(
        containerColor = background,
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = {
                    IconButton(onClick = back) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.nav_back))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = background),
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(bottom = 24.dp),
        ) {
            if (items.isEmpty()) {
                item(key = "empty") {
                    Text(
                        text = stringResource(empty),
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 24.dp).testTag("sessionList.empty"),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
                return@LazyColumn
            }
            header?.let { text ->
                item(key = "header") {
                    SectionTitle(text, Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp))
                }
            }
            items(items, key = { "${it.session.machineId}/${it.session.session.sessionId}" }) { item ->
                SessionCard(item, kind(item), nowMs, showsMachineName, openAgent, remove, item.id in removableGone, removeGone)
            }
        }
    }
}

@Composable
private fun SessionCard(
    item: FocusItem,
    kind: FocusKind,
    nowMs: Long,
    showsMachineName: Boolean,
    openAgent: (SessionRef) -> Unit,
    remove: ((FocusItem) -> Unit)?,
    gone: Boolean,
    removeGone: (FocusItem) -> Unit,
) {
    val plan = if (remove != null) RowActions.endedCard() else RowActions.otherSessionCard(gone)
    val run: (RowActionKind) -> () -> Unit = { action ->
        when (action) {
            RowActionKind.REMOVE_ENDED -> ({ remove?.invoke(item) })
            RowActionKind.REMOVE_FROM_PHONE -> ({ removeGone(item) })
            else -> ({})
        }
    }
    val sessionId = item.session.session.sessionId
    ActionRow(
        swipe = plan.swipe?.let { it.swipeAction(run(it)) },
        menu = plan.menu.map { it.menuAction(run(it)) },
        onClick = { openAgent(item.id) },
        onClickLabel = stringResource(R.string.action_open_agent),
        modifier = Modifier
            .padding(CardInsets)
            .clip(RoundedCornerShape(14.dp))
            .testTag("sessionList.row.$sessionId"),
    ) {
        Box {
            FocusRowView(item, kind, nowMs, showsMachineName, trailingInset = if (remove != null) RemoveSize else 0.dp)
            if (remove != null) {
                // Its own button over the card's end (not merged into the card's words); it moves with the swipe.
                IconButton(
                    onClick = { remove(item) },
                    modifier = Modifier.align(Alignment.CenterEnd).size(RemoveSize).testTag("sessionList.remove.$sessionId"),
                ) {
                    Icon(
                        Icons.Outlined.Delete,
                        contentDescription = stringResource(R.string.ended_remove_named, item.name),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}
