package com.shellx.app.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.shellx.core.platform.Clock
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/** The home's re-sort timer (ledger 6.2-7): a tick every 30 s. */
object HomeTicks {
    val INTERVAL: Duration = 30.seconds

    fun every(interval: Duration = INTERVAL): Flow<Unit> = flow {
        while (true) {
            delay(interval)
            emit(Unit)
        }
    }
}

/**
 * The clock's wall time, read again on each of [ticks] while the screen is started (and once more each time it
 * starts), so "how long ago" texts and the home's order follow time without a recomposition every frame.
 */
@Composable
fun rememberNowMs(clock: Clock, ticks: Flow<Unit> = remember { HomeTicks.every() }): Long {
    var now by remember(clock) { mutableLongStateOf(clock.nowMs()) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(clock, ticks, lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            now = clock.nowMs()
            ticks.collect { now = clock.nowMs() }
        }
    }
    return now
}
