package com.shellx.app.ui.components

import android.animation.ValueAnimator
import android.graphics.Matrix
import androidx.compose.animation.core.withInfiniteAnimationFrameMillis
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.SweepGradientShader
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.shellx.link.core.AgentState
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * The thin multicolour border around an agent that waits for the user's answer (`WaitingBorder.swift`): a 2 dp ring
 * in the shape's own corner radius, drawn over the view. A sweep gradient (blue, violet, pink, amber, blue) turns once
 * every 3 seconds at a constant speed, at most 30 frames a second. With animations off (the system's "Remove
 * animations"), the ring stays still, in all its colours. It is decoration: TalkBack never sees it.
 */
object WaitingBorder {
    /** The gradient's colours, ARGB: the same at both ends, so the turn has no seam. Fixed in light and dark. */
    val PALETTE: List<Long> = listOf(0xFF60A5FA, 0xFFA78BFA, 0xFFF472B6, 0xFFFBBF24, 0xFF60A5FA)
    val LINE_WIDTH: Dp = 2.dp
    val TURN: Duration = 3.seconds
    const val FRAMES_PER_SECOND = 30

    internal val colors: List<Color> = PALETTE.map { Color(it) }

    /** Whether an agent in [state] waits for the user's answer. An agent whose Mac is not online cannot be answered. */
    fun isActive(state: AgentState, online: Boolean): Boolean = online && state == AgentState.NEEDS_INPUT

    /** The gradient's turn at [atMs], in degrees from 0 (inclusive) to 360: the same on every card, so two rings are
     *  never out of step. */
    fun angle(atMs: Long): Float {
        val turn = TURN.inWholeMilliseconds
        return Math.floorMod(atMs, turn).toFloat() / turn * 360f
    }

    /** Whether the ring turns: not when the system's animations are off. */
    fun animates(animatorsEnabled: Boolean): Boolean = animatorsEnabled
}

/**
 * Draws the waiting border over this view while [isActive], in a shape with [cornerRadius] (the view's own outline).
 * Inactive, it adds nothing. A frame changes only the shader's rotation: a redraw, never a recomposition.
 */
fun Modifier.waitingBorder(isActive: Boolean, cornerRadius: Dp): Modifier {
    if (!isActive) return this
    return composed {
        var angle by remember { mutableFloatStateOf(0f) }
        if (WaitingBorder.animates(ValueAnimator.areAnimatorsEnabled())) {
            LaunchedEffect(Unit) {
                val frameMs = 1000L / WaitingBorder.FRAMES_PER_SECOND
                while (true) {
                    withInfiniteAnimationFrameMillis {
                        angle = WaitingBorder.angle(System.currentTimeMillis() / frameMs * frameMs)
                    }
                }
            }
        }
        Modifier.drawWithCache {
            val width = WaitingBorder.LINE_WIDTH.toPx()
            val radius = (cornerRadius.toPx() - width / 2).coerceAtLeast(0f)
            val middle = Offset(size.width / 2, size.height / 2)
            val shader = SweepGradientShader(middle, WaitingBorder.colors)
            val brush = ShaderBrush(shader)
            val matrix = Matrix()
            val stroke = Stroke(width)
            onDrawWithContent {
                drawContent()
                matrix.setRotate(angle, middle.x, middle.y)
                shader.setLocalMatrix(matrix)
                drawRoundRect(
                    brush = brush,
                    topLeft = Offset(width / 2, width / 2),
                    size = Size(size.width - width, size.height - width),
                    cornerRadius = CornerRadius(radius),
                    style = stroke,
                )
            }
        }
    }
}
