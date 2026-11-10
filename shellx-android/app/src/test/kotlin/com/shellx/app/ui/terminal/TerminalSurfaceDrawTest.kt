package com.shellx.app.ui.terminal

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.demo.DemoTerminalFixture
import com.shellx.core.terminal.TerminalViewModel
import com.shellx.link.core.TerminalCursor
import com.shellx.link.core.TerminalRun
import com.shellx.link.core.TerminalScreen
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric

/**
 * What a frame costs (review D1 M8): a frame that shows the same rows lays out nothing again, also while the view is
 * scrolled far above the cursor, whose row is out of sight.
 */
@RunWith(AndroidJUnit4::class)
class TerminalSurfaceDrawTest {
    private val activity = Robolectric.buildActivity(Activity::class.java).setup().get()

    /** A shell with [history] rows above a 40 × 10 screen, its cursor on the screen's last row. */
    private fun surface(history: Int): TerminalSurfaceView {
        val fixture = DemoTerminalFixture(
            cols = 40, rows = 10,
            history = (1..history).map { listOf(TerminalRun(text = "line $it")) },
            screen = (1..10).map { listOf(TerminalRun(text = "screen $it")) },
            cursor = TerminalCursor(0, 9),
        )
        val model = TerminalViewModel.fixed("t-zsh", TerminalScreen().apply { apply(fixture.snapshot) })
        val surface = TerminalSurfaceView(activity, model, "t-zsh", TerminalFont(activity), RecordingIme())
        activity.setContentView(surface)
        surface.measure(View.MeasureSpec.makeMeasureSpec(400, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(300, View.MeasureSpec.EXACTLY))
        surface.layout(0, 0, 400, 300)
        surface.render(model.state.value)
        return surface
    }

    private fun TerminalSurfaceView.drawFrames(count: Int) {
        val canvas = Canvas(Bitmap.createBitmap(400, 300, Bitmap.Config.ARGB_8888))
        repeat(count) { draw(canvas) }
    }

    @Test
    fun framesOfTheSameRowsLayOutNothingAgain() {
        val surface = surface(history = 200)
        surface.drawFrames(1)
        val built = surface.rowLayoutsBuilt
        surface.drawFrames(5)
        assertEquals(built, surface.rowLayoutsBuilt)
    }

    @Test
    fun scrolledFarAboveTheCursorAFrameLaysOutNothingAgain() {
        val surface = surface(history = 200)
        surface.dragVertically(1_000_000f)
        assertEquals("scrolled to the top", 0f, surface.viewport.scrollY, 0.5f)
        surface.drawFrames(1)
        val built = surface.rowLayoutsBuilt
        assertTrue(built > 0)
        surface.drawFrames(5)
        assertEquals("the cursor's row, out of sight, is not laid out each frame", built, surface.rowLayoutsBuilt)
    }
}
