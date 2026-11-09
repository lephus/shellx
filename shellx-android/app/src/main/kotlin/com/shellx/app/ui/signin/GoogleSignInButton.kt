package com.shellx.app.ui.signin

import android.annotation.SuppressLint
import android.content.Context
import androidx.annotation.DrawableRes
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shellx.app.R

/** Google's branding page, Light theme (https://developers.google.com/identity/branding-guidelines, "Color"). */
object GoogleButtonColors {
    val Fill = Color(0xFFFFFFFF)
    val Stroke = Color(0xFF747775)
    val Text = Color(0xFF1F1F1F)
}

/**
 * Google's own files for the button (contracts §11): the "G" from Google's sign-in bundle and Google Sans with its OFL
 * text. Each is looked for once per process, and is null until it is in the app.
 */
object GoogleBranding {
    const val MARK = "ic_google_g"
    const val FONT_ASSET = "fonts/GoogleSans.ttf"
    const val FONT_LICENCE_ASSET = "fonts/GoogleSans-OFL.txt"

    private class Answer<T>(val value: T)

    @Volatile private var mark: Answer<Int?>? = null

    @Volatile private var font: Answer<FontFamily?>? = null

    /**
     * The official "G" (20 × 20 dp), looked up by name so the app builds without it: `res/raw/keep_google_branding.xml`
     * keeps it from the resource shrinker.
     */
    @SuppressLint("DiscouragedApi")
    @DrawableRes
    fun mark(context: Context): Int? = (
        mark ?: Answer(context.resources.getIdentifier(MARK, "drawable", context.packageName).takeIf { it != 0 })
            .also { mark = it }
        ).value

    /** Google Sans Medium, only when its SIL OFL 1.1 text is next to it; null: the platform font. */
    fun font(context: Context): FontFamily? = (font ?: Answer(load(context)).also { font = it }).value

    private fun load(context: Context): FontFamily? {
        val files = try {
            context.assets.list(FONT_ASSET.substringBeforeLast('/')).orEmpty().toSet()
        } catch (e: java.io.IOException) {
            emptySet()
        }
        if (FONT_ASSET.substringAfterLast('/') !in files || FONT_LICENCE_ASSET.substringAfterLast('/') !in files) return null
        return FontFamily(
            Font(
                FONT_ASSET, context.assets, FontWeight.Medium,
                variationSettings = FontVariation.Settings(FontVariation.weight(500)),
            ),
        )
    }
}

/**
 * "Continue with Google" drawn to Google's branding page (contracts §11; plan 1C's button with the page's "Android &
 * Web" values): the Light theme in both appearances, a pill with a 1 dp inside stroke, 12 dp before the G, 10 dp after
 * it and 12 dp after the text, Google Sans Medium 14/20, at least 48 dp high. Without Google's files the G and its gap
 * are left out and the platform font is used. The G is never tinted, resized or redrawn. While [busy] a spinner
 * replaces the words, and TalkBack still hears the button's name. [mark] and [font] are parameters so tests can draw
 * the button with and without Google's files.
 */
@Composable
fun GoogleSignInButton(
    onClick: () -> Unit,
    busy: Boolean,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    @DrawableRes mark: Int? = GoogleBranding.mark(LocalContext.current),
    font: FontFamily? = GoogleBranding.font(LocalContext.current),
) {
    val label = stringResource(R.string.signin_google)
    Surface(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .alpha(if (enabled) 1f else 0.4f)
            .testTag("signin.google")
            .then(if (busy) Modifier.semantics { contentDescription = label } else Modifier),
        shape = RoundedCornerShape(50),
        color = GoogleButtonColors.Fill,
        contentColor = GoogleButtonColors.Text,
        border = BorderStroke(1.dp, GoogleButtonColors.Stroke),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (busy) {
                CircularProgressIndicator(Modifier.size(20.dp), color = GoogleButtonColors.Text, strokeWidth = 2.dp)
            } else {
                if (mark != null) {
                    Image(
                        painter = painterResource(mark),
                        contentDescription = null,
                        modifier = Modifier.size(20.dp).testTag("signin.google.mark"),
                    )
                    Spacer(Modifier.width(10.dp))
                }
                Text(
                    text = label,
                    color = GoogleButtonColors.Text,
                    fontFamily = font ?: FontFamily.Default,
                    fontWeight = FontWeight.Medium,
                    fontSize = 14.sp,
                    lineHeight = 20.sp,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}
