package com.shellx.app.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme
import kotlinx.coroutines.launch

/** One action of a row: what the swipe, the long-press menu and TalkBack's custom actions run. */
data class RowAction(val label: String, val icon: ImageVector, val destructive: Boolean, val run: () -> Unit)

/**
 * A row (S3 §7.2): a swipe from the end runs [swipe] once and the row returns to rest; a long press opens [menu]
 * (every action, in order); TalkBack lists [menu] as custom actions. [enabled] false turns off the click, the gestures
 * and the custom actions, and draws the row at 38 % alpha. [modifier] lands on the node that holds the click and the
 * custom actions.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ActionRow(
    swipe: RowAction?,
    menu: List<RowAction>,
    onClick: (() -> Unit)?,
    onClickLabel: String?,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable () -> Unit,
) {
    val state = rememberSwipeToDismissBoxState()
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    var menuOpen by remember { mutableStateOf(false) }
    val currentSwipe by rememberUpdatedState(swipe)
    val swipes = swipe != null && enabled
    val hasMenu = enabled && menu.isNotEmpty()
    val actionsLabel = stringResource(R.string.row_actions)
    val openMenu: () -> Unit = {
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        menuOpen = true
    }

    val interaction = when {
        onClick != null -> Modifier.combinedClickable(
            enabled = enabled,
            onClickLabel = onClickLabel,
            onLongClickLabel = if (hasMenu) actionsLabel else null,
            onLongClick = if (hasMenu) openMenu else null,
            onClick = onClick,
        )
        hasMenu -> Modifier
            .pointerInput(menu) { detectTapGestures(onLongPress = { openMenu() }) }
            .semantics { onLongClick(actionsLabel) { openMenu(); true } }
        else -> Modifier
    }
    val customActions = if (hasMenu) {
        Modifier.semantics {
            this.customActions = menu.map { action -> CustomAccessibilityAction(action.label) { action.run(); true } }
        }
    } else {
        Modifier
    }

    SwipeToDismissBox(
        state = state,
        backgroundContent = {
            val shown = swipe
            if (shown != null && state.dismissDirection == SwipeToDismissBoxValue.EndToStart) SwipeBackground(shown)
        },
        modifier = modifier.then(customActions).then(interaction),
        enableDismissFromStartToEnd = false,
        enableDismissFromEndToStart = swipes,
        gesturesEnabled = swipes,
        onDismiss = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) {
                currentSwipe?.run()
                scope.launch { state.reset() }
            }
        },
    ) {
        Box(Modifier.fillMaxWidth().alpha(if (enabled) 1f else 0.38f)) {
            content()
            DropdownMenu(expanded = menuOpen && hasMenu, onDismissRequest = { menuOpen = false }) {
                for (action in menu) {
                    val tint = if (action.destructive) ShellXTheme.colors.statusError else LocalContentColor.current
                    DropdownMenuItem(
                        text = { Text(action.label, color = tint) },
                        leadingIcon = { Icon(action.icon, contentDescription = null, tint = tint) },
                        onClick = {
                            menuOpen = false
                            action.run()
                        },
                    )
                }
            }
        }
    }
}

/** What a swipe uncovers: the action's colour, with its icon and label at the end edge. TalkBack skips it. */
@Composable
private fun SwipeBackground(action: RowAction) {
    val fill = if (action.destructive) ShellXTheme.colors.statusError else ShellXTheme.colors.accentText
    Row(
        Modifier.fillMaxSize().background(fill).padding(horizontal = 20.dp).clearAndSetSemantics {},
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(action.icon, contentDescription = null, tint = Color.White)
        Spacer(Modifier.width(8.dp))
        Text(action.label, color = Color.White, style = MaterialTheme.typography.labelLarge)
    }
}
