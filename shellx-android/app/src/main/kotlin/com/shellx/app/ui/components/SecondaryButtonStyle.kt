package com.shellx.app.ui.components

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.shellx.app.ui.theme.ShellXTheme

/**
 * A secondary button next to a [PrimaryButton] (`SecondaryButtonStyle.swift`): the same shape and height, a soft tint
 * of [color] behind a label in that colour (no gradient, no border).
 */
@Composable
fun SecondaryButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    color: Color = ShellXTheme.colors.accentText,
    content: @Composable RowScope.() -> Unit,
) {
    Button(
        onClick = onClick,
        modifier = modifier.heightIn(min = 50.dp),
        enabled = enabled,
        shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = color.copy(alpha = 0.14f),
            contentColor = color,
            disabledContainerColor = color.copy(alpha = 0.14f * 0.4f),
            disabledContentColor = color.copy(alpha = 0.4f),
        ),
        elevation = null,
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        content = content,
    )
}
