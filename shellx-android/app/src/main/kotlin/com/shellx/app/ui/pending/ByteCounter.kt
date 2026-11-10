package com.shellx.app.ui.pending

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme

/** "120 / 4096 bytes" under a field whose text has a byte limit on the wire; "Too long: …" in the error colour past it
 *  (`ByteCounter.swift`). */
@Composable
fun ByteCounter(used: Int, limit: Int, modifier: Modifier = Modifier) {
    val over = used > limit
    Text(
        text = stringResource(if (over) R.string.pending_too_long else R.string.pending_bytes, used, limit),
        modifier = modifier.fillMaxWidth(),
        style = MaterialTheme.typography.bodySmall.copy(fontFeatureSettings = "tnum"),
        color = if (over) ShellXTheme.colors.statusError else MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.End,
    )
}
