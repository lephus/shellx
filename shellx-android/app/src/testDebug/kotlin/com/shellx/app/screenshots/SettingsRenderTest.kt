package com.shellx.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.ui.settings.AccountActions
import com.shellx.app.ui.settings.DeleteAccountCard
import com.shellx.app.ui.settings.DeleteAccountFlow
import com.shellx.app.ui.settings.SettingsScreen
import com.shellx.app.ui.settings.settingsVoiceService
import com.shellx.app.ui.theme.AppAppearance
import com.shellx.core.voice.VoiceLanguage
import com.shellx.core.voice.VoiceService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Settings (AccountRenderTests' settings renders) and the deletion card's steps (DeleteAccountRenderTests). The card is
 * rendered directly: a dialog's window is not in the capture (Spec note 10). The Working step's spinner is a still one.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
class SettingsRenderTest {
    private val voiceScope = CoroutineScope(SupervisorJob())
    private val stillSpinner: @Composable (Modifier) -> Unit = { CircularProgressIndicator(progress = { 0.7f }, modifier = it) }

    @After
    fun tearDown() {
        voiceScope.cancel()
    }

    @Composable
    private fun Settings(email: String, account: AccountActions?, voice: VoiceService? = null) {
        SettingsScreen(
            email = email, account = account, appearance = AppAppearance.SYSTEM, onAppearance = {}, voice = voice,
            version = "1.0.0 (100)", openMachines = {}, back = {},
        )
    }

    @Composable
    private fun Card(step: DeleteAccountFlow.Step) {
        Box(
            Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(24.dp),
            contentAlignment = Alignment.Center,
        ) { DeleteAccountCard(step, onDelete = {}, onCancel = {}, spinner = stillSpinner) }
    }

    @Test
    fun settings() {
        assertRenders("settings") { Settings("phu@example.com", AccountActions({}, {})) }
    }

    @Test
    fun settingsWithVoice() {
        val voice = settingsVoiceService(voiceScope, VoiceLanguage.ENGLISH)
        // The recognizer is known before the first frame, so the footer's spinner never shows.
        runBlocking { voice.refreshEngine() }
        assertRenders("settings-voice") { Settings("phu@example.com", AccountActions({}, {}), voice) }
    }

    @Test
    fun settingsInTheDemo() {
        assertRenders("settings-demo") { Settings("demo@shellx.pro", null) }
    }

    @Test
    fun deleteConfirm() {
        assertRenders("delete-account-confirm") { Card(DeleteAccountFlow.Step.Confirm) }
    }

    @Test
    fun deleteWorking() {
        assertRenders("delete-account-working") { Card(DeleteAccountFlow.Step.Working) }
    }

    @Test
    fun deleteFailed() {
        assertRenders("delete-account-failed") { Card(DeleteAccountFlow.Step.Failed(R.string.signin_error_reauth_required)) }
    }
}
