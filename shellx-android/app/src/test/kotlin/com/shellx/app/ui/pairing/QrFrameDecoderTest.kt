package com.shellx.app.ui.pairing

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import com.shellx.link.core.PairingOffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

/** A camera frame's luminance plane to the QR code's text. */
@RunWith(AndroidJUnit4::class)
class QrFrameDecoderTest {
    private val size = 400

    /** [text] as a QR code, one byte per pixel (0 black, 255 white), each row [rowStride] bytes, padded with 127. */
    private fun frame(text: String, rowStride: Int = size): ByteArray {
        val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size)
        val data = ByteArray(rowStride * size) { 127 }
        for (y in 0 until size) {
            for (x in 0 until size) data[y * rowStride + x] = if (matrix[x, y]) 0 else -1
        }
        return data
    }

    private val shellXCode = PairingOffer.make(
        "6f1c2b7e-0d4a-4c1e-9a53-3b8e5d2f7a10", "slot-1", ByteArray(32) { 1 }, "MacBook của Phú",
    ).uri

    @Test
    fun aShellXCodeDecodes() {
        assertEquals(shellXCode, QrFrameDecoder.decode(frame(shellXCode), size, size, size))
    }

    @Test
    fun paddedRowsDecode() {
        assertEquals(shellXCode, QrFrameDecoder.decode(frame(shellXCode, rowStride = 448), 448, size, size))
    }

    @Test
    fun aBlankFrameHasNoCode() {
        assertNull(QrFrameDecoder.decode(ByteArray(size * size) { -1 }, size, size, size))
    }

    @Test
    fun anyQrIsReported() {
        assertEquals("https://example.com", QrFrameDecoder.decode(frame("https://example.com"), size, size, size))
    }
}
