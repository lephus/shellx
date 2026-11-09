package com.shellx.core.composer

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * How far the attachments of the message being sent got, for the screen that sends it: the bytes uploaded over the
 * bytes to upload, null while no upload runs (UploadProgress.swift). Values may come from any thread (3B calls progress
 * on Dispatchers.Default); each one hops to [scope] (scope.launch) before it is applied, only while its send is the
 * latest one, and only upward.
 *
 * Main-confined. [onChange] gets every new [fraction] (the agent screen copies it into its own state).
 */
internal class UploadProgress(private val scope: CoroutineScope, private val onChange: (Double?) -> Unit = {}) {
    private val _fraction = MutableStateFlow<Double?>(null)
    val fraction: StateFlow<Double?> = _fraction.asStateFlow()

    private var run = 0

    /** Runs [send] with a progress callback to hand to MachineHub.chatSend: [fraction] is 0 from now, follows the
     *  callback, and is null again when [send] returns or throws. */
    suspend fun <T> track(send: suspend (progress: (Double) -> Unit) -> T): T {
        run += 1
        val current = run
        set(0.0)
        try {
            return send { value -> scope.launch { advance(value, current) } }
        } finally {
            if (run == current) set(null)
        }
    }

    private fun set(value: Double?) {
        _fraction.value = value
        onChange(value)
    }

    private fun advance(value: Double, send: Int) {
        // A late value of a send that is over (null) or replaced does nothing.
        val fraction = _fraction.value
        if (send != run || fraction == null || value <= fraction) return
        set(minOf(value, 1.0))
    }
}
