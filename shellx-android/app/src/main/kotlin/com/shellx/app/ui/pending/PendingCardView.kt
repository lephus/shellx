package com.shellx.app.ui.pending

import android.content.res.Resources
import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Assignment
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.outlined.Laptop
import androidx.compose.material.icons.outlined.QuestionAnswer
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.components.PrimaryButton
import com.shellx.app.ui.components.SecondaryButton
import com.shellx.app.ui.components.isLargeText
import com.shellx.app.ui.components.shellXCard
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.theme.StatusDot
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.pending.AgentLabel
import com.shellx.core.pending.DecisionStatus
import com.shellx.core.pending.PendingAction
import com.shellx.core.pending.PermissionLayout
import com.shellx.core.pending.actions
import com.shellx.core.pending.previewText
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.PendingItem
import com.shellx.link.core.PendingKind

/** A card's buttons (`PendingCardView.Actions`). */
class PendingCardActions(
    /** A button that decides at once (Allow, Deny, Always allow, All tools). */
    val decide: (LinkDecision) -> Unit = {},
    /** "Answer" or "Review plan": the item's sheet. */
    val openSheet: () -> Unit = {},
    /** "Show more": everything the preview cut. */
    val showMore: () -> Unit = {},
    /** "Try again" after no answer. */
    val retry: () -> Unit = {},
)

/**
 * One pending request as a card (`PendingCardView.swift`): who asks and what (`workspace · agent`, the Mac when there
 * are several, the kind of request), up to three lines of what it is about, then its buttons.
 *
 * The buttons come from `PendingItem.actions`: a permission shows Deny and Allow, with "Always allow" and "All tools"
 * behind `⋯`, as 3C's [PermissionLayout] lays them out; a question opens the answer sheet, a plan the review sheet;
 * anything else says to open it on the Mac. The buttons are off while the card cannot act (reconnecting, or its
 * decision is out or taken). No hub here, so render tests can show every kind and state.
 */
@Composable
fun PendingCardView(
    item: MachinePendingItem,
    status: DecisionStatus?,
    showsMachineName: Boolean,
    actions: PendingCardActions = PendingCardActions(),
    modifier: Modifier = Modifier,
) {
    val enabled = item.actionable && (status == null || status is DecisionStatus.Failed)
    val shape = RoundedCornerShape(14.dp)
    Box(
        modifier = modifier
            .testTag("pending.card")
            .fillMaxWidth()
            .shellXCard(shape, outline = ShellXTheme.colors.accent.copy(alpha = 0.55f))
            .padding(12.dp),
    ) {
        CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurface) {
            CardContent(item, status, showsMachineName, enabled, actions)
        }
    }
}

@Composable
private fun CardContent(item: MachinePendingItem, status: DecisionStatus?, showsMachineName: Boolean, enabled: Boolean, actions: PendingCardActions) {
    val res = LocalContext.current.resources
    val pending = item.item
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val secondary = MaterialTheme.colorScheme.onSurfaceVariant
        val spoken = PendingCardView.spokenHeadline(item, showsMachineName, res)
        Row(
            modifier = Modifier.clearAndSetSemantics {
                contentDescription = spoken
                heading()
            },
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            StatusDot(ShellXTheme.colors.statusNeedsYou)
            Text(
                PendingCardView.headline(item, showsMachineName, res, secondary),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
        val preview = pending.previewText
        if (!preview.isNullOrEmpty()) {
            when (pending.kind) {
                PendingKind.PERMISSION -> CommandPreview(preview, CommandPreviewStyle.COMMAND, actions.showMore)
                PendingKind.EXIT_PLAN -> CommandPreview(PlanMarkdownText.summary(preview), CommandPreviewStyle.MARKDOWN, actions.showMore)
                else -> CommandPreview(preview, CommandPreviewStyle.PROSE, actions.showMore)
            }
        }
        PendingCardStatusLine(status, item.actionable, item.machineName, retry = actions.retry)
        Buttons(pending, enabled, actions)
    }
}

@Composable
private fun Buttons(pending: PendingItem, enabled: Boolean, actions: PendingCardActions) {
    val offered = pending.actions
    when {
        offered == listOf(PendingAction.OpenOnMac) -> Row(
            modifier = Modifier.heightIn(min = 48.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val color = MaterialTheme.colorScheme.onSurfaceVariant
            Icon(Icons.Outlined.Laptop, contentDescription = null, tint = color)
            Text(
                stringResource(R.string.pending_open_on_mac),
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                color = color,
            )
        }
        pending.kind == PendingKind.PERMISSION -> PermissionButtons(PermissionLayout.of(offered), enabled, actions)
        pending.kind == PendingKind.QUESTION -> SheetButton(R.string.pending_answer, Icons.Outlined.QuestionAnswer, enabled, actions.openSheet)
        else -> SheetButton(R.string.pending_review_plan, Icons.AutoMirrored.Outlined.Assignment, enabled, actions.openSheet)
    }
}

@Composable
private fun PermissionButtons(layout: PermissionLayout, enabled: Boolean, actions: PendingCardActions) {
    val stacked = isLargeText()
    val decide: (PendingAction) -> Unit = { action -> action.decision?.let(actions.decide) }
    val buttons = @Composable { wide: Modifier ->
        for (action in layout.buttons) {
            val label = @Composable {
                Text(stringResource(PendingCardView.title(action)), style = MaterialTheme.typography.titleMedium)
            }
            if (action == PendingAction.Deny) {
                SecondaryButton(
                    onClick = { decide(action) }, modifier = wide.testTag("pending.deny"), enabled = enabled,
                    color = ShellXTheme.colors.statusError,
                ) { label() }
            } else {
                PrimaryButton(onClick = { decide(action) }, modifier = wide.testTag("pending.allow"), enabled = enabled) { label() }
            }
        }
        if (layout.menu.isNotEmpty()) {
            MoreMenu(layout.menu, enabled, wide = stacked || layout.buttons.isEmpty(), decide)
        }
    }
    if (stacked) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) { buttons(Modifier.fillMaxWidth()) }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            buttons(Modifier.weight(1f))
        }
    }
}

