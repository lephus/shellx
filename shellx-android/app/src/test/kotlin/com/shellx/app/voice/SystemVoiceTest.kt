package com.shellx.app.voice

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.FakeVoicePermissions
import com.shellx.app.testing.ManualClock
import com.shellx.app.testing.WorkRig
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.platform.MemoryKeyValueStore
import com.shellx.core.voice.VoiceEngine
import com.shellx.core.voice.VoiceLanguage
import com.shellx.core.voice.VoiceService
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/** The process-level speech recognition: every account's service hears that the on-device recognizer failed. */
@RunWith(AndroidJUnit4::class)
class SystemVoiceTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val rig = WorkRig.make()
    private val clock = ManualClock()

    /** API 33, the on-device recognizer present, the standard one only through the speech service. */
    private val voice = SystemVoice(
        context,
        probe = VoiceCapabilityProbe(sdkInt = 33, onDeviceAvailable = { true }, standardAvailable = { true }) { _, _ -> null },
    )

    @After
    fun tearDown() = rig.close()

    private fun service(): VoiceService {
        val settings = MemoryKeyValueStore().also { VoiceLanguage.VIETNAMESE.save(it) }
        return voice.makeService(rig.hub, FakeVoicePermissions(), LatencyLog(), settings, clock)
    }

    /** Final review m-5: after the demo made its own service, the real account's Settings › Voice still names the
     *  recognizer really used once the on-device one fails. */
    @Test
    fun everyServiceHearsThatTheOnDeviceRecognizerFailed() = runBlocking {
        val real = service()
        real.refreshEngine()
        assertEquals(VoiceEngine.ON_DEVICE_RECOGNIZER, real.engine)
        val demo = service()
        demo.refreshEngine()

        voice.primaryFailed(VoiceLanguage.VIETNAMESE)

        assertEquals("the older service names the speech service", VoiceEngine.SERVER, real.engine)
        assertEquals(VoiceEngine.SERVER, demo.engine)
    }
}
