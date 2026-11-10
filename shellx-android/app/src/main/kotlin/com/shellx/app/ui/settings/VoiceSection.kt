package com.shellx.app.ui.settings

import android.content.res.Resources
import androidx.annotation.StringRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.shellx.app.R
import com.shellx.core.voice.VoiceEngine
import com.shellx.core.voice.VoiceLanguage
import com.shellx.core.voice.VoiceService

/** Settings › Voice's words (`VoiceSection.swift`). */
object VoiceSectionText {
    @StringRes
    fun name(language: VoiceLanguage): Int = when (language) {
        VoiceLanguage.VIETNAMESE -> R.string.voice_language_vietnamese
        VoiceLanguage.ENGLISH -> R.string.voice_language_english
    }

    /** The line under the language for [engine]: on this phone; through the phone's speech service (said plainly, and
     *  that ShellX never receives the voice); or not right now (typing still works). */
    fun explanation(engine: VoiceEngine?, language: VoiceLanguage, res: Resources): String = when (engine) {
        VoiceEngine.ON_DEVICE_RECOGNIZER, VoiceEngine.ON_DEVICE -> res.getString(R.string.settings_voice_on_device)
        VoiceEngine.SERVER -> res.getString(R.string.settings_voice_server, res.getString(name(language)))
        null -> res.getString(R.string.settings_voice_unavailable)
    }
}

/**
 * Settings › Voice (`VoiceSection.swift`; contracts §20, plan 3E builds the [VoiceService]): the spoken language (a menu
 * of the two), and under it where the voice is recognised for it, asked again each time the language changes (a small
 * spinner until the phone answers).
 */
@Composable
fun VoiceSection(service: VoiceService) {
    val state by service.state.collectAsStateWithLifecycle()
    val res = LocalContext.current.resources
    var picking by remember { mutableStateOf(false) }
    LaunchedEffect(state.language) { service.refreshEngine() }

    SettingsSectionLayout(
        title = stringResource(R.string.settings_voice_title),
        footer = {
            if (state.engineKnown) {
                SettingsFooterText(
                    VoiceSectionText.explanation(state.engine, state.language, res),
                    Modifier.testTag("settings.voice.engine"),
                )
            } else {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
            }
        },
    ) {
        Box {
            ListItem(
                headlineContent = { Text(stringResource(R.string.settings_voice_language)) },
                modifier = Modifier.clickable { picking = true }.testTag("settings.voice.language"),
                trailingContent = {
                    Text(
                        text = stringResource(VoiceSectionText.name(state.language)),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                },
                colors = settingsRowColors(),
            )
            DropdownMenu(expanded = picking, onDismissRequest = { picking = false }) {
                for (language in VoiceLanguage.entries) {
                    DropdownMenuItem(
                        text = { Text(stringResource(VoiceSectionText.name(language))) },
                        onClick = {
                            picking = false
                            service.setLanguage(language)
                        },
                    )
                }
            }
        }
    }
}
