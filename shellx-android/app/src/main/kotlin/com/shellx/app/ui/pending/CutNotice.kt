package com.shellx.app.ui.pending

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentCut
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.shellx.app.R

/** "This may be cut short. See all of it on the Mac." under a preview that hit the host's limit (`CutNotice.swift`). */
@Composable
fun CutNotice() {
    val color = MaterialTheme.colorScheme.onSurfaceVariant
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Outlined.ContentCut, contentDescription = null, modifier = Modifier.size(16.dp), tint = color)
        Text(stringResource(R.string.pending_may_be_cut), style = MaterialTheme.typography.bodySmall, color = color)
    }
}
