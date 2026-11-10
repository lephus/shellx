package com.shellx.app.platform

import android.content.Intent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** A tap on a "needs you" alert, held until the signed-in screens take it (iPhone `PushTapInbox`; the tap may start
 *  the app). Main thread. */
class PushTapInbox {
    private val _hasTap = MutableStateFlow(false)
    val hasTap: StateFlow<Boolean> = _hasTap.asStateFlow()

    fun receive() {
        _hasTap.value = true
    }

    /** True once per tap. */
    fun take(): Boolean {
        val had = _hasTap.value
        _hasTap.value = false
        return had
    }

    companion object {
        /** The alert's tap ([PushNotifier.ACTION_OPEN_PENDING]); any other intent, or none, is not one. */
        fun isOpenPending(intent: Intent?): Boolean = intent?.action == PushNotifier.ACTION_OPEN_PENDING
    }
}
