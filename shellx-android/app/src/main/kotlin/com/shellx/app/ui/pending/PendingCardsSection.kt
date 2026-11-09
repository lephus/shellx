package com.shellx.app.ui.pending

import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.components.SectionTitle
import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.PendingKey
import com.shellx.core.pending.DecisionCenter
import com.shellx.core.pending.DecisionStatus
import com.shellx.core.pending.PendingSheetModel
import kotlinx.coroutines.launch

/**
 * "Needs you · N": pending requests as cards in a lazy list (`PendingCardsSection.swift`). The owner passes the items
 * the decision center shows (a card goes as soon as its decision is taken); the signed-in scope keeps the center synced
 * with the hub. Opening a card's sheet goes through [actions], so the owner holds the sheet and it outlives a card that
 * goes meanwhile.
 */
fun LazyListScope.pendingCardsSection(
    items: List<MachinePendingItem>,
    status: (PendingKey) -> DecisionStatus?,
    showsMachineName: Boolean,
    actions: (MachinePendingItem) -> PendingCardActions,
) {
    if (items.isEmpty()) return
    item(key = "pending.header") {
        SectionTitle(
            stringResource(R.string.pending_section_title, items.size),
            Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp),
        )
    }
    items(items, key = { "pending/${it.machineId}/${it.item.requestId}" }) { item ->
        PendingCardView(
            item, status(item.id), showsMachineName, actions(item),
            Modifier.animateItem().padding(horizontal = 16.dp, vertical = 6.dp),
        )
    }
}

object PendingCardsSection {
    /**
     * A card's buttons: decisions and retries go through [center] in `hub.scope` (they outlive the page); "Answer",
     * "Review plan" and "Show more" make the item's [PendingSheetModel] and [open] its sheet, unless the item went
     * between the tap and now.
     */
    fun actions(item: MachinePendingItem, hub: MachineHub, center: DecisionCenter, open: (PendingRoute) -> Unit): PendingCardActions {
        val key = item.id
        val sheet = {
            val model = PendingSheetModel(key, hub, center)
            // Gone between the tap and now: there is nothing left to show.
            if (model.opened != null) open(PendingRoute(PendingRoute.kind(item.item), model))
        }
        return PendingCardActions(
            decide = { decision -> hub.scope.launch { center.send(decision, key) } },
            openSheet = sheet,
            showMore = sheet,
            retry = { hub.scope.launch { center.retry(key) } },
        )
    }
}
