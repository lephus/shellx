package com.shellx.app.ui.signin

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.shellx.app.ui.theme.ShellXTheme
import java.text.BreakIterator

/**
 * The line under the sign-in title, typed like a terminal's: each tagline is typed, held, erased, and the next one
 * follows after a pause, for as long as the screen shows. Without motion the first tagline is there at once.
 */
object TypedTagline {
    /** Typing starts when the logo's chevrons are in place. */
    const val START_MS = SignInLogo.SLIDE_MS
    const val TYPE_MS = 28L
    const val HOLD_MS = 2_400L
    const val ERASE_MS = 12L
    const val PAUSE_MS = 300L

    /** The cursor is the block "▍": three eighths of a letter's cell wide, as tall as the letters' line. */
    const val CURSOR_WIDTH_EM = 0.225f
    const val CURSOR_HEIGHT_EM = 1.2f

    enum class Phase { TYPING, HOLDING, ERASING, PAUSING }

    /** What shows at one moment: the first [shown] letters of tagline [line]. */
    data class Frame(val line: Int, val shown: Int, val phase: Phase)

    /** When each letter of each tagline shows; [letters] is how many letters each tagline has. */
    class Schedule(private val letters: List<Int>) {
        init {
            require(letters.isNotEmpty()) { "no tagline to type" }
        }

        /** One round through every tagline. */
        val cycleMs: Long = letters.sumOf { it * TYPE_MS + HOLD_MS + it * ERASE_MS + PAUSE_MS }

        /** Without motion: the first tagline, whole. */
        val still: Frame = Frame(0, letters[0], Phase.HOLDING)

        /** The frame at [ms] since the screen appeared. */
        fun at(ms: Long): Frame {
            if (ms < START_MS) return Frame(0, 0, Phase.PAUSING)
            var left = (ms - START_MS) % cycleMs
            for (line in letters.indices) {
                val count = letters[line]
                if (left < count * TYPE_MS) return Frame(line, (left / TYPE_MS).toInt(), Phase.TYPING)
                left -= count * TYPE_MS
                if (left < HOLD_MS) return Frame(line, count, Phase.HOLDING)
                left -= HOLD_MS
                if (left < count * ERASE_MS) return Frame(line, count - (left / ERASE_MS).toInt(), Phase.ERASING)
                left -= count * ERASE_MS
                if (left < PAUSE_MS) return Frame(line, 0, Phase.PAUSING)
                left -= PAUSE_MS
            }
            error("$ms ms is past the cycle of $cycleMs ms")
        }
    }

    /** Whether the cursor after the typed letters is lit at [ms]: steady while letters change, blinking at rest. */
    fun cursorOn(phase: Phase, ms: Long): Boolean =
        phase == Phase.TYPING || phase == Phase.ERASING || SignInLogo.cursorOn(ms)

    /** Where each letter of [text] ends, so a letter and its accents are typed as one. */
    fun letters(text: String): IntArray {
        val breaks = BreakIterator.getCharacterInstance()
        breaks.setText(text)
        val ends = ArrayList<Int>(text.length)
        breaks.first()
        var end = breaks.next()
        while (end != BreakIterator.DONE) {
            ends += end
            end = breaks.next()
        }
        return ends.toIntArray()
    }

    /**
     * [text] with its first [shown] characters in the text's colour and the rest [hidden]: the whole line is laid out
     * from the first letter, so no letter moves while the line is typed, and TalkBack reads the whole line.
     */
    fun styled(text: String, shown: Int, hidden: Color = Color.Transparent): AnnotatedString = buildAnnotatedString {
        append(text)
        if (shown < text.length) addStyle(SpanStyle(color = hidden), shown.coerceAtLeast(0), text.length)
    }
}

/**
 * The typed [lines] at [introMs] (milliseconds since the screen appeared; null: no motion, the first line whole and
 * no cursor). One line of small monospace text, centred, with room kept for two lines so nothing below moves when a
 * line wraps. The cursor is drawn after the last typed letter, not added to the text.
 */
@Composable
fun TypedTagline(lines: List<String>, introMs: (() -> Long)?, modifier: Modifier = Modifier) {
    val letters = remember(lines) { lines.map(TypedTagline::letters) }
    val schedule = remember(letters) { TypedTagline.Schedule(letters.map { it.size }) }
    // A frame's change recomposes the text; the clock's ticks in between do not.
    val frame by remember(schedule, introMs) { derivedStateOf { introMs?.let { schedule.at(it()) } ?: schedule.still } }
    val cursorOn by remember(introMs) {
        derivedStateOf { introMs != null && TypedTagline.cursorOn(frame.phase, introMs()) }
    }
    val line = lines[frame.line]
    val typed = if (frame.shown == 0) 0 else letters[frame.line][frame.shown - 1]
    val text = remember(line, typed) { TypedTagline.styled(line, typed) }
    var placed by remember { mutableStateOf<TextLayoutResult?>(null) }
    val style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace)
    val cursorColor = ShellXTheme.colors.statusDone

    Text(
        text = text,
        modifier = modifier
            .fillMaxWidth()
            .testTag("signin.tagline")
            .drawWithContent {
                drawContent()
                val layout = placed
                if (cursorOn && layout != null && layout.layoutInput.text.length >= typed) {
                    val caret = layout.getCursorRect(typed)
                    val em = style.fontSize.toPx()
                    val height = minOf(caret.height, em * TypedTagline.CURSOR_HEIGHT_EM)
                    drawRect(
                        cursorColor,
                        topLeft = Offset(caret.left + 1.dp.toPx(), caret.top + (caret.height - height) / 2),
                        size = Size(em * TypedTagline.CURSOR_WIDTH_EM, height),
                    )
                }
            },
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
        minLines = 2,
        onTextLayout = { placed = it },
        style = style,
    )
}
