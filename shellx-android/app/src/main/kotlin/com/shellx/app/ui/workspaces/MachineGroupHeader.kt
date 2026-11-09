package com.shellx.app.ui.workspaces

import android.content.Context
import android.text.format.DateFormat
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shellx.app.R
import com.shellx.app.ui.components.isLargeText
import com.shellx.app.ui.theme.AppLanguage
import com.shellx.app.ui.theme.MachineStateStyle
import com.shellx.app.ui.theme.StatusDot
import com.shellx.app.ui.theme.color
import com.shellx.core.link.MachineLinkState
import java.util.Date

/** What a Mac's group header says (`MachineGroupHeader.swift`). */
object MachineGroupHeaderText {
    /** "08:12", in the phone's 12- or 24-hour setting (Spec note 16). */
    fun time(ms: Long, context: Context): String = DateFormat.getTimeFormat(context).format(Date(ms))

    /** Why a Mac has no rows to show, or how its link stands while it has some; null when it is simply online. An
     *  offline Mac says when it was last reachable. */
    fun caption(state: MachineLinkState, machineName: String, context: Context): String? = when (state) {
        MachineLinkState.Online -> null
        is MachineLinkState.Offline -> context.getString(R.string.workspaces_group_offline, time(state.sinceMs, context))
        else -> MachineStateStyle.of(state, machineName, context.resources).text
    }

    /** "MacBook Pro · Default", "Mac mini · offline · last seen 08:12". */
    fun line(group: WorkspaceGroup, showsDefault: Boolean, context: Context): String = listOfNotNull(
        group.name,
        context.getString(R.string.machines_default).takeIf { showsDefault && group.isDefault },
        caption(group.state, group.name, context),
    ).joinToString(" · ")

    /** "MacBook Pro, Connected, Default, 4 workspaces" for TalkBack. */
    fun spokenLabel(group: WorkspaceGroup, showsDefault: Boolean, context: Context): String {
        val count = count(group)
        return listOfNotNull(
            group.name,
            MachineStateStyle.of(group.state, group.name, context.resources).text,
            context.getString(R.string.machines_default).takeIf { showsDefault && group.isDefault },
            count?.let { context.resources.getQuantityString(R.plurals.workspaces_group_count, it, it) },
        ).joinToString(", ")
    }

    /** How many workspaces the header counts: only while it shows rows and the Mac lists workspaces. */
    internal fun count(group: WorkspaceGroup): Int? = if (group.showsRows && group.listsWorkspaces) group.rows.size else null
}

/**
 * The top of a Mac's group on the home (`MachineGroupHeader.swift`): a status dot, the Mac's name in small capitals,
 * why it has no rows when it has none, and how many workspaces it lists. A tap opens Your Macs ([open]). TalkBack reads
 * it as one heading.
 */
@Composable
fun MachineGroupHeader(group: WorkspaceGroup, showsDefault: Boolean, open: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val large = isLargeText()
    val style = MachineStateStyle.of(group.state, group.name, context.resources)
    val spoken = MachineGroupHeaderText.spokenLabel(group, showsDefault, context)
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    val labelStyle = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold, letterSpacing = 0.6.sp)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .alpha(if (group.showsRows) 1f else 0.55f)
            .clickable(onClickLabel = stringResource(R.string.action_open_your_macs), onClick = open)
            .semantics {
                contentDescription = spoken
                heading()
            }
            .testTag("workspace.group.${group.id}"),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StatusDot(style.tone.color())
        Text(
            text = MachineGroupHeaderText.line(group, showsDefault, context).uppercase(AppLanguage.current()),
            modifier = Modifier.weight(1f).clearAndSetSemantics {},
            style = labelStyle,
            color = secondary,
            maxLines = if (large) 3 else 1,
            overflow = TextOverflow.Ellipsis,
        )
        MachineGroupHeaderText.count(group)?.let { count ->
            Text(
                text = "$count",
                modifier = Modifier.clearAndSetSemantics {},
                style = labelStyle.copy(fontFeatureSettings = "tnum"),
                color = secondary,
            )
        }
    }
}
