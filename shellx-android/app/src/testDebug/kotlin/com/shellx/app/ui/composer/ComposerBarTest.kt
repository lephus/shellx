package com.shellx.app.ui.composer

import android.content.Context
import android.net.Uri
import androidx.activity.compose.LocalActivityResultRegistryOwner
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.text.AnnotatedString
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.testing.FakeResultRegistry
import com.shellx.app.testing.VoiceRig
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.voice.LocalVoice
import com.shellx.app.voice.VoiceEnvironment
import com.shellx.core.composer.AttachmentChecks
import com.shellx.core.composer.AttachmentPick
import com.shellx.core.composer.AttachmentReader
import com.shellx.core.composer.ComposerDraft
import com.shellx.core.composer.OutgoingAttachment
import com.shellx.core.text.utf8Size
import com.shellx.core.voice.VoiceCapabilities
import com.shellx.link.core.AttachmentKind
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ComposerBarTest {
    @get:Rule val compose = createComposeRule()

    private var draft by mutableStateOf(ComposerDraft())
    private val sent = mutableListOf<Pair<String, Int>>()
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private val registry = FakeResultRegistry()

    /** Names each photo as AttachmentPreparer does, from the names taken when its read starts; waits for [gate] first. */
    private class PhotoReader(val gate: CompletableDeferred<Unit>? = null) : AttachmentReader {
        override suspend fun read(pick: AttachmentPick, taken: List<String>): OutgoingAttachment {
            val name = AttachmentChecks.photoName("jpg", taken)
            gate?.await()
            return OutgoingAttachment(kind = AttachmentKind.IMAGE, name = name, data = byteArrayOf(1, 2, 3))
        }
    }

    private fun show(
        env: VoiceEnvironment? = null,
        attachmentsEnabled: Boolean = false,
        sending: Double? = null,
        reader: AttachmentReader? = null,
    ) = compose.setContent {
        ShellXTheme {
            CompositionLocalProvider(
                LocalVoice provides env,
                LocalAttachmentReader provides reader,
                LocalActivityResultRegistryOwner provides registry.owner,
            ) {
                ComposerBar(
                    draft, { draft = it }, send = { t, a -> sent += t to a.size }, attachmentsEnabled = attachmentsEnabled,
                    sending = sending,
                )
            }
        }
    }

    private fun until(condition: () -> Boolean) = compose.waitUntil(10_000) {
        compose.waitForIdle()
        condition()
    }

    private fun pickPhotos(vararg uris: String) {
        registry.answer = { uris.map(Uri::parse) }
        compose.onNodeWithTag("composer.attach").performClick()
        compose.onNodeWithText(context.getString(R.string.composer_attach_photos)).performClick()
    }

    private fun file(name: String) = OutgoingAttachment(kind = AttachmentKind.FILE, name = name, data = "error: missing import\n".toByteArray())

    @Test
    fun aTextMessageLeavesTheFieldAtOnce() {
        show()
        compose.onNodeWithTag("composer.field").performTextInput("  chạy test  ")
        compose.onNodeWithTag("composer.send").performClick()
        assertEquals(listOf("chạy test" to 0), sent)
        assertEquals("", draft.text)
    }

    @Test
    fun tooLongSaysByHowMuchAndBlocksSend() {
        draft = ComposerDraft(text = "a".repeat(16_385))
        show()
        compose.onNodeWithTag("composer.tooLong").assertTextEquals(context.getString(R.string.composer_too_long, "16,385", "16,384"))
        compose.onNodeWithTag("composer.send").assertIsNotEnabled()
    }

    @Test
    fun attachmentsAloneGoAndStayInTheBar() {
        draft = ComposerDraft(attachments = listOf(file("build-output.log")))
        show(attachmentsEnabled = true)
        compose.onNodeWithTag("composer.send").performClick()
        assertEquals(listOf("" to 1), sent)
        assertEquals(1, draft.attachments.size)
    }

    @Test
    fun sendingLocksTheBar() {
        draft = ComposerDraft(text = "x", attachments = listOf(file("build-output.log")))
        show(attachmentsEnabled = true, sending = 0.4)
        compose.onNodeWithTag("composer.sending").assertExists()
        compose.onNodeWithTag("composer.field").assertIsNotEnabled()
        compose.onNodeWithTag("composer.attach").assertIsNotEnabled()
    }

    @Test
    fun theMicShowsOnlyWhileTheBarIsEmpty() {
        show(VoiceRig.make().env)
        compose.onNodeWithTag("voice.mic").assertExists()
        draft = draft.copy(text = "x")
        compose.waitForIdle()
        compose.onNodeWithTag("voice.mic").assertDoesNotExist()
        compose.onNodeWithTag("composer.send").assertExists()
    }

    @Test
    fun aDictationStoppedAtTheLimitGoesIntoTheField() {
        val rig = VoiceRig.make()
        show(rig.env)
        compose.onNodeWithTag("voice.mic").performTouchInput { down(center) }
        until { rig.engine.starts.size == 1 }
        rig.engine.say("giữ route v1, đừng xoá. ".repeat(700))
        compose.waitForIdle()
        compose.onNodeWithTag("voice.mic").performTouchInput { up() }
        until { draft.text.isNotEmpty() }
        assertTrue(draft.text.utf8Size <= 16_384)
        compose.onNodeWithTag("composer.voiceLimit").assertExists()
        assertEquals(emptyList<Pair<String, Int>>(), sent)
    }

    @Test
    fun noRecognizerOpensTheKeyboard() {
        val rig = VoiceRig.make(VoiceCapabilities.NONE)
        show(rig.env)
        compose.onNodeWithTag("voice.mic").performSemanticsAction(SemanticsActions.OnClick)
        until { compose.onAllNodesWithTag("voice.mic").fetchSemanticsNodes().isEmpty() }
        compose.onNodeWithTag("composer.field").assertIsFocused()
    }

    /** Review A I-1: each read is named after the attachments the bar holds when it starts, the ones added a moment
     *  before included, and none overwrites another. */
    @Test
    fun photosPickedTogetherGetTheirOwnNamesAndAllStay() {
        show(attachmentsEnabled = true, reader = PhotoReader())
        pickPhotos("content://com.shellx.test.attachments/IMG_1", "content://com.shellx.test.attachments/IMG_2")
        until { draft.attachments.isNotEmpty() }
        compose.waitForIdle()
        assertEquals(listOf("photo-1.jpg", "photo-2.jpg"), draft.attachments.map { it.name })
    }

    /** Review A I-1: typing in the frame a pick arrives keeps both the letter and the attachment. */
    @Test
    fun aKeystrokeInTheFrameAPickArrivesKeepsBoth() {
        val gate = CompletableDeferred<Unit>()
        show(attachmentsEnabled = true, reader = PhotoReader(gate))
        pickPhotos("content://com.shellx.test.attachments/IMG_1")
        compose.waitForIdle()
        val setText = compose.onNodeWithTag("composer.field").fetchSemanticsNode().config[SemanticsActions.SetText].action!!
        compose.runOnUiThread {
            gate.complete(Unit)
            setText(AnnotatedString("x"))
        }
        until { draft.attachments.isNotEmpty() || draft.text.isNotEmpty() }
        compose.waitForIdle()
        assertEquals("x", draft.text)
        assertEquals(listOf("photo-1.jpg"), draft.attachments.map { it.name })
    }
}
