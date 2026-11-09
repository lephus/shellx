package com.shellx.core.pairing

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Counts the sheets open over the signed-in screens (the pending question, plan and full-text sheets), so a pairing
 * link opened meanwhile waits for them ([PairingInbox.take]): closing an answer sheet to make room would lose what was
 * typed.
 *
 * Each sheet calls [opened] when it appears and [closed] when it goes; the two may come in either order when one
 * sheet replaces another. Main-confined.
 */
class SheetPresence {
    private var count = 0
    private val _isAnyOpen = MutableStateFlow(false)

    /** True while any sheet is up. */
    val isAnyOpen: StateFlow<Boolean> = _isAnyOpen.asStateFlow()

    fun opened() {
        count += 1
        _isAnyOpen.value = true
    }

    /** Never goes below none (a disappear without its appear). */
    fun closed() {
        count = maxOf(0, count - 1)
        _isAnyOpen.value = count > 0
    }
}
