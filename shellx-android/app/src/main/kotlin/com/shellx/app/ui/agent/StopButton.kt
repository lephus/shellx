package com.shellx.app.ui.agent

import android.content.res.Resources
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Dangerous
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.link.core.ChatInterruptOutcome

/**
 * "Stop" (`StopButton.swift`), in `statusError`: a tap interrupts the agent's current turn; a long press opens a menu
 * with "Force Stop…", which the owner confirms first. "Force Stop…" is also a TalkBack action. The owner shows it only
 * while the session works or waits for the user.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun StopButton(stop: () -> Unit, forceStop: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    val red = ShellXTheme.colors.statusError
    val forceLabel = stringResource(R.string.agent_force_stop_menu)
    Box {
        Box(
            modifier = Modifier
                .heightIn(min = 48.dp)
                .widthIn(min = 48.dp)
                .clip(RoundedCornerShape(12.dp))
                .combinedClickable(
                    onClick = stop,
                    onLongClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        menu = true
                    },
                )
                .semantics {
                    role = Role.Button
                    customActions = listOf(CustomAccessibilityAction(forceLabel) { forceStop(); true })
                }
                .testTag("agent.stop")
                .padding(horizontal = 12.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(stringResource(R.string.agent_stop), style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), color = red)
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(
                text = { Text(forceLabel, color = red) },
                leadingIcon = { Icon(Icons.Outlined.Dangerous, contentDescription = null, tint = red) },
                onClick = {
                    menu = false
                    forceStop()
                },
            )
        }
    }
}

object StopButton {
    /** What the screen says after a Stop or Force Stop: the Mac's answer, or why there was none. */
    fun text(outcome: ChatInterruptOutcome?, offline: Boolean, machineName: String, res: Resources): String = when (outcome) {
        ChatInterruptOutcome.SENT -> res.getString(R.string.agent_stop_sent)
        ChatInterruptOutcome.NOT_FOUND -> res.getString(R.string.agent_gone)
        null -> if (offline) res.getString(R.string.home_note_offline, machineName) else res.getString(R.string.agent_stop_no_answer)
        else -> res.getString(R.string.agent_stop_failed)
    }
}
