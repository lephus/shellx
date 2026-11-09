package com.shellx.app.ui.pairing

import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.ReaderException
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.multi.qrcode.QRCodeMultiReader
import com.google.zxing.qrcode.QRCodeReader

/** Reads a QR code from a camera frame's luminance (Y) plane. Any QR text: [com.shellx.core.pairing.PairingScanFilter]
 *  sorts them. */
object QrFrameDecoder {
    private val hints = mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE))

    /**
     * The text of the QR code in the frame, or null. [rowStride] is the bytes per row (at least [width]).
     *
     * The single-code reader takes the three likeliest finder patterns. In about 2 of 100 pairing codes the data holds a
     * run that looks like one, and it picks the wrong three on every frame; the multi-code reader, which tries each
     * likely three, reads those. It runs only when the first finds nothing.
     */
    fun decode(luminance: ByteArray, rowStride: Int, width: Int, height: Int): String? {
        val source = PlanarYUVLuminanceSource(luminance, rowStride, height, 0, 0, width, height, false)
        val bitmap = BinaryBitmap(HybridBinarizer(source))
        return try {
            QRCodeReader().decode(bitmap, hints).text
        } catch (_: ReaderException) {
            try {
                QRCodeMultiReader().decodeMultiple(bitmap, hints).firstOrNull()?.text
            } catch (_: ReaderException) {
                null
            }
        }
    }
}
