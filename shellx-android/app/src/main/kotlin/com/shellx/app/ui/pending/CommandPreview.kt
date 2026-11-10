package com.shellx.app.ui.pending

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.text.takeGraphemes

/** How a card's preview is set: a tool's input in monospace, a question in the body font, a plan's summary with its
 *  inline Markdown (bold, code). */
enum class CommandPreviewStyle { COMMAND, PROSE, MARKDOWN }

/**
 * A request's text on its card (`CommandPreview.swift`): at most three lines, with "Show more" when there is more than
 * fits. A preview may be 8 KB of anything (emoji, right-to-left text): only its first
 * [CommandPreview.COLLAPSED_CHARACTERS] are laid out, more than three lines can ever show.
 */
@Composable
fun CommandPreview(text: String, style: CommandPreviewStyle = CommandPreviewStyle.COMMAND, showMore: () -> Unit) {
    val (shown, cut) = remember(text) { CommandPreview.collapsed(text) }
    val accent = ShellXTheme.colors.accentText
    val uriHandler = LocalUriHandler.current
    val content = remember(shown, style, accent, uriHandler) {
        when (style) {
            CommandPreviewStyle.MARKDOWN -> PlanMarkdownText.inline(
                shown, link = TextLinkStyles(SpanStyle(color = accent)), open = { PlanMarkdownText.open(it, uriHandler) },
            )
            CommandPreviewStyle.COMMAND, CommandPreviewStyle.PROSE -> AnnotatedString(shown)
        }
    }
    // Whether the three-line limit left some of the shown text out.
    var overflows by remember(content) { mutableStateOf(false) }
    val typography = MaterialTheme.typography
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = content,
            modifier = Modifier.fillMaxWidth(),
            style = if (style == CommandPreviewStyle.COMMAND) typography.bodySmall.copy(fontFamily = FontFamily.Monospace) else typography.bodyMedium,
            maxLines = CommandPreview.LINE_LIMIT,
            overflow = TextOverflow.Ellipsis,
            onTextLayout = { overflows = it.hasVisualOverflow },
        )
        if (cut || overflows) {
            TextButton(
                onClick = showMore,
                modifier = Modifier.heightIn(min = 48.dp).testTag("pending.showMore"),
                contentPadding = PaddingValues(horizontal = 0.dp, vertical = 8.dp),
            ) {
                Text(
                    stringResource(R.string.pending_show_more),
                    style = typography.bodySmall.copy(fontWeight = FontWeight.SemiBold),
                    color = accent,
                )
            }
        }
    }
}

object CommandPreview {
    const val LINE_LIMIT = 3
    const val COLLAPSED_CHARACTERS = 600

    /** The first [COLLAPSED_CHARACTERS] characters (graphemes) of [text], and whether that left some out. */
    fun collapsed(text: String): Pair<String, Boolean> {
        val shown = text.takeGraphemes(COLLAPSED_CHARACTERS)
        return shown to (shown.length < text.length)
    }
}
