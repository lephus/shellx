package com.shellx.app.ui.settings

import android.content.res.Resources
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.core.voice.VoiceEngine
import com.shellx.core.voice.VoiceLanguage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Settings' words: where the voice is recognised, the version, and the Licenses link. */
@RunWith(AndroidJUnit4::class)
class SettingsTextTest {
    private val res: Resources = ApplicationProvider.getApplicationContext<android.content.Context>().resources

    @Test
    fun theVoiceLineNamesThePathUsed() {
        val onDevice = res.getString(R.string.settings_voice_on_device)
        assertEquals(onDevice, VoiceSectionText.explanation(VoiceEngine.ON_DEVICE, VoiceLanguage.ENGLISH, res))
        assertEquals(onDevice, VoiceSectionText.explanation(VoiceEngine.ON_DEVICE_RECOGNIZER, VoiceLanguage.VIETNAMESE, res))
        val server = VoiceSectionText.explanation(VoiceEngine.SERVER, VoiceLanguage.VIETNAMESE, res)
        assertTrue(server, server.contains("Vietnamese"))
        assertEquals(
            res.getString(R.string.settings_voice_unavailable),
            VoiceSectionText.explanation(null, VoiceLanguage.ENGLISH, res),
        )
        assertEquals(R.string.voice_language_vietnamese, VoiceSectionText.name(VoiceLanguage.VIETNAMESE))
        assertEquals(R.string.voice_language_english, VoiceSectionText.name(VoiceLanguage.ENGLISH))
    }

    @Test
    fun theVersionShowsItsBuildNumber() {
        assertEquals("1.0.0 (100)", versionText("1.0.0", 100))
    }
}
