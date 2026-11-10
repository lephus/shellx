package com.shellx.app.ui.composer

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.core.composer.AttachmentReadException
import com.shellx.core.home.ComposerValidation
import com.shellx.core.text.graphemeCount
import com.shellx.core.voice.VoiceInputModel
import com.shellx.core.voice.VoicePermission
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ComposerTextsTest {
    private val res = ApplicationProvider.getApplicationContext<Context>().resources

    @Test
    fun byteCountsReadInTheAppsLanguage() {
        assertEquals("16,384", ComposerValidation.byteCount(16_384, Locale.ENGLISH))
        assertEquals("16 384", ComposerValidation.byteCount(16_384, Locale("vi")))
    }

    @Test
    fun attachmentProblemsHaveTheirWords() {
        assertEquals(res.getString(R.string.composer_attach_too_many), ComposerBar.problem(ComposerValidation.TooManyAttachments, res))
        assertEquals(
            res.getString(R.string.composer_attach_too_large, "video.mov"),
            ComposerBar.problem(ComposerValidation.AttachmentTooLarge("video.mov"), res),
        )
        assertEquals(
            AttachmentPreparer.message(AttachmentReadException.TooLarge("video.mov"), res),
            ComposerBar.problem(ComposerValidation.AttachmentTooLarge("video.mov"), res),
        )
        assertNull(ComposerBar.problem(ComposerValidation.Ok("x"), res))
    }

    /** Port of testLongDictationShowsItsNewestWords. */
    @Test
    fun aLongDictationShowsItsNewestWords() {
        val spoken = "Chạy test cho shellx rồi tạo PR cho branch develop"
        assertEquals(spoken, VoiceStatusView.newest(spoken))
        val shown = VoiceStatusView.newest("giữ route v1, đừng xoá. ".repeat(40) + "rồi push")
        assertTrue(shown.startsWith("…"))
        assertTrue(shown.endsWith("rồi push"))
        assertTrue(shown.graphemeCount() <= VoiceStatusView.SHOWN_CHARACTERS + 1)
        assertFalse(shown.drop(1).startsWith(" "))
    }

    @Test
    fun eachMicStateHasItsSymbol() {
        val symbols = listOf(
            VoiceInputModel.Phase.Idle, VoiceInputModel.Phase.Listening(""), VoiceInputModel.Phase.CancelArmed(""),
            VoiceInputModel.Phase.Denied(VoicePermission.MICROPHONE),
        ).map(MicButton::symbol)
        assertEquals(4, symbols.toSet().size)
    }
}