/** "⋯": the lasting grants, in a menu. */
@Composable
private fun MoreMenu(menu: List<PendingAction>, enabled: Boolean, wide: Boolean, decide: (PendingAction) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val accent = ShellXTheme.colors.accentText
    Box {
        IconButton(
            onClick = { open = true },
            enabled = enabled,
            modifier = Modifier
                .then(if (wide) Modifier.fillMaxWidth() else Modifier)
                .sizeIn(minWidth = 50.dp, minHeight = 50.dp)
                .alpha(if (enabled) 1f else 0.4f)
                .background(accent.copy(alpha = 0.14f), RoundedCornerShape(12.dp))
                .testTag("pending.more"),
            shape = RoundedCornerShape(12.dp),
            colors = IconButtonDefaults.iconButtonColors(contentColor = accent, disabledContentColor = accent),
        ) {
            Icon(Icons.Filled.MoreHoriz, contentDescription = stringResource(R.string.pending_more))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            for (action in menu) {
                DropdownMenuItem(
                    text = { Text(stringResource(PendingCardView.title(action))) },
                    onClick = {
                        open = false
                        decide(action)
                    },
                )
            }
        }
    }
}

@Composable
private fun SheetButton(@StringRes title: Int, icon: ImageVector, enabled: Boolean, open: () -> Unit) {
    PrimaryButton(onClick = open, modifier = Modifier.fillMaxWidth().testTag("pending.open"), enabled = enabled) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
        Text(stringResource(title), style = MaterialTheme.typography.titleMedium)
    }
}

object PendingCardView {
    /** "**shellx** · Claude Code · MacBook Pro · wants to run Bash": the workspace SemiBold, the rest in [secondary]. */
    fun headline(item: MachinePendingItem, showsMachineName: Boolean, res: Resources, secondary: Color): AnnotatedString =
        workspaceThen(item.item.workspaceTitle, details(item, showsMachineName, res), secondary)

    /** "shellx, Claude Code, MacBook Pro, wants to run Bash" for TalkBack. */
    fun spokenHeadline(item: MachinePendingItem, showsMachineName: Boolean, res: Resources): String =
        (listOf(item.item.workspaceTitle) + details(item, showsMachineName, res)).joinToString(", ")

    /** "wants to run Bash", "asks", "proposes a plan". */
    fun kindText(item: PendingItem, res: Resources): String = when (item.kind) {
        PendingKind.PERMISSION -> item.toolName?.takeIf { it.isNotEmpty() }?.let { res.getString(R.string.pending_kind_permission, it) }
            ?: res.getString(R.string.pending_kind_permission_no_tool)
        PendingKind.QUESTION -> res.getString(R.string.pending_kind_question)
        PendingKind.EXIT_PLAN -> res.getString(R.string.pending_kind_plan)
        else -> res.getString(R.string.pending_kind_other)
    }

    /** The title of a button that decides at once (`PendingAction.title` of `PendingCardView.swift`). */
    @StringRes
    fun title(action: PendingAction): Int = when (action) {
        PendingAction.AllowOnce -> R.string.pending_allow
        PendingAction.Deny, PendingAction.RejectPlan -> R.string.pending_deny
        PendingAction.AllowAlways -> R.string.pending_allow_always
        PendingAction.AllowAllTools -> R.string.pending_allow_all_tools
        PendingAction.Answer -> R.string.pending_answer
        is PendingAction.ApprovePlan -> R.string.pending_plan_approve
        PendingAction.RevisePlan -> R.string.pending_plan_revise
        PendingAction.OpenOnMac -> R.string.pending_open_on_mac
    }

    /** The workspace's title in SemiBold, then " · " and [parts] joined by " · " in [secondary]. */
    internal fun workspaceThen(workspace: String, parts: List<String>, secondary: Color): AnnotatedString = buildAnnotatedString {
        withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(workspace) }
        withStyle(SpanStyle(color = secondary)) { append(" · " + parts.joinToString(" · ")) }
    }

    private fun details(item: MachinePendingItem, showsMachineName: Boolean, res: Resources): List<String> = buildList {
        val agent = AgentLabel.of(item.item.agent).text
        if (agent.isNotEmpty()) add(agent)
        if (showsMachineName) add(item.machineName)
        add(kindText(item.item, res))
    }
}
