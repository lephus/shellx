package com.shellx.app.ui.pending

import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.ui.pending.PlanMarkdownText.Block.Bullet
import com.shellx.app.ui.pending.PlanMarkdownText.Block.Code
import com.shellx.app.ui.pending.PlanMarkdownText.Block.Heading
import com.shellx.app.ui.pending.PlanMarkdownText.Block.Numbered
import com.shellx.app.ui.pending.PlanMarkdownText.Block.Paragraph
import com.shellx.app.ui.pending.PlanMarkdownText.Block.Rule
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/** Ports `PendingCardRenderTests.testPlanMarkdownBlocks`, plus the inline marks Android parses itself. */
@RunWith(AndroidJUnit4::class)
class PlanMarkdownTextTest {
    private val plan = "## Pair Macs by QR\n\n1. Add `PairingModel` and its **tests** first.\n2. Build the pairing sheet: scan, paste, confirm.\n" +
        "3. \"Your Macs\" with unpair.\n\n### Checks\n- `swift test` for ShellXAppCore\n  - render tests in light and dark\n```\ndev.sh test all\n```"

    @Test
    fun blocksFollowThePlansLines() {
        assertEquals(
            listOf(
                Heading(2, "Pair Macs by QR"), Numbered("1", "Add `PairingModel` and its **tests** first.", 0),
                Numbered("2", "Build the pairing sheet: scan, paste, confirm.", 0), Numbered("3", "\"Your Macs\" with unpair.", 0),
                Heading(3, "Checks"), Bullet("`swift test` for ShellXAppCore", 0), Bullet("render tests in light and dark", 1),
                Code("dev.sh test all"),
            ),
            PlanMarkdownText.blocks(plan),
        )
        assertEquals(listOf(Paragraph("one\ntwo"), Paragraph("three")), PlanMarkdownText.blocks("one\ntwo\n\nthree"))
        assertEquals(listOf(Paragraph("#hashtag"), Rule, Code("open")), PlanMarkdownText.blocks("#hashtag\n---\n```\nopen"))
    }

    @Test
    fun aCardsSummaryCarriesTextNotMarks() {
        assertEquals("Title\n1. First\n• item\ntext", PlanMarkdownText.summary("## Title\n\n1. First\n- item\n---\ntext"))
    }

    @Test
    fun inlineMarksBecomeSpans() {
        val s = PlanMarkdownText.inline("Add `PairingModel` and its **tests** first, *now*.")
        assertEquals("Add PairingModel and its tests first, now.", s.text)
        fun spans(p: (SpanStyle) -> Boolean) = s.spanStyles.filter { p(it.item) }.map { s.text.substring(it.start, it.end) }
        assertEquals(listOf("PairingModel"), spans { it.fontFamily == FontFamily.Monospace })
        assertEquals(listOf("tests"), spans { it.fontWeight == FontWeight.Bold })
        assertEquals(listOf("now"), spans { it.fontStyle == FontStyle.Italic })
    }

    @Test
    fun unclosedMarksAndIntrawordUnderscoresStayText() {
        for (t in listOf("**unclosed", "snake_case_name", "a * b * c", "`open code", "[label](no close", "dòng một\n**không đóng")) {
            assertEquals(t, PlanMarkdownText.inline(t).text)
        }
        assertEquals("2 * 3", PlanMarkdownText.inline("2 \\* 3").text)
    }

    @Test
    fun linksKeepTheirLabelAndUrl() {
        val s = PlanMarkdownText.inline("see [the docs](https://shellx.pro/docs) now")
        assertEquals("see the docs now", s.text)
        val link = s.getLinkAnnotations(0, s.length).single()
        assertEquals("https://shellx.pro/docs", (link.item as LinkAnnotation.Url).url)
        assertEquals("the docs", s.text.substring(link.start, link.end))
    }
}
