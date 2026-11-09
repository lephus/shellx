package com.shellx.core.terminal

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** Review Focus 5 of plan 2C. */
class TerminalZoomTest {
    @Test fun aNewGridWidthGoesBackToFit() {
        var zoom = TerminalZoom().gridChanged(100).pinch(1f, fit = 0.5f)
        zoom = zoom.gridChanged(100)
        assertEquals(1f, zoom.scale(0.5f), "frames of the same width keep the pinch")
        zoom = zoom.gridChanged(50)
        assertNull(zoom.zoom); assertEquals(1f, zoom.scale(1f))
    }

    @Test fun pinchStaysBetweenFitAndTwo() {
        var zoom = TerminalZoom().pinch(0.1f, fit = 0.5f); assertEquals(0.5f, zoom.scale(0.5f))
        zoom = zoom.pinch(9f, fit = 0.5f); assertEquals(2f, zoom.scale(0.5f))
    }

    @Test fun aZoomBelowANewFitFollowsTheFit() {
        val zoom = TerminalZoom().pinch(0.6f, fit = 0.5f)
        assertEquals(0.8f, zoom.scale(0.8f), "a wider pane after rotation: never smaller than fit")
    }
}
