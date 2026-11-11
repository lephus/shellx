package com.shellx.app.ui.signin

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.theme.ShellXTheme

/**
 * The three numbered steps on the sign-in screen. They come in one after another when the logo's chevrons are in
 * place, each fading in while it rises, then stay.
 */
object SignInGuide {
    /** The first row starts when the logo's chevrons are in place; each next one [STEP_MS] later. */
    const val START_MS = SignInLogo.SLIDE_MS
    const val STEP_MS = 80L
    const val ROW_MS = 250L

    /** How far a row rises while it comes in, in dp. */
    const val RISE_DP = 8

    const val ROWS = 3

    /** When the last row is in. */
    const val END_MS = START_MS + (ROWS - 1) * STEP_MS + ROW_MS

    /** The number's circle, in dp at font scale 1 (it grows with the text), and its tint of the brand green. */
    const val CIRCLE_DP = 28
    const val CIRCLE_TINT = 0.14f

    /** How far row [row] (from 0) has come in at [ms]: 0 unseen and [RISE_DP] low, 1 in place. Null: no motion. */
    fun reveal(row: Int, ms: Long?): Float {
        if (ms == null) return 1f
        val left = 1f - ((ms - START_MS - row * STEP_MS).toFloat() / ROW_MS).coerceIn(0f, 1f)
        return 1f - left * left * left
    }
}

/**
 * The three steps, each a number in the brand green on a tinted circle and its words, drawn as far in as [reveal] says
 * for its row (from 0). The rows keep their room from the first frame, so nothing below them moves while they come
 * in; a new value moves a row's layer and recomposes nothing. TalkBack reads a row as one: "1, Sign in with…".
 */
@Composable
fun SignInGuide(reveal: (row: Int) -> Float, modifier: Modifier = Modifier) {
    val steps = listOf(R.string.signin_guide_1, R.string.signin_guide_2, R.string.signin_guide_3)
    val green = ShellXTheme.colors.statusDone
    val circle = (SignInGuide.CIRCLE_DP * LocalDensity.current.fontScale).dp
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        steps.forEachIndexed { row, words ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("signin.guide.${row + 1}")
                    .graphicsLayer {
                        val shown = reveal(row)
                        alpha = shown
                        translationY = (1f - shown) * SignInGuide.RISE_DP.dp.toPx()
                    }
                    .semantics(mergeDescendants = true) {},
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier.size(circle).background(green.copy(alpha = SignInGuide.CIRCLE_TINT), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "${row + 1}",
                        style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold),
                        color = green,
                    )
                }
                Text(
                    text = stringResource(words),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onBackground,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}
