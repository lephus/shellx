package com.shellx.app.ui.composer

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.GraphicsMode

/**
 * Review A M-3: a converted photo is decoded at most 4096 px on its long side, its shape kept, so a 50–108 MP HEIC never
 * needs hundreds of MB of memory. Robolectric's decoder has no HEIF, so a PNG goes through the same `ImageDecoder` path.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class HeifToJpegTest {
    private fun encoded(width: Int, height: Int): ByteArray {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.rgb(30, 120, 200)) }
        return ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            bitmap.recycle()
            out.toByteArray()
        }
    }

    /** The JPEG's width and height, and that it is a JPEG. */
    private fun jpegSize(data: ByteArray): Pair<Int, Int> {
        assertEquals(listOf(0xFF, 0xD8), data.take(2).map { it.toInt() and 0xFF })
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, options)
        return options.outWidth to options.outHeight
    }

    private fun converted(width: Int, height: Int) = jpegSize(AttachmentPreparer.systemHeifToJpeg(encoded(width, height))!!)

    @Test
    fun aLargePhotoComesDownToTheLongestSideAllowed() {
        assertEquals(4096 to 27, converted(6000, 40))
        assertEquals(27 to 4096, converted(40, 6000))
    }

    @Test
    fun aThinPhotoKeepsAtLeastOnePixel() {
        assertEquals(4096 to 1, converted(20_000, 2))
    }

    @Test
    fun aPhotoWithinTheLimitKeepsItsSize() {
        assertEquals(1200 to 900, converted(1200, 900))
    }
}
