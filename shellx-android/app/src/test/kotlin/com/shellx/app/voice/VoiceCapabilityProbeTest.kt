package com.shellx.app.voice

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.voice.VoiceCapabilities
import com.shellx.core.voice.VoiceEngine
import com.shellx.core.voice.VoiceLanguage
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class VoiceCapabilityProbeTest {
    private fun probe(
        sdk: Int = 34,
        onDevice: Boolean = true,
        standard: Boolean = true,
        installed: suspend (RecognizerKind, VoiceLanguage) -> Set<String>? = { _, _ -> null },
    ) = VoiceCapabilityProbe(sdk, { onDevice }, { standard }, installed)

    @Test
    fun theOnDeviceRecognizerComesFirstWhenItHasTheLanguage() {
        runTest {
            val p = probe(installed = { kind, _ -> if (kind == RecognizerKind.ON_DEVICE) setOf("vi-VN") else emptySet() })
            val found = p.capabilities(VoiceLanguage.VIETNAMESE)
            assertEquals(VoiceCapabilities(true, false, true), found)
            assertEquals(VoiceEngine.ON_DEVICE_RECOGNIZER, found.engine)
        }
    }

    @Test
    fun withoutTheLanguageOnDeviceTheStandardRecognizerRuns() {
        runTest {
            val server = probe(installed = { kind, _ -> if (kind == RecognizerKind.ON_DEVICE) setOf("en-US") else emptySet() })
            assertEquals(VoiceCapabilities(false, false, true), server.capabilities(VoiceLanguage.VIETNAMESE))
            assertEquals(VoiceEngine.SERVER, server.capabilities(VoiceLanguage.VIETNAMESE).engine)
            val onPhone = probe(installed = { kind, _ -> if (kind == RecognizerKind.ON_DEVICE) setOf("en-US") else setOf("vi") })
            assertEquals(VoiceCapabilities(false, true, true), onPhone.capabilities(VoiceLanguage.VIETNAMESE))
            assertEquals(VoiceEngine.ON_DEVICE, onPhone.capabilities(VoiceLanguage.VIETNAMESE).engine)
        }
    }

    @Test
    fun aLanguageThatFailedOnDeviceIsNotOfferedAgain() {
        runTest {
            val p = probe()
            p.markFailed(VoiceLanguage.VIETNAMESE)
            assertFalse(p.onDeviceReady(VoiceLanguage.VIETNAMESE))
            assertTrue(p.onDeviceReady(VoiceLanguage.ENGLISH))
        }
    }

    @Test
    fun belowApi31ThereIsNoOnDeviceRecognizer() {
        runTest {
            assertFalse(probe(sdk = 30, onDevice = true).capabilities(VoiceLanguage.ENGLISH).onDeviceRecognizer)
        }
    }

    @Test
    fun unknownSupportIsTriedOnApi31() {
        runTest {
            assertTrue(probe(sdk = 31, installed = { _, _ -> null }).capabilities(VoiceLanguage.VIETNAMESE).onDeviceRecognizer)
        }
    }

    @Test
    fun nothingAvailableIsNoEngine() {
        runTest {
            assertNull(probe(onDevice = false, standard = false).capabilities(VoiceLanguage.VIETNAMESE).engine)
        }
    }

    @Test
    fun tagsMatchByTheirFirstSubtag() {
        assertTrue(VoiceCapabilityProbe.matches("vi", VoiceLanguage.VIETNAMESE))
        assertTrue(VoiceCapabilityProbe.matches("vi_VN", VoiceLanguage.VIETNAMESE))
        assertTrue(VoiceCapabilityProbe.matches("EN-gb", VoiceLanguage.ENGLISH))
        assertFalse(VoiceCapabilityProbe.matches("ve-VE", VoiceLanguage.VIETNAMESE))
    }
}
