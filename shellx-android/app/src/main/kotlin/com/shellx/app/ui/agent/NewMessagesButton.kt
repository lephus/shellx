package com.shellx.app.ui.agent

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme

/** "New messages ↓" over the bottom of an agent's chat (`NewMessagesButton.swift`): newer entries came while the user
 *  read older ones; a tap scrolls to the newest. A capsule in the primary button's colours, at least 48 dp tall. */
@Composable
fun NewMessagesButton(action: () -> Unit) {
    val colors = ShellXTheme.colors
    Row(
        modifier = Modifier
            .heightIn(min = 48.dp)
            .clip(CircleShape)
            .background(colors.accent, CircleShape)
            .clickable(onClickLabel = stringResource(R.string.agent_new_messages_hint), role = Role.Button, onClick = action)
            .testTag("agent.newMessages")
            .padding(horizontal = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.ArrowDownward, contentDescription = null, modifier = Modifier.size(18.dp), tint = colors.onAccent)
        Text(
            stringResource(R.string.agent_new_messages),
            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
            color = colors.onAccent,
        )
    }
}
