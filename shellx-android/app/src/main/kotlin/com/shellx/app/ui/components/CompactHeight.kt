package com.shellx.app.ui.components

import android.annotation.SuppressLint
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * A window less than [MAX_DP] tall: Material's compact height, a phone in landscape or a short split screen. The work
 * screens then compact their top bars and put their fixed headers side by side, and the pending sheets scroll their
 * bottom bar with their content, so the chat keeps a usable height and a field being typed in stays above the
 * keyboard. The iPhone compacts its bars in landscape too. Taller windows keep the portrait layout as it is.
 */
object CompactHeight {
    const val MAX_DP: Int = 480

    /** A top bar's height in a compact-height window (Material's 64 dp otherwise). */
    val TOP_BAR: Dp = 48.dp
}

/** The window is compact in height ([CompactHeight]). */
@SuppressLint("ConfigurationScreenWidthHeight") // The window's size class, which a rotation or a resize recomposes.
@Composable
fun isCompactHeight(): Boolean = LocalConfiguration.current.screenHeightDp < CompactHeight.MAX_DP

/** The height of a work screen's top bar in this window. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun topBarHeight(): Dp = if (isCompactHeight()) CompactHeight.TOP_BAR else TopAppBarDefaults.TopAppBarExpandedHeight

/**
 * Whether a terminal page of the window holds the soft keyboard (ledger A-36). The window provides one
 * ([LocalTerminalKeyboard]) and the workspace screen keeps it told; in a short window ([isCompactHeight]) the bars above
 * the screens (the demo banner) step aside meanwhile, as the workspace's own top bar does. Main thread only.
 */
@Stable
class TerminalKeyboard {
    var held: Boolean by mutableStateOf(false)
}

/** The window's [TerminalKeyboard]; none outside the window's frame (tests of one screen). */
val LocalTerminalKeyboard = staticCompositionLocalOf<TerminalKeyboard?> { null }
