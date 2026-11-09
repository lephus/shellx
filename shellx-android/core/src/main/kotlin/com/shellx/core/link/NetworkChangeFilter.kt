package com.shellx.core.link

import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch

/**
 * Turns the stream of network paths into "the path changed" calls: the first path is the baseline, an equal path is
 * no change, and changes less than [SETTLE] apart are reported once, after the last of them.
 *
 * Main-confined: [receive] is called only from the dispatcher of [scope], which runs the settle waits.
 */
class NetworkChangeFilter(
    private val scope: CoroutineScope,
    private val sleep: suspend (Duration) -> Unit = { delay(it) },
    private val onChange: () -> Unit,
) {
    private var last: NetworkPath? = null
    private var pending: Job? = null

    fun receive(path: NetworkPath) {
        if (path == last) return
        val first = last == null
        last = path
        if (first) return
        pending?.cancel()
        pending = scope.launch {
            sleep(SETTLE)
            ensureActive()
            onChange()
        }
    }

    companion object {
        val SETTLE: Duration = 300.milliseconds
    }
}
