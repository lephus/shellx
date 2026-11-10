package com.shellx.app.ui.pending

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.LinkInteractionListener
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.platform.CoreLog

/**
 * An agent's plan, drawn from its Markdown (`PlanMarkdownText.swift`): headings, bullet and numbered lists, code
 * blocks, rules and paragraphs, with inline styles (bold, italic, code, links). The lines are sorted into blocks
 * first ([PlanMarkdownText.blocks]); each block's inline marks become spans ([PlanMarkdownText.inline]). Selectable
 * for copying. A tapped link opens only when it is a web link ([PlanMarkdownText.open]). On a sheet, where the code
 * block's colour is the sheet's own, [outlinesCode] gives it a hairline edge.
 */
@Composable
fun PlanMarkdownText(markdown: String, modifier: Modifier = Modifier, color: Color = Color.Unspecified, outlinesCode: Boolean = false) {
    val typography = MaterialTheme.typography
    val accent = ShellXTheme.colors.accentText
    val uriHandler = LocalUriHandler.current
    // Parsed once per text: a redraw never parses the plan again (review A M-7).
    val parsed = remember(markdown, accent, uriHandler) {
        val code = SpanStyle(fontFamily = FontFamily.Monospace)
        val links = TextLinkStyles(SpanStyle(color = accent))
        val open = { url: String -> PlanMarkdownText.open(url, uriHandler) }
        PlanMarkdownText.blocks(markdown).map { block ->
            val text = when (block) {
                is PlanMarkdownText.Block.Heading -> block.text
                is PlanMarkdownText.Block.Bullet -> block.text
                is PlanMarkdownText.Block.Numbered -> block.text
                is PlanMarkdownText.Block.Paragraph -> block.text
                is PlanMarkdownText.Block.Code, PlanMarkdownText.Block.Rule -> null
            }
            block to (text?.let { PlanMarkdownText.inline(it, code, links, open) } ?: AnnotatedString(""))
        }
    }
    SelectionContainer(modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for ((block, inline) in parsed) {
                when (block) {
                    is PlanMarkdownText.Block.Heading -> Text(
                        inline,
                        modifier = Modifier.padding(top = 4.dp).semantics { heading() },
                        color = color,
                        style = when (block.level) {
                            1 -> typography.titleMedium.copy(fontWeight = FontWeight.SemiBold)
                            2 -> typography.titleSmall
                            else -> typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold)
                        },
                    )
                    is PlanMarkdownText.Block.Bullet -> ListRow("•", inline, block.level, color)
                    is PlanMarkdownText.Block.Numbered -> ListRow(block.number + ".", inline, block.level, color)
                    is PlanMarkdownText.Block.Code -> Text(
                        block.code,
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(MaterialTheme.colorScheme.surfaceContainerHighest, RoundedCornerShape(8.dp))
                            .then(if (outlinesCode) Modifier.border(1.dp, SheetCardOutline.color(), RoundedCornerShape(8.dp)) else Modifier)
                            .padding(10.dp),
                        color = color,
                        style = typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                    )
                    PlanMarkdownText.Block.Rule -> HorizontalDivider()
                    is PlanMarkdownText.Block.Paragraph -> Text(inline, color = color)
                }
            }
        }
    }
}

/** A list row: the marker in `onSurfaceVariant`, then the text, indented 16 dp per level (at most 4). */
@Composable
private fun ListRow(marker: String, text: AnnotatedString, level: Int, color: Color) {
    Row(Modifier.padding(start = 16.dp * minOf(level, 4)), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            marker,
            modifier = Modifier.alignByBaseline(),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = markerStyle(),
        )
        Text(text, modifier = Modifier.alignByBaseline(), color = color)
    }
}

/** The body style with tabular digits, so list numbers line up. */
@Composable
private fun markerStyle(): TextStyle = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum")

object PlanMarkdownText {
    sealed interface Block {
        data class Heading(val level: Int, val text: String) : Block
        data class Bullet(val text: String, val level: Int) : Block
        data class Numbered(val number: String, val text: String, val level: Int) : Block
        data class Code(val code: String) : Block
        data object Rule : Block
        data class Paragraph(val text: String) : Block
    }

