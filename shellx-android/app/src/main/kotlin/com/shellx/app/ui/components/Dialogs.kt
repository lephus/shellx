package com.shellx.app.ui.components

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme

/**
 * A confirmation (the iPhone's `confirmationDialog`/`alert` with a destructive button): Cancel (`common_cancel`) and
 * [confirmLabel]. Confirm runs [onDismiss] then [onConfirm], once even when tapped twice; [destructive] tints it
 * `statusError`.
 */
@Composable
fun ConfirmDialog(
    title: String,
    text: String?,
    confirmLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    destructive: Boolean = true,
) {
    var confirmed by remember { mutableStateOf(false) }
    val colors = ShellXTheme.colors
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = text?.let { { Text(it) } },
        confirmButton = {
            TextButton(
                onClick = {
                    if (confirmed) return@TextButton
                    confirmed = true
                    onDismiss()
                    onConfirm()
                },
            ) { Text(confirmLabel, color = if (destructive) colors.statusError else colors.accentText) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel), color = colors.accentText) }
        },
    )
}

/** A message with one OK (`common_ok`). */
@Composable
fun MessageDialog(title: String?, text: String, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = title?.let { { Text(it) } },
        text = { Text(text) },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.common_ok), color = ShellXTheme.colors.accentText)
            }
        },
    )
}
