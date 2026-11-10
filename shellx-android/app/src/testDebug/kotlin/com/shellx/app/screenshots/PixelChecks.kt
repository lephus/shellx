package com.shellx.app.screenshots

import kotlin.math.abs

private fun channels(argb: Int): IntArray = intArrayOf((argb shr 16) and 0xFF, (argb shr 8) and 0xFF, argb and 0xFF)

/** How coloured a pixel is: max(r, g, b) − min(r, g, b). Greys and white are near 0. */
fun chroma(argb: Int): Int {
    val c = channels(argb)
    return c.max() - c.min()
}

/** The iPhone tests' colour distance: |Δr| + |Δg| + |Δb|. */
fun colourDistance(a: Int, b: Int): Int {
    val x = channels(a)
    val y = channels(b)
    return abs(x[0] - y[0]) + abs(x[1] - y[1]) + abs(x[2] - y[2])
}
