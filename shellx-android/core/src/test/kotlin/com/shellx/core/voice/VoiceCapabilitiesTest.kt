package com.shellx.core.voice

import com.shellx.core.platform.MemoryKeyValueStore
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/** Which recognizer the mic uses (S3 §7.3): the on-device recognizer first, then the standard SpeechRecognizer on
 *  the phone, then the standard one through the phone's speech service. The mic is off only when none can run; it is
 *  never off just because the language cannot run on the phone. And the spoken language. */
class VoiceCapabilitiesTest {
    private fun engine(recognizer: Boolean, onDevice: Boolean, available: Boolean): VoiceEngine? =
        VoiceCapabilities(onDeviceRecognizer = recognizer, standardOnDevice = onDevice, standardAvailable = available).engine

    @Test fun analyzerPreferredWhenItSupportsLocale() {
        assertEquals(VoiceEngine.ON_DEVICE_RECOGNIZER, engine(recognizer = true, onDevice = true, available = true))
        assertEquals(VoiceEngine.ON_DEVICE_RECOGNIZER, engine(recognizer = true, onDevice = false, available = true))
        assertEquals(VoiceEngine.ON_DEVICE_RECOGNIZER, engine(recognizer = true, onDevice = false, available = false))
    }

    @Test fun onDeviceBeforeServer() {
        assertEquals(VoiceEngine.ON_DEVICE, engine(recognizer = false, onDevice = true, available = true))
        assertEquals(VoiceEngine.ON_DEVICE, engine(recognizer = false, onDevice = true, available = false))
    }

    @Test fun serverWhenNoOnDevice() {
        assertEquals(VoiceEngine.SERVER, engine(recognizer = false, onDevice = false, available = true))
    }

    @Test fun nilOnlyWhenNothingAvailable() {
        for (recognizer in listOf(false, true)) {
            for (onDevice in listOf(false, true)) {
                for (available in listOf(false, true)) {
                    val result = engine(recognizer, onDevice, available)
                    if (recognizer || onDevice || available) {
                        assertNotNull(result, "$recognizer $onDevice $available: some path still runs")
                    } else {
                        assertNull(result)
                    }
                }
            }
        }
        assertNull(VoiceCapabilities.NONE.engine)
    }

    @Test fun defaultLanguageVietnameseWhenPreferred() {
        assertEquals(VoiceLanguage.VIETNAMESE, VoiceLanguage.of(listOf("en-US", "vi-VN")))
        assertEquals(VoiceLanguage.VIETNAMESE, VoiceLanguage.of(listOf("vi")))
        assertEquals(VoiceLanguage.VIETNAMESE, VoiceLanguage.of(listOf("fr-FR", "vi_VN")))
        assertEquals(VoiceLanguage.ENGLISH, VoiceLanguage.of(listOf("en-GB", "fr")))
        assertEquals(VoiceLanguage.ENGLISH, VoiceLanguage.of(emptyList()))
        assertEquals("vi-VN", VoiceLanguage.VIETNAMESE.tag)
        assertEquals("en-US", VoiceLanguage.ENGLISH.tag)
    }

    @Test fun savedChoiceWinsOverPreferredLanguages() {
        val settings = MemoryKeyValueStore()

        assertEquals(VoiceLanguage.VIETNAMESE, VoiceLanguage.saved(settings, listOf("vi-VN")))
        VoiceLanguage.ENGLISH.save(settings)
        assertEquals(VoiceLanguage.ENGLISH, VoiceLanguage.saved(settings, listOf("vi-VN")))
        // An unknown stored value falls back to the preferred languages.
        settings.putString(VoiceLanguage.SETTINGS_KEY, "xx-YY")
        assertEquals(VoiceLanguage.VIETNAMESE, VoiceLanguage.saved(settings, listOf("vi-VN")))
    }
}
