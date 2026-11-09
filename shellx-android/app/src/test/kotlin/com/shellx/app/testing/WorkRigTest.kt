package com.shellx.app.testing

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.voice.SpeechRunId
import com.shellx.core.voice.VoiceLanguage
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WorkRigTest {
    @Test
    fun theRigHasTwoWorkspacesAndOneWorkingSession() {
        val rig = WorkRig.make()
        try {
            assertEquals(listOf("ws-shellx", "ws-web"), rig.hub.workspaceRows(rig.machineId).map { it.id.workspaceId })
            assertEquals(listOf("s1"), rig.hub.liveSessions.map { it.session.sessionId })
            assertEquals("t-zsh", rig.workspaceModel().selectedTerminalId)
        } finally {
            rig.close()
        }
    }

    @Test
    fun theFakeEngineHandsTheWordsToItsRun() {
        runTest {
            val engine = FakeSpeechEngine()
            val run = SpeechRunId()
            val words = engine.start(run, VoiceLanguage.VIETNAMESE, listOf("PR"))
            engine.say("xin chào")
            assertEquals("xin chào", words.receive())
            engine.finalText = "xin chào bạn"
            assertEquals("xin chào bạn", engine.finish(run))
            assertTrue(words.isClosedForReceive)
            assertEquals(listOf(run), engine.finishCalls)
            assertNull(engine.activeRun)
        }
    }
}
