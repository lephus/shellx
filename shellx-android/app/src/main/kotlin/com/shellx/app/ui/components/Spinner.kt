package com.shellx.app.ui.components

import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * How the work screens draw a wait (an indeterminate [CircularProgressIndicator]). Render tests provide a still one:
 * an endless animation never lets a capture settle (3D's snapshot watchdog fails it after 60 s), and the screens that
 * wait sit deep in the tree (a pane's agent chat, a sheet's status line), so a local reaches them all.
 */
val LocalSpinner: ProvidableCompositionLocal<@Composable (Modifier, Dp) -> Unit> = staticCompositionLocalOf {
    { modifier, strokeWidth -> CircularProgressIndicator(modifier, strokeWidth = strokeWidth) }
}

/** The wait mark: [LocalSpinner]'s spinner. */
@Composable
fun Spinner(modifier: Modifier = Modifier, strokeWidth: Dp = 2.dp) = LocalSpinner.current(modifier, strokeWidth)
