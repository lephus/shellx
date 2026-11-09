package com.shellx.app.ui.pending

import com.shellx.core.link.PendingKey
import com.shellx.core.pending.PendingAction
import com.shellx.core.pending.PendingSheetModel
import com.shellx.core.pending.actions
import com.shellx.link.core.PendingItem
import com.shellx.link.core.PendingKind

/** The sheet open over the pending cards, and the model that follows its item (`PendingRoute.swift`). */
class PendingRoute(val kind: Kind, val model: PendingSheetModel) {
    enum class Kind {
        /** [QuestionAnswerSheet]. */
        QUESTION,

        /** [PlanReviewSheet]. */
        PLAN,

        /** [FullTextSheet]: everything a permission's preview holds. */
        FULL_TEXT,
    }

    val id: PendingKey = model.key

    companion object {
        /** The sheet that shows all of [item]: its answer or review sheet, or the full text. */
        fun kind(item: PendingItem): Kind = when {
            item.kind == PendingKind.QUESTION && item.actions == listOf(PendingAction.Answer) -> Kind.QUESTION
            item.kind == PendingKind.EXIT_PLAN && item.actions != listOf(PendingAction.OpenOnMac) -> Kind.PLAN
            else -> Kind.FULL_TEXT
        }
    }
}
