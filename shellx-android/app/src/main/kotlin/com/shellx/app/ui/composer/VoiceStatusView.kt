package com.shellx.app.ui.composer

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.MicOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.shellx.app.R
import com.shellx.app.ui.theme.AppLanguage
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.home.ComposerValidation
import com.shellx.core.platform.CoreLog
import com.shellx.core.text.graphemes
import com.shellx.core.voice.VoiceInputModel

/**
 * What the mic says above where it is used (`VoiceStatusView.swift`):
 * - while listening, the newest words as they come with a level bar, "Listening…" before the first word, "Release to
 *   cancel" once cancel is armed, and the byte limit once reached;
 * - a denied microphone, with "Open Settings"; no recognizer right now, with "You can still type".
 *
 * Shows nothing while idle.
 */
@Composable
fun VoiceStatusView(model: VoiceInputModel, level: Float, modifier: Modifier = Modifier) {
    val state by model.state.collectAsStateWithLifecycle()
    // The last words shown, kept while the final text comes (not state: only this composition reads it).
    val last = remember(model) { LastWords() }
    when (val phase = state.phase) {
        VoiceInputModel.Phase.Idle -> last.text = ""
        is VoiceInputModel.Phase.Listening -> last.text = phase.text
        is VoiceInputModel.Phase.CancelArmed -> last.text = phase.text
        else -> Unit
    }
    when (val phase = state.phase) {
        VoiceInputModel.Phase.Idle -> Unit
        is VoiceInputModel.Phase.Listening -> Panel(phase.text, armed = false, finishing = false, level, state.limitReached, model.maxBytes, modifier)
        is VoiceInputModel.Phase.CancelArmed -> Panel(phase.text, armed = true, finishing = false, level, state.limitReached, model.maxBytes, modifier)
        VoiceInputModel.Phase.Finishing -> Panel(last.text, armed = false, finishing = true, level, state.limitReached, model.maxBytes, modifier)
        is VoiceInputModel.Phase.Denied -> Notice(stringResource(R.string.voice_denied), settings = true, dismiss = model::dismiss, modifier)
        VoiceInputModel.Phase.Unavailable ->
            Notice(stringResource(R.string.settings_voice_unavailable), settings = false, dismiss = model::dismiss, modifier)
    }
}

private class LastWords {
    var text = ""
}

object VoiceStatusView {
    /** The characters shown of a long dictation. */
    const val SHOWN_CHARACTERS = 160

    /** The text when it has at most [SHOWN_CHARACTERS] graphemes; else "…" and the newest ones, from a word
     *  boundary. */
    fun newest(text: String): String {
        val graphemes = text.graphemes()
        if (graphemes.size <= SHOWN_CHARACTERS) return text
        val tail = graphemes.takeLast(SHOWN_CHARACTERS)
        val space = tail.indexOfFirst { g -> g.any { it.isWhitespace() } }
        return "…" + tail.drop(if (space >= 0) space + 1 else 0).joinToString("")
    }
}

@Composable
private fun Panel(text: String, armed: Boolean, finishing: Boolean, level: Float, limitReached: Boolean, maxBytes: Int, modifier: Modifier) {
    val colors = ShellXTheme.colors
    val shape = RoundedCornerShape(14.dp)
    Column(
        modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerHigh, shape)
            .border(1.5.dp, if (armed) colors.statusError else colors.accent, shape)
            .padding(12.dp)
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        val blank = text.isBlank()
        Text(
            if (blank) stringResource(R.string.voice_listening) else VoiceStatusView.newest(text),
            style = MaterialTheme.typography.bodyLarge,
            color = if (blank || armed) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.fillMaxWidth().testTag("voice.text"),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (finishing) {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
            } else {
                LevelBar(level)
            }
            if (armed) {
                Row(
                    Modifier.testTag("voice.releaseToCancel"),
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.Cancel, contentDescription = null, tint = colors.statusError, modifier = Modifier.size(16.dp))
                    Text(
                        stringResource(R.string.voice_release_to_cancel),
                        style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
                        color = colors.statusError,
                    )
                }
            }
        }
        if (limitReached) {
            Text(
                stringResource(R.string.voice_limit, ComposerValidation.byteCount(maxBytes, AppLanguage.current())),
                style = MaterialTheme.typography.bodySmall,
                color = colors.statusError,
                modifier = Modifier.testTag("voice.limit"),
            )
        }
    }
}

/** A capsule filled as loud as the microphone is (at least its height). */
@Composable
private fun LevelBar(level: Float) {
    val track = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.2f)
    val fill = ShellXTheme.colors.accent
    Box(
        Modifier
            .widthIn(max = 160.dp)
            .fillMaxWidth()
            .height(6.dp)
            .drawBehind {
                val radius = CornerRadius(size.height / 2)
                drawRoundRect(track, cornerRadius = radius)
                val width = maxOf(size.height, size.width * level.coerceIn(0f, 1f))
                drawRoundRect(fill, size = Size(width, size.height), cornerRadius = radius)
            },
    )
}

@Composable
private fun Notice(text: String, settings: Boolean, dismiss: () -> Unit, modifier: Modifier) {
    val context = LocalContext.current
    Row(
        modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerHigh, RoundedCornerShape(14.dp))
            .padding(start = 12.dp)
            .testTag("voice.notice"),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            Icons.Outlined.MicOff, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 14.dp).size(18.dp),
        )
        Column(Modifier.weight(1f).padding(vertical = 12.dp)) {
            Text(text, style = MaterialTheme.typography.bodySmall)
            if (settings) {
                TextButton(
                    onClick = {
                        try {
                            context.startActivity(
                                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                            )
                        } catch (e: ActivityNotFoundException) {
                            CoreLog.log("voice_settings_missing")
                        }
                    },
                    modifier = Modifier.heightIn(min = 48.dp).testTag("voice.openSettings"),
                ) {
                    Text(
                        stringResource(R.string.voice_open_settings),
                        style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
                        color = ShellXTheme.colors.accentText,
                    )
                }
            }
        }
        IconButton(onClick = dismiss, modifier = Modifier.size(48.dp)) {
            Icon(
                Icons.Filled.Close, contentDescription = stringResource(R.string.common_close),
                tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp),
            )
        }
    }
}
