package com.shellx.app.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalDensity

/** Whether text is at a large accessibility size (font scale 1.3 or more): where the iPhone switches layout at its
 *  accessibility sizes, Android switches here. */
@Composable
@ReadOnlyComposable
fun isLargeText(): Boolean = LocalDensity.current.fontScale >= 1.3f
