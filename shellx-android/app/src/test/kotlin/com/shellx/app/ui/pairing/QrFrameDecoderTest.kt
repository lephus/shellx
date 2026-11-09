package com.shellx.app.ui.pairing

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import com.shellx.link.core.PairingOffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

/** A camera frame's luminance plane to the QR code's text. */
@RunWith(AndroidJUnit4::class)
class QrFrameDecoderTest {
    private val size = 400

    /** [text] as a QR code at the Mac's error correction (M), one byte per pixel (0 black, 255 white), each row
     *  [rowStride] bytes, padded with 127. */
    private fun frame(text: String, rowStride: Int = size): ByteArray {
        val hints = mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M)
        val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size, hints)
        val data = ByteArray(rowStride * size) { 127 }
        for (y in 0 until size) {
            for (x in 0 until size) data[y * rowStride + x] = if (matrix[x, y]) 0 else -1
        }
        return data
    }

    /** [rows] (`#` dark) inside a quiet zone of [quiet] modules, scaled to [size] px as a camera would see it. */
    private fun frame(rows: List<String>, quiet: Int): ByteArray {
        val side = rows.size
        val modules = side + 2 * quiet
        val data = ByteArray(size * size)
        for (y in 0 until size) {
            for (x in 0 until size) {
                val mx = x * modules / size - quiet
                val my = y * modules / size - quiet
                data[y * size + x] = if (mx in 0 until side && my in 0 until side && rows[my][mx] == '#') 0 else -1
            }
        }
        return data
    }

    // A fixed code: the test reads the same QR on every run.
    private val shellXCode = PairingOffer(
        "6f1c2b7e-0d4a-4c1e-9a53-3b8e5d2f7a10", "slot-1", ByteArray(32) { 1 }, ByteArray(16) { (it * 17).toByte() }, "MacBook của Phú",
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

    /**
     * A pairing code as the Mac draws it (Core Image, error correction M, its 1-module margin widened to 4), whose data
     * modules hold a run that looks like a finder pattern. About 2 in 100 random pairing codes are like this; the
     * single-code detector picks the wrong three corners for them on every frame size.
     */
    @Test
    fun aMacCodeWithAFinderLookalikeDecodes() {
        val uri = "shellx-link://pair?v=1&m=4999c39e-005b-4e55-bd5e-452f678ce2dd&s=slot-1" +
            "&k=qWPv7PiIhDlXrDdOpsMcCFt9T3Z0RLxkBWIHbxB1Ot0&c=fPUTBM_S9a9RSwcNZFkXDQ&n=Studio"
        assertEquals(uri, QrFrameDecoder.decode(frame(MAC_CODE_ROWS, quiet = 3), size, size, size))
    }

    private companion object {
        /** Core Image's `CIQRCodeGenerator` output (one pixel per module, with its 1-module margin) for the uri above. */
        val MAC_CODE_ROWS = listOf(
            "...................................................",
            ".#######...#######..##..###.####.#..###..#.#######.",
            ".#.....#..#....#..##..##...#...#.#.....###.#.....#.",
            ".#.###.#.###....#...#.#.#..#.#.##.#..#..##.#.###.#.",
            ".#.###.#.#.#.##.#.###...###...###...###.#..#.###.#.",
            ".#.###.#.####.##..##..#######..##...#.#....#.###.#.",
            ".#.....#.###.#.....##.##...#.#...###.#.#...#.....#.",
            ".#######.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#######.",
            ".........#####..###....#...#####.#..#.#..#.........",
            ".#.#####...#..####.#..######...##.##.##.#..#####...",
            ".#.###...##.#.#..##.#.##.#...###.##.......##.#..#..",
            "..#..######....##..##...#####......###.######.##.#.",
            "..##..#..#.#.#....##.....###.#####.#....#....##.##.",
            ".###.###..###.#...##..#.##..#..#....##.#.#.##..##..",
            "...#..#.###...#.#..###..#.#....##....##....##.#....",
            ".#.....##..###....##.#..##.####.####.#..#....##.##.",
            ".#.##...#.#.#...#.#.##..#..######.#.#.#####..##.#..",
            ".###..#####.####.#.#####.#..#...#.##.##.####..##.#.",
            ".#.###...#..##..#.......###...##.#..###...###.###..",
            "...#...##.#..#######.#..#..##...##...##.....#.#..#.",
            "...##.#...#....#..##..#.#.###.#######..#....##...#.",
            ".#.###.#.###..####.##.##.#.#........######.##.####.",
            "..###.#....###.######...#...####.....#....##....#..",
            ".##..#####..#...##..#..######...#..#.###.######.##.",
            "....##...###....####..##...#.#####....####...#...#.",
            ".##..#.#.#..#.####.#####.#.#...#...####.##.#.###.#.",
            "...#.#...#.###...#.....#...#...##.#......#...#.....",
            "...#.######.#.###..#...#####.#..#..#.#########.#.#.",
            ".#.#.#.....##..#.#.#.....###.#.####.#.#.##.###.....",
            "...#..###...#####.....#.#..##.#....###..#..#.#...#.",
            "...#.#...#.#.##.#.....#.###.#.##.#..#.#.##.##...#..",
            ".##....#..#....#....##.##.#...###.#.#..######.####.",
            ".###....##.##.###..####..#.#......#...########.....",
            ".#..##.#..#...#.......######..#.#..######.#...####.",
            "...####...#.#.....#.#.#.#####.####..###.#####...#..",
            "...#.###.#.#.###.##....#..#...##...#..#..####...##.",
            "....###.#.#.########.#...###..#.###.#..#.....#..#..",
            ".####.##.###.....#######...#..###.####.##..######..",
            "....#....##....#..###.##.####..#.##.#...##......##.",
            "..#...####...####...#....##.#.#.#..##..##.###...##.",
            "..###....###......#.##.###...###.####.#..#..#.#.#..",
            ".###...####..#.##...#########...#.#..#..######.###.",
            ".........#...####......#...#.#####..##..##...##....",
            ".#######..##..##..#....#.#.##.#...########.#.##.##.",
            ".#.....#.#..#...#..#..##...#.#..###...#..#...#..##.",
            ".#.###.#.#.#...###...########...#..#.#...#########.",
            ".#.###.#.#..##..#..##..##.##...###..#.#...##.##.##.",
            ".#.###.#.##.#.##.#..#.#..##..##.###.#......##..#...",
            ".#.....#..#.#....##..####.#.#....#..#.....##..#..#.",
            ".#######.#######.##.##...##....##..#.###....##.###.",
            "...................................................",
        )
    }
}
