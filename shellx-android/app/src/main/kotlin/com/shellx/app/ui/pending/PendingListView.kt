package com.shellx.app.ui.pending

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.shellx.app.R
import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.pairing.SheetPresence
import com.shellx.core.pending.DecisionCenter
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first

/** The open sheet of one pending page, kept across configuration changes (`viewModel(key = "pending")`). */
class PendingListHolder : ViewModel() {
    var route: PendingRoute? by mutableStateOf(null)
}

/**
 * "Needs You": the pending cards, opened from a "Needs you" bar (the home's shows every one, an agent screen's only its
 * workspace's, through [only]; `PendingListView.swift`). It only reads the decision center; the signed-in scope keeps
 * it synced with the hub. Once the last card is handled it says so for a moment ([PendingListView.LEAVE_DELAY]) and
 * goes [back] by itself, once the page is in front; never while a sheet is up (closing it would lose an answer being
 * typed).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PendingListView(
    hub: MachineHub,
    center: DecisionCenter,
    sheets: SheetPresence?,
    only: ((MachinePendingItem) -> Boolean)? = null,
    back: () -> Unit,
) {
    val holder: PendingListHolder = viewModel(key = PendingListView.HOLDER_KEY)
    hub.state.collectAsStateWithLifecycle().value
    center.state.collectAsStateWithLifecycle().value
    val all = hub.pendingItems
    val items = center.visibleItems(only?.let { all.filter(it) } ?: all)
    // A card showed here: the page goes back once there are none (never when it opened empty).
    var hadItems by rememberSaveable { mutableStateOf(false) }
    val shows = items.isNotEmpty()
    SideEffect { if (shows) hadItems = true }
    val route = holder.route
    val finished = hadItems && items.isEmpty() && route == null
    val leave by rememberUpdatedState(back)
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(finished, lifecycle) {
        if (!finished) return@LaunchedEffect
        delay(PendingListView.LEAVE_DELAY)
        // The navigator goes back only from the page in front: a page paused meanwhile (Home, a dialog over it)
        // leaves once it is there again, as the workspace page does.
        lifecycle.currentStateFlow.first { it.isAtLeast(Lifecycle.State.RESUMED) }
        leave()
    }
    val background = MaterialTheme.colorScheme.background
    Scaffold(
        containerColor = background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.pending_list_title)) },
                navigationIcon = {
                    IconButton(onClick = back) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.nav_back))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = background),
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
                pendingCardsSection(
                    items, status = { center.status[it] }, showsMachineName = hub.machines.size > 1,
                    actions = { PendingCardsSection.actions(it, hub, center) { opened -> holder.route = opened } },
                )
            }
            if (items.isEmpty()) {
                Column(
                    Modifier.align(Alignment.Center).padding(32.dp).testTag("pending.empty"),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(
                        Icons.Outlined.CheckCircle, contentDescription = null, modifier = Modifier.size(48.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        stringResource(R.string.pending_list_empty),
                        style = MaterialTheme.typography.titleMedium,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
    }
    route?.let { PendingSheetHost(it, hub, center, sheets) { holder.route = null } }
}

object PendingListView {
    /** How long "Nothing needs you" shows before the page goes back (ledger 6.2-19). */
    val LEAVE_DELAY: Duration = 700.milliseconds

    /** The page's holder key: one open sheet per pending page. */
    const val HOLDER_KEY: String = "pending"
}
