package com.shellx.app.screenshots

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.VoiceRig
import com.shellx.app.ui.composer.AttachmentStrip
import com.shellx.app.ui.composer.AttachmentThumbnails
import com.shellx.app.ui.composer.ComposerBar
import com.shellx.app.voice.LocalVoice
import com.shellx.core.composer.ComposerDraft
import com.shellx.core.composer.OutgoingAttachment
import com.shellx.core.voice.VoiceCapabilities
import com.shellx.core.voice.VoiceInputModel
import com.shellx.link.core.AttachmentKind
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The composer part of MicButtonRenderTests: the bar at the bottom of the screen in each mic and attachment state. */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
class ComposerRenderTest {
    private val spoken = "Chạy test cho shellx rồi tạo PR cho branch develop"

    @Composable
    private fun Screen(content: @Composable ColumnScope.() -> Unit) {
        Column(
            Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background),
            verticalArrangement = Arrangement.Bottom,
            content = content,
        )
    }

    /** The bar over [rig]'s mic, with the dictation [model] in the state the test put it in. */
    private fun renderBar(name: String, rig: VoiceRig, model: VoiceInputModel? = null, draft: ComposerDraft = ComposerDraft(),
                          attachmentsEnabled: Boolean = false, sending: Double? = null) {
        assertRenders(name) {
            CompositionLocalProvider(LocalVoice provides rig.env) {
                Screen {
                    ComposerBar(draft, {}, send = { _, _ -> }, attachmentsEnabled = attachmentsEnabled, sending = sending, voice = model)
                }
            }
        }
    }

    /** A 1170 × 2532 screenshot-like PNG: dark, 30 bars, the 12th red. */
    private fun photo(): OutgoingAttachment {
        val bitmap = Bitmap.createBitmap(1170, 2532, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(0xFF1F2129.toInt())
        val paint = Paint()
        for (i in 0 until 30) {
            paint.color = if (i == 11) 0xFFEF4444.toInt() else 0xFF4B5263.toInt()
            val top = 80f + i * 80f
            canvas.drawRect(60f, top, 60f + 300f + (i * 37 % 700), top + 40f, paint)
        }
        val png = ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
        return OutgoingAttachment(kind = AttachmentKind.IMAGE, name = "photo-1.png", data = png)
    }

    private fun log(name: String = "build-output.log") =
        OutgoingAttachment(kind = AttachmentKind.FILE, name = name, data = "error: missing import\n".toByteArray())

    /** Both attachments, the photo's thumbnail made first (renders do not wait for a background decode). */
    private fun both(): List<OutgoingAttachment> {
        val photo = photo()
        assertTrue(AttachmentThumbnails.image(photo) != null)
        return listOf(photo, log())
    }

    private fun VoiceInputModel.pressNow() = runBlocking { press() }

    @Test
    fun voiceIdle() {
        renderBar("voice-idle", VoiceRig.make())
    }

    @Test
    fun voiceListening() {
        val rig = VoiceRig.make()
        val model = rig.model()
        model.pressNow()
        rig.engine.say(spoken)
        renderBar("voice-listening", rig, model)
    }

    @Test
    fun voiceCancelArmed() {
        val rig = VoiceRig.make()
        val model = rig.model()
        model.pressNow()
        rig.engine.say(spoken)
        model.drag(-120.0, 0.0)
        renderBar("voice-cancel-armed", rig, model)
    }

    @Test
    fun voiceDenied() {
        val rig = VoiceRig.make(microphone = false)
        val model = rig.model()
        model.pressNow()
        renderBar("voice-denied", rig, model)
    }

    @Test
    fun voiceUnavailable() {
        val rig = VoiceRig.make(VoiceCapabilities.NONE)
        val model = rig.model()
        model.pressNow()
        // The bar would focus its field (the keyboard); a focused field's cursor blinks forever, which a render cannot
        // wait out. The keyboard path is ComposerBarTest.noRecognizerOpensTheKeyboard's.
        model.wantsKeyboard = false
        renderBar("voice-unavailable", rig, model)
    }

    @Test
    fun voiceLimit() {
        val rig = VoiceRig.make()
        val model = rig.model()
        model.pressNow()
        rig.engine.say("giữ route v1, đừng xoá. ".repeat(700))
        assertTrue(model.limitReached)
        renderBar("voice-limit", rig, model)
    }

    @Test
    fun composerAttachments() {
        renderBar("composer-attachments", VoiceRig.make(), draft = ComposerDraft(attachments = both()), attachmentsEnabled = true)
    }

    @Test
    fun composerSending() {
        renderBar(
            "composer-sending", VoiceRig.make(), draft = ComposerDraft(text = "Sửa lỗi này giúp mình", attachments = both()),
            attachmentsEnabled = true, sending = 0.4,
        )
    }

    @Test
    fun composerLoading() {
        val attachments = both()
        assertRenders("composer-loading") {
            Screen {
                AttachmentStrip(
                    attachments, onRemove = {}, locked = false, loading = listOf("a", "b"), cancelLoading = {},
                    spinner = { CircularProgressIndicator(progress = { 0.7f }) },
                )
            }
        }
    }

    @Test
    fun composerTooMany() {
        val six = (1..6).map { log("log-$it.txt") }
        renderBar("composer-too-many", VoiceRig.make(), draft = ComposerDraft(attachments = six), attachmentsEnabled = true)
    }
}
