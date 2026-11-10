package com.shellx.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp
import com.shellx.app.ui.theme.ShellXTheme

/** A card's look (S3 §7.2): `ShellXTheme.colors.surface` in [shape], with a 1 dp outline of `onSurface` at 10 %
 *  ([outline] replaces it), its content clipped to the shape. */
@Composable
fun Modifier.shellXCard(shape: Shape, outline: Color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f)): Modifier =
    this.clip(shape).background(ShellXTheme.colors.surface, shape).border(1.dp, outline, shape)
