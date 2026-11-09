package com.shellx.app.ui.pending

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.shellx.app.R
import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.pairing.SheetPresence
import com.shellx.core.pending.DecisionCenter
import com.shellx.core.pending.DecisionStatus
import com.shellx.link.core.LinkDecision
import kotlinx.coroutines.launch

/**
 * The bottom sheet over the pending cards, fed by its route's model (`PendingSheetHost.swift`): it closes once its own
 * decision is taken, and tells TalkBack when the item was decided elsewhere meanwhile. While it is up it counts in
 * [sheets], so a pairing link opened meanwhile waits. Sends run in `hub.scope`, so they outlive the sheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PendingSheetHost(route: PendingRoute, hub: MachineHub, center: DecisionCenter, sheets: SheetPresence?, close: () -> Unit) {
    // Read so that the getters below are read again when any of the three changes.
    hub.state.collectAsStateWithLifecycle().value
    center.state.collectAsStateWithLifecycle().value
    route.model.state.collectAsStateWithLifecycle().value
    val state = PendingSheetState.of(route.model)
    val closing by rememberUpdatedState(close)
    LaunchedEffect(state.status) { if (state.status == DecisionStatus.Done) closing() }
    DisposableEffect(sheets) {
        sheets?.opened()
        onDispose { sheets?.closed() }
    }
    val send: (LinkDecision) -> Unit = { decision -> hub.scope.launch { route.model.send(decision) } }
    val item = route.model.opened ?: return
    ModalBottomSheet(
        onDismissRequest = close,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = if (route.kind == PendingRoute.Kind.FULL_TEXT) MaterialTheme.colorScheme.background else MaterialTheme.colorScheme.surfaceContainer,
    ) {
        Box {
            when (route.kind) {
                PendingRoute.Kind.QUESTION, PendingRoute.Kind.PLAN -> PendingSheetPlaceholder(item, route.kind, close)
                PendingRoute.Kind.FULL_TEXT -> FullTextSheet(item.item, close)
            }
            HandledElsewhereAnnouncement(state.handledElsewhere)
        }
    }
}

/** A polite live region that says "Already handled elsewhere" once the item was decided elsewhere. */
@Composable
private fun HandledElsewhereAnnouncement(handled: Boolean) {
    val text = if (handled) stringResource(R.string.pending_status_handled_elsewhere) else ""
    Box(
        Modifier.size(1.dp).semantics {
            liveRegion = LiveRegionMode.Polite
            if (text.isNotEmpty()) contentDescription = text
        },
    )
}

/** Until the question and plan sheets: the item's prompts or plan, and Close. */
@Composable
private fun PendingSheetPlaceholder(item: MachinePendingItem, kind: PendingRoute.Kind, close: () -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        SheetTopBar(
            stringResource(if (kind == PendingRoute.Kind.QUESTION) R.string.pending_question_title else R.string.pending_plan_title),
            close,
        )
        Column(Modifier.padding(16.dp)) {
            if (kind == PendingRoute.Kind.QUESTION) {
                for (question in item.item.questions.orEmpty()) Text(question.prompt, style = MaterialTheme.typography.bodyLarge)
            } else {
                Text(item.item.planPreview.orEmpty(), style = MaterialTheme.typography.bodyLarge)
            }
        }
    }
}
