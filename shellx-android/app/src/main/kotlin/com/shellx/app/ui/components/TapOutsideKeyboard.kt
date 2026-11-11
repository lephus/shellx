package com.shellx.app.ui.components

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController

/**
 * The soft keyboard's holder that no focus manager clears: a View that took the focus and the keyboard itself (the
 * terminal surface). While it holds them it sets [hide], its own way of giving both up (what its hide key does), and
 * clears it after; [TapOutsideHidesKeyboard] calls it in place of the focus manager and the keyboard controller. Main
 * thread only.
 */
class KeyboardHolder {
    var hide: (() -> Unit)? = null
}

/** The frame's [KeyboardHolder] ([TapOutsideHidesKeyboard]); null outside one (tests of one page). */
val LocalKeyboardHolder = staticCompositionLocalOf<KeyboardHolder?> { null }

/**
 * A frame around a window's content, or a sheet's: while a text input holds the soft keyboard, a tap on anything that
 * takes no tap of its own (the empty background, a header, a row without a click, the room beside the terminal grid)
 * gives the focus up and hides the keyboard, as a tap outside does on the iPhone. A control takes its tap before it
 * reaches the frame (a button, a chip, a row with onClick, the text field itself, the terminal grid): it does what it
 * does and the keyboard stays. A drag (a scroll, a swipe, a pinch) is no tap. A text field gives the keyboard up
 * through the focus manager and the keyboard controller; a View that holds it gives it up its own way
 * ([LocalKeyboardHolder]). A sheet has a frame of its own: its window is not the screen's.
 */
@Composable
fun TapOutsideHidesKeyboard(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val holder = remember { KeyboardHolder() }
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    Box(
        modifier.pointerInput(focusManager, keyboard) {
            detectTapGestures(
                onTap = {
                    val hide = holder.hide
                    if (hide != null) {
                        hide()
                    } else {
                        focusManager.clearFocus()
                        // Compose keeps the keyboard up when a field loses the focus (a switch between fields would
                        // flicker it): it is hidden here.
                        keyboard?.hide()
                    }
                },
            )
        },
    ) {
        CompositionLocalProvider(LocalKeyboardHolder provides holder, content = content)
    }
}
