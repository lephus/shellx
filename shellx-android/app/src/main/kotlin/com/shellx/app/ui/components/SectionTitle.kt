package com.shellx.app.ui.components

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.sp

/** A list section's title, as the iPhone's grouped-list headers: upper case, `labelMedium`, 0.6 sp tracking, a heading. */
@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text.uppercase(LocalConfiguration.current.locales[0]),
        modifier = modifier.semantics { heading() },
        style = MaterialTheme.typography.labelMedium.copy(letterSpacing = 0.6.sp),
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}
