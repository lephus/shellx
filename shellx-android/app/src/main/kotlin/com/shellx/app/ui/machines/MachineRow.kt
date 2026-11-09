package com.shellx.app.ui.machines

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Laptop
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.components.isLargeText
import com.shellx.app.ui.theme.MachineStateStyle
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.theme.StatusDot
import com.shellx.app.ui.theme.StatusTone
import com.shellx.app.ui.theme.color
import com.shellx.core.link.MachineLinkState

/**
 * One paired Mac in Your Macs (`MachineRow.swift`): its name, a status dot with the state in words, the Default badge,
 * and, when the link stopped for good, the one action that helps ([pairAgain], [remove]). At large text the icon steps
 * aside and the badge and the action go under the name, so the name never breaks inside a word.
 */
@Composable
fun MachineRow(name: String, state: MachineLinkState, isDefault: Boolean, pairAgain: () -> Unit, remove: () -> Unit) {
    val large = isLargeText()
    if (large) {
        Column(
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Details(name, state, isDefault, large = true)
            Action(state, pairAgain, remove)
        }
    } else {
        Row(
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.weight(1f)) { Details(name, state, isDefault, large = false) }
            Action(state, pairAgain, remove)
        }
    }
}

/** The name, the badge and the state, read by TalkBack as "name, state text[, Default]". */
@Composable
private fun Details(name: String, state: MachineLinkState, isDefault: Boolean, large: Boolean) {
    val style = MachineStateStyle.of(state, name, LocalContext.current.resources)
    val defaultWord = stringResource(R.string.machines_default)
    val spoken = listOfNotNull(name, style.text, defaultWord.takeIf { isDefault }).joinToString(", ")
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Row(
        modifier = Modifier.clearAndSetSemantics { contentDescription = spoken }.testTag("machine.row"),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        if (!large) Icon(Icons.Outlined.Laptop, contentDescription = null, tint = secondary)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            val nameText: @Composable (Modifier) -> Unit = { modifier ->
                Text(
                    text = name,
                    modifier = modifier,
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
                    color = MaterialTheme.colorScheme.onSurface,
                )
            }
            if (large) {
                nameText(Modifier)
                if (isDefault) DefaultBadge()
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    nameText(Modifier.weight(1f, fill = false))
                    if (isDefault) DefaultBadge()
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                StatusDot(style.tone.color())
                Text(style.text, style = MaterialTheme.typography.bodyMedium, color = secondary)
            }
        }
    }
}

/** Pair Again for a Mac whose key changed; Remove for a Mac that removed this phone; nothing otherwise. */
@Composable
private fun Action(state: MachineLinkState, pairAgain: () -> Unit, remove: () -> Unit) {
    when (state) {
        MachineLinkState.HostKeyChanged -> ActionButton(
            label = stringResource(R.string.machines_pair_again),
            color = ShellXTheme.colors.accentText,
            tag = "machine.pairAgain",
            onClick = pairAgain,
        )
        MachineLinkState.Revoked -> ActionButton(
            label = stringResource(R.string.machines_remove),
            color = StatusTone.ERROR.color(),
            tag = "machine.remove",
            onClick = remove,
        )
        else -> Unit
    }
}

@Composable
private fun ActionButton(label: String, color: Color, tag: String, onClick: () -> Unit) {
    OutlinedButton(
        onClick = onClick,
        modifier = Modifier.heightIn(min = 48.dp).testTag(tag),
        colors = ButtonDefaults.outlinedButtonColors(contentColor = color),
    ) { Text(label) }
}

/** The "Default" capsule next to the default Mac's name; TalkBack hears "Default" in the row's label instead. */
@Composable
fun DefaultBadge() {
    val accentText = ShellXTheme.colors.accentText
    Text(
        text = stringResource(R.string.machines_default),
        modifier = Modifier
            .clearAndSetSemantics {}
            .background(accentText.copy(alpha = 0.14f), CircleShape)
            .padding(horizontal = 8.dp, vertical = 2.dp),
        style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
        color = accentText,
        maxLines = 1,
    )
}
