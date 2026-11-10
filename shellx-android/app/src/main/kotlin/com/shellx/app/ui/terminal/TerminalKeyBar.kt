package com.shellx.app.ui.terminal

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.East
import androidx.compose.material.icons.filled.KeyboardHide
import androidx.compose.material.icons.filled.North
import androidx.compose.material.icons.filled.South
import androidx.compose.material.icons.filled.West
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.terminal.TerminalBarKey

/** The key bar's buttons: its keys in [TerminalBarKey] order, then hide keyboard. */
sealed interface TerminalKeyBarItem {
    data class Key(val key: TerminalBarKey) : TerminalKeyBarItem

    data object HideKeyboard : TerminalKeyBarItem
}

private val ROW_HEIGHT = 48.dp
private val KEY_HEIGHT = 40.dp
private val GAP = 6.dp
private val SIDE_PADDING = 8.dp

/** A key's slot, its cap with the half gaps beside it: at least the 48 dp touch target, at most a 52 dp cap. */
private val MIN_SLOT = 48.dp
private val MAX_SLOT = 52.dp + GAP

/**
 * The keys a phone keyboard lacks (`TerminalKeyBar.swift`), in a 48 dp row over it: esc, tab, ctrl (held for the next
 * key), the four arrows and, at the trailing end, hide keyboard. Each key's touch target is its slot: the row's full
 * height and its share of the width with the gaps beside it, at least 48 dp wide. A window too narrow for eight such
 * slots (under 384 dp) scrolls the row sideways rather than shrink a key below 48 dp. A latched ctrl is drawn in the
 * accent and read as selected. No key takes focus, so the terminal keeps the keyboard.
 */
@Composable
fun TerminalKeyBar(ctrlLatched: Boolean, press: (TerminalKeyBarItem) -> Unit, modifier: Modifier = Modifier) {
    val line = MaterialTheme.colorScheme.outlineVariant
    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .height(ROW_HEIGHT)
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .drawBehind { drawLine(line, Offset(0f, 0f), Offset(size.width, 0f), strokeWidth = 1.dp.toPx()) }
            .testTag("terminal.keyBar"),
    ) {
        // The side padding gives way first (a 393 dp phone fits eight 48 dp slots with 4.5 dp at each end).
        val fits = maxWidth >= MIN_SLOT * 8
        val edge = if (fits) minOf(SIDE_PADDING - GAP / 2, (maxWidth - MIN_SLOT * 8) / 2) else SIDE_PADDING - GAP / 2
        val slot = if (fits) ((maxWidth - edge * 2) / 8).coerceIn(MIN_SLOT, MAX_SLOT) else MIN_SLOT
        Row(
            Modifier
                .fillMaxSize()
                .then(if (fits) Modifier else Modifier.horizontalScroll(rememberScrollState()))
                .padding(horizontal = edge),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            for (key in TerminalBarKey.entries) {
                KeyButton(TerminalKeyBarItem.Key(key), slot, latched = key == TerminalBarKey.CTRL && ctrlLatched, press)
            }
            if (fits) Spacer(Modifier.weight(1f))
            KeyButton(TerminalKeyBarItem.HideKeyboard, slot, latched = false, press)
        }
    }
}

@Composable
private fun KeyButton(item: TerminalKeyBarItem, slot: Dp, latched: Boolean, press: (TerminalKeyBarItem) -> Unit) {
    val colors = ShellXTheme.colors
    val shape = RoundedCornerShape(8.dp)
    val label = stringResource(label(item))
    val latchedText = stringResource(R.string.terminal_key_ctrl_latched)
    val isCtrl = item == TerminalKeyBarItem.Key(TerminalBarKey.CTRL)
    val content = if (latched) colors.accentText else MaterialTheme.colorScheme.onSurface
    Box(
        Modifier
            .width(slot)
            .fillMaxHeight()
            .minimumInteractiveComponentSize()
            .focusProperties { canFocus = false }
            .clickable(role = Role.Button) { press(item) }
            .testTag(tag(item))
            .clearAndSetSemantics {
                contentDescription = label
                role = Role.Button
                onClick { press(item); true }
                if (isCtrl) {
                    selected = latched
                    if (latched) stateDescription = latchedText
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .padding(horizontal = GAP / 2)
                .fillMaxWidth()
                .height(KEY_HEIGHT)
                .clip(shape)
                .background(if (latched) colors.accent.copy(alpha = 0.2f) else MaterialTheme.colorScheme.background, shape)
                .then(if (latched) Modifier.border(1.dp, colors.accent.copy(alpha = 0.45f), shape) else Modifier),
            contentAlignment = Alignment.Center,
        ) {
            Cap(item, content)
        }
    }
}

@Composable
private fun Cap(item: TerminalKeyBarItem, color: Color) {
    val caption = when (item) {
        TerminalKeyBarItem.Key(TerminalBarKey.ESCAPE) -> R.string.terminal_cap_esc
        TerminalKeyBarItem.Key(TerminalBarKey.TAB) -> R.string.terminal_cap_tab
        TerminalKeyBarItem.Key(TerminalBarKey.CTRL) -> R.string.terminal_cap_ctrl
        else -> null
    }
    if (caption != null) {
        Text(
            stringResource(caption),
            style = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 15.sp, fontWeight = FontWeight.Medium),
            color = color,
            maxLines = 1,
        )
        return
    }
    val icon: ImageVector = when (item) {
        TerminalKeyBarItem.Key(TerminalBarKey.LEFT) -> Icons.Filled.West
        TerminalKeyBarItem.Key(TerminalBarKey.UP) -> Icons.Filled.North
        TerminalKeyBarItem.Key(TerminalBarKey.DOWN) -> Icons.Filled.South
        TerminalKeyBarItem.Key(TerminalBarKey.RIGHT) -> Icons.Filled.East
        else -> Icons.Filled.KeyboardHide
    }
    Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(20.dp))
}

private fun label(item: TerminalKeyBarItem): Int = when (item) {
    TerminalKeyBarItem.HideKeyboard -> R.string.terminal_key_hide_keyboard
    is TerminalKeyBarItem.Key -> when (item.key) {
        TerminalBarKey.ESCAPE -> R.string.terminal_key_escape
        TerminalBarKey.TAB -> R.string.terminal_key_tab
        TerminalBarKey.CTRL -> R.string.terminal_key_ctrl
        TerminalBarKey.LEFT -> R.string.terminal_key_left
        TerminalBarKey.UP -> R.string.terminal_key_up
        TerminalBarKey.DOWN -> R.string.terminal_key_down
        TerminalBarKey.RIGHT -> R.string.terminal_key_right
    }
}

private fun tag(item: TerminalKeyBarItem): String = when (item) {
    TerminalKeyBarItem.HideKeyboard -> "terminal.key.hideKeyboard"
    is TerminalKeyBarItem.Key -> when (item.key) {
        TerminalBarKey.ESCAPE -> "terminal.key.escape"
        TerminalBarKey.TAB -> "terminal.key.tab"
        TerminalBarKey.CTRL -> "terminal.key.ctrl"
        TerminalBarKey.LEFT -> "terminal.key.left"
        TerminalBarKey.UP -> "terminal.key.up"
        TerminalBarKey.DOWN -> "terminal.key.down"
        TerminalBarKey.RIGHT -> "terminal.key.right"
    }
}
