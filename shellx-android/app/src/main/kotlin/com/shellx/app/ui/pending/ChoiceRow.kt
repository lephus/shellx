package com.shellx.app.ui.pending

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.unit.dp
import com.shellx.app.ui.theme.ShellXTheme

/**
 * A checklist row (`ChoiceRow.swift`): its text, and a checkmark when chosen. The row's owner makes it selectable
 * ([modifier]), so TalkBack hears "selected"; the mark is hidden from it. At least 48 dp tall, across its width.
 */
@Composable
fun ChoiceRow(selected: Boolean, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Row(
        modifier = modifier.fillMaxWidth().heightIn(min = 48.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp), content = content)
        Icon(
            Icons.Filled.Check,
            contentDescription = null,
            modifier = Modifier.alpha(if (selected) 1f else 0f),
            tint = ShellXTheme.colors.accentText,
        )
    }
}