    /** Sorts the plan's lines into blocks. Lines in a row form one paragraph; a blank line ends it. */
    fun blocks(markdown: String): List<Block> {
        val blocks = ArrayList<Block>()
        val paragraph = ArrayList<String>()
        var code: MutableList<String>? = null

        fun endParagraph() {
            if (paragraph.isEmpty()) return
            blocks += Block.Paragraph(paragraph.joinToString("\n"))
            paragraph.clear()
        }

        for (line in markdown.split('\n')) {
            val trimmed = line.trim(::isHorizontalSpace)
            val open = code
            if (open != null) {
                if (trimmed.startsWith("```")) {
                    blocks += Block.Code(open.joinToString("\n"))
                    code = null
                } else {
                    open += line
                }
                continue
            }
            val level = line.takeWhile { it == ' ' || it == '\t' }.length / 2
            val heading = heading(trimmed)
            val marker = BULLET_MARKERS.firstOrNull { trimmed.startsWith(it) }
            val numbered = numbered(trimmed)
            when {
                trimmed.startsWith("```") -> {
                    endParagraph()
                    code = ArrayList()
                }
                trimmed.isEmpty() -> endParagraph()
                heading != null -> {
                    endParagraph()
                    blocks += heading
                }
                trimmed in RULES -> {
                    endParagraph()
                    blocks += Block.Rule
                }
                marker != null -> {
                    endParagraph()
                    blocks += Block.Bullet(trimmed.substring(marker.length), level)
                }
                numbered != null -> {
                    endParagraph()
                    blocks += Block.Numbered(numbered.first, numbered.second, level)
                }
                else -> paragraph += trimmed
            }
        }
        code?.let { blocks += Block.Code(it.joinToString("\n")) }
        endParagraph()
        return blocks
    }

    /** The plan as plain lines for a card's three-line preview: no blank lines, no heading marks, list items with
     *  their bullet or number; inline Markdown is kept for [inline]. */
    fun summary(markdown: String): String = blocks(markdown).mapNotNull { block ->
        when (block) {
            is Block.Heading -> block.text
            is Block.Bullet -> "• " + block.text
            is Block.Numbered -> block.number + ". " + block.text
            is Block.Code -> block.code
            Block.Rule -> null
            is Block.Paragraph -> block.text
        }
    }.joinToString("\n")

    /**
     * Inline Markdown of one block, line breaks kept (iOS `inlineOnlyPreservingWhitespace`). Scans left to right: an
     * opening mark that finds its closing mark becomes a span over the parsed inside; otherwise it stays text.
     * Backslash escapes, `code`, **bold** / __bold__, *italic* / _italic_ (not inside a word for `_`) and
     * [label](url).
     *
     * A tapped link goes to [open], and to nothing when it is null: never to Compose's own handler, which opens any
     * scheme and lets most failures through (review A I-2).
     */
    fun inline(
        text: String,
        code: SpanStyle = SpanStyle(fontFamily = FontFamily.Monospace),
        link: TextLinkStyles? = null,
        open: ((String) -> Unit)? = null,
    ): AnnotatedString = buildAnnotatedString {
        val tapped = LinkInteractionListener { tapped -> (tapped as? LinkAnnotation.Url)?.let { open?.invoke(it.url) } }
        InlineParser(text, code, link, tapped, this).parse(0, text.length)
    }

    /**
     * Opens [url] through [handler] when it is a web link ([isWebLink]). A plan's links come from an agent, so any other
     * scheme (`file:`, `intent:`, `javascript:`, `tel:`, `content:` …) does nothing, and a phone that cannot open the
     * link (no browser, a refused URI) does nothing either. Never logs the link.
     */
    fun open(url: String, handler: UriHandler) {
        if (!isWebLink(url)) {
            CoreLog.log("plan_link_ignored")
            return
        }
        try {
            handler.openUri(url)
        } catch (e: RuntimeException) {
            CoreLog.log("plan_link_failed ${e.javaClass.simpleName}")
        }
    }

    /** `http:` or `https:`, in any case. */
    fun isWebLink(url: String): Boolean {
        val scheme = url.substringBefore(':', missingDelimiterValue = "")
        return scheme.equals("http", ignoreCase = true) || scheme.equals("https", ignoreCase = true)
    }

