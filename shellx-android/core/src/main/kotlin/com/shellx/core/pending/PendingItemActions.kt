package com.shellx.core.pending

import com.shellx.link.core.ExitPlanMode
import com.shellx.link.core.PendingItem
import com.shellx.link.core.PendingKind
import com.shellx.link.core.PermissionMode

/**
 * The buttons this item's card offers, in the order the card shows them. A mode only becomes a button when the Mac
 * listed it in `modes`; a mode this app does not know (`bypass`, `bypassPermissions` or anything newer) never does.
 * With nothing to offer the card says to open it on the Mac (`[OpenOnMac]`), as for a kind this app does not know.
 */
val PendingItem.actions: List<PendingAction>
    get() {
        val offered: List<PendingAction> = when (kind) {
            PendingKind.PERMISSION -> listOf(
                PermissionMode.ONCE to PendingAction.AllowOnce,
                PermissionMode.DENY to PendingAction.Deny,
                PermissionMode.ALWAYS to PendingAction.AllowAlways,
                PermissionMode.ALL to PendingAction.AllowAllTools,
            ).filter { it.first.wire in modes }.map { it.second }
            PendingKind.QUESTION -> {
                val questions = questions.orEmpty()
                // Answers are kept by question id, so two questions sharing one cannot be answered here.
                val answerable = questions.isNotEmpty() && questions.all { it.options.isNotEmpty() } &&
                    questions.map { it.id }.toSet().size == questions.size
                if (answerable) listOf(PendingAction.Answer) else emptyList()
            }
            PendingKind.EXIT_PLAN -> {
                val approvals = listOf(ExitPlanMode.MANUAL, ExitPlanMode.AUTO_ACCEPT, ExitPlanMode.ULTRAPLAN)
                    .filter { it.wire in modes }
                    .map { PendingAction.ApprovePlan(it) }
                val refusals =
                    if (ExitPlanMode.DENY.wire in modes) listOf(PendingAction.RevisePlan, PendingAction.RejectPlan) else emptyList()
                approvals + refusals
            }
            else -> emptyList()
        }
        return offered.ifEmpty { listOf(PendingAction.OpenOnMac) }
    }
