package com.shellx.app.testing

import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.unit.Dp
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import kotlin.math.roundToInt

/**
 * The soft keyboard as the system tells the window: [height] of room from the bottom (0.dp: it went down). Robolectric
 * shows no keyboard, so a screen that follows it (`imePadding`, `WindowInsets.ime`) gets its inset this way
 * (CompactHeightTest's helper, for any test with an activity's rule).
 */
fun AndroidComposeTestRule<*, out ComponentActivity>.imeInset(height: Dp) {
    runOnIdle {
        val root = activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0)
        val px = (height.value * root.resources.displayMetrics.density).roundToInt()
        val insets = WindowInsetsCompat.Builder()
            .setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, px))
            .setVisible(WindowInsetsCompat.Type.ime(), px > 0)
            .build()
        ViewCompat.dispatchApplyWindowInsets(root, insets)
    }
    waitForIdle()
}
