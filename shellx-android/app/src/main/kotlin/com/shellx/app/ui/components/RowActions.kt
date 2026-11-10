package com.shellx.app.ui.components

import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import com.shellx.app.R
import com.shellx.core.link.MachineLinkState

/** The iPhone's swipe and context-menu actions, re-shaped for Android rows. */
enum class RowActionKind {
    CLOSE_AGENT, REMOVE_FROM_PHONE, CLOSE_WORKSPACE, RENAME_WORKSPACE, REMOVE_ENDED, MAKE_DEFAULT, PAIR_AGAIN, UNPAIR,
    REMOVE_MAC,
    ;

    /** The menu's (and TalkBack's) label. */
    @get:StringRes
    val menuLabel: Int
        get() = when (this) {
            CLOSE_AGENT -> R.string.agent_close_menu
            REMOVE_FROM_PHONE -> R.string.agent_remove_from_phone
            CLOSE_WORKSPACE -> R.string.workspace_menu_close
            RENAME_WORKSPACE -> R.string.workspace_menu_rename
            REMOVE_ENDED -> R.string.ended_remove
            MAKE_DEFAULT -> R.string.machines_make_default
            PAIR_AGAIN -> R.string.machines_pair_again
            UNPAIR -> R.string.machines_unpair
            REMOVE_MAC -> R.string.machines_remove
        }

    /** The label a swipe uncovers. */
    @get:StringRes
    val swipeLabel: Int
        get() = when (this) {
            CLOSE_AGENT -> R.string.agent_close
            CLOSE_WORKSPACE -> R.string.workspaces_close
            else -> menuLabel
        }

    val icon: ImageVector
        get() = when (this) {
            CLOSE_AGENT, CLOSE_WORKSPACE -> Icons.Filled.Close
            REMOVE_FROM_PHONE, REMOVE_ENDED, REMOVE_MAC -> Icons.Outlined.Delete
            RENAME_WORKSPACE -> Icons.Outlined.Edit
            MAKE_DEFAULT -> Icons.Outlined.StarOutline
            PAIR_AGAIN -> Icons.Filled.QrCodeScanner
            UNPAIR -> Icons.Outlined.RemoveCircleOutline
        }

    val destructive: Boolean
        get() = this != RENAME_WORKSPACE && this != MAKE_DEFAULT && this != PAIR_AGAIN
}

/** The kind as a menu item (and TalkBack custom action). */
@Composable
fun RowActionKind.menuAction(run: () -> Unit): RowAction = RowAction(stringResource(menuLabel), icon, destructive, run)

/** The kind as a row's swipe. */
@Composable
fun RowActionKind.swipeAction(run: () -> Unit): RowAction = RowAction(stringResource(swipeLabel), icon, destructive, run)

/** A row's swipe (null: none) and its long-press menu, in order. */
data class RowActionPlan(val swipe: RowActionKind?, val menu: List<RowActionKind>)

/** Which swipe and menu each row has (the table of plan 3D Task 6). */
object RowActions {
    private val none = RowActionPlan(null, emptyList())

    fun agentCard(closable: Boolean, removable: Boolean): RowActionPlan = RowActionPlan(
        swipe = when {
            closable -> RowActionKind.CLOSE_AGENT
            removable -> RowActionKind.REMOVE_FROM_PHONE
            else -> null
        },
        menu = listOfNotNull(
            RowActionKind.CLOSE_AGENT.takeIf { closable },
            RowActionKind.REMOVE_FROM_PHONE.takeIf { removable },
        ),
    )

    fun workspaceCard(canControl: Boolean): RowActionPlan = if (canControl) {
        RowActionPlan(RowActionKind.CLOSE_WORKSPACE, listOf(RowActionKind.RENAME_WORKSPACE, RowActionKind.CLOSE_WORKSPACE))
    } else {
        none
    }

    fun endedCard(): RowActionPlan = RowActionPlan(RowActionKind.REMOVE_ENDED, listOf(RowActionKind.REMOVE_ENDED))

    fun otherSessionCard(removable: Boolean): RowActionPlan = if (removable) {
        RowActionPlan(RowActionKind.REMOVE_FROM_PHONE, listOf(RowActionKind.REMOVE_FROM_PHONE))
    } else {
        none
    }

    fun machine(state: MachineLinkState, offersMakeDefault: Boolean): RowActionPlan {
        val last = if (state == MachineLinkState.Revoked) RowActionKind.REMOVE_MAC else RowActionKind.UNPAIR
        return RowActionPlan(
            swipe = last,
            menu = listOfNotNull(
                RowActionKind.MAKE_DEFAULT.takeIf { offersMakeDefault },
                RowActionKind.PAIR_AGAIN.takeIf { state == MachineLinkState.HostKeyChanged },
                last,
            ),
        )
    }
}