    private val BULLET_MARKERS = listOf("- ", "* ", "+ ")
    private val RULES = setOf("---", "***", "___")
    private const val ASCII_PUNCTUATION = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
    private val BOLD = SpanStyle(fontWeight = FontWeight.Bold)
    private val ITALIC = SpanStyle(fontStyle = FontStyle.Italic)

    /** Swift's `CharacterSet.whitespaces`: tabs and the space separators. */
    private fun isHorizontalSpace(c: Char): Boolean = c == '\t' || Character.getType(c) == Character.SPACE_SEPARATOR.toInt()

    private fun heading(line: String): Block? {
        val hashes = line.takeWhile { it == '#' }.length
        if (hashes !in 1..6 || line.getOrNull(hashes) != ' ') return null
        return Block.Heading(hashes, line.substring(hashes + 1))
    }

    /** "12. Text" or "12) Text". */
    private fun numbered(line: String): Pair<String, String>? {
        val digits = line.takeWhile { it in '0'..'9' }
        if (digits.isEmpty() || digits.length > 4) return null
        val rest = line.substring(digits.length)
        val mark = rest.firstOrNull() ?: return null
        if ((mark != '.' && mark != ')') || rest.getOrNull(1) != ' ') return null
        return digits to rest.substring(2)
    }

    private class InlineParser(
        private val s: String,
        private val code: SpanStyle,
        private val link: TextLinkStyles?,
        private val tapped: LinkInteractionListener,
        private val out: AnnotatedString.Builder,
    ) {
        fun parse(start: Int, end: Int) {
            var i = start
            while (i < end) {
                val c = s[i]
                i = when {
                    c == '\\' && i + 1 < end && s[i + 1] in ASCII_PUNCTUATION -> {
                        out.append(s[i + 1])
                        i + 2
                    }
                    c == '`' -> code(i, end)
                    (c == '*' || c == '_') && i + 1 < end && s[i + 1] == c -> bold(i, end)
                    c == '*' || c == '_' -> italic(i, end)
                    c == '[' -> link(i, end)
                    else -> {
                        out.append(c)
                        i + 1
                    }
                }
            }
        }

        /** The character at [i] stays text; the scan goes on after it. */
        private fun text(i: Int): Int {
            out.append(s[i])
            return i + 1
        }

        private fun code(i: Int, end: Int): Int {
            val close = s.indexOf('`', i + 1)
            if (close < 0 || close >= end || close == i + 1) return text(i)
            out.withStyle(code) { append(s.substring(i + 1, close)) }
            return close + 1
        }

        private fun bold(i: Int, end: Int): Int {
            val pair = s.substring(i, i + 2)
            val close = s.indexOf(pair, i + 2)
            if (close < 0 || close + 2 > end || close == i + 2) return text(i)
            out.withStyle(BOLD) { parse(i + 2, close) }
            return close + 2
        }

        private fun italic(i: Int, end: Int): Int {
            val mark = s[i]
            // `snake_case` stays text: an underscore after a letter or digit opens nothing.
            if (mark == '_' && i > 0 && s[i - 1].isLetterOrDigit()) return text(i)
            var close = -1
            var k = i + 1
            while (k < end) {
                if (s[k] == mark && (k + 1 >= end || s[k + 1] != mark)) {
                    close = k
                    break
                }
                k += if (s[k] == mark) 2 else 1
            }
            if (close < 0) return text(i)
            val inside = s.substring(i + 1, close)
            if (inside.isEmpty() || inside.first().isWhitespace() || inside.last().isWhitespace()) return text(i)
            out.withStyle(ITALIC) { parse(i + 1, close) }
            return close + 1
        }

        private fun link(i: Int, end: Int): Int {
            val close = s.indexOf(']', i + 1)
            if (close < 0 || close + 1 >= end || s[close + 1] != '(') return text(i)
            val paren = s.indexOf(')', close + 2)
            if (paren < 0 || paren >= end || paren == close + 2) return text(i)
            val url = s.substring(close + 2, paren)
            out.withLink(LinkAnnotation.Url(url, link, tapped)) { parse(i + 1, close) }
            return paren + 1
        }
    }
}
