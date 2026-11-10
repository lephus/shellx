package com.shellx.app.ui.workspaces

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.shellx.app.R

/**
 * The page of a shell chip on a Mac whose ShellX shows no terminals (no `terminal_view`; `ShellPanePlaceholder.swift`):
 * a terminal symbol and "Update ShellX on the Mac to see the terminal." on a card, in the terminal's place. Tag
 * `workspace.shell.placeholder`.
 */
@Composable
fun ShellPanePlaceholder(modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(14.dp)
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(start = 12.dp, end = 12.dp, bottom = 12.dp)
            .background(MaterialTheme.colorScheme.surfaceContainer, shape)
            .border(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f), shape)
            .padding(24.dp)
            .semantics(mergeDescendants = true) {}
            .testTag("workspace.shell.placeholder"),
        verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(Icons.Outlined.Terminal, contentDescription = null, modifier = Modifier.size(40.dp), tint = secondary)
        Text(
            stringResource(R.string.terminal_needs_update),
            style = MaterialTheme.typography.bodyLarge,
            color = secondary,
            textAlign = TextAlign.Center,
        )
    }
}
