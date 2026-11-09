package com.shellx.core.diagnostics

import com.shellx.core.platform.CoreLog
import kotlin.math.ceil
import kotlin.time.Duration

/** The latencies the app measures against its targets (S3 §7.4). [wire] is the name in log lines. */
enum class LatencyMetric(val wire: String) {
    /** Tap on a decision to the Mac's `reply_result`. */
    REPLY_ROUND_TRIP("replyRoundTrip"),

    /** A request created on the Mac to its arrival on the phone. */
    PENDING_ARRIVAL("pendingArrival"),

    /** A session's state change on the Mac to its arrival on the phone. */
    SESSION_CHANGE_ARRIVAL("sessionChangeArrival"),

    /** App launch to the home screen with content. */
    LAUNCH_TO_HOME("launchToHome"),

    /** App launch to the default Mac's first workspace list. */
    LAUNCH_TO_WORKSPACE_LIST("launchToWorkspaceList"),

    /** Start of speech to the first recognised word. */
    FIRST_WORD("firstWord"),

    /** A terminal shown (the swipe or tap) to its first screen drawn. */
    TERMINAL_FIRST_SCREEN("terminalFirstScreen"),

    /** A key typed into a terminal to the next frame that changes its screen. */
    TERMINAL_KEY_ECHO("terminalKeyEcho"),

    /** Assembling and applying one terminal frame on the phone. */
    TERMINAL_FRAME_APPLY("terminalFrameApply"),
}

data class LatencySummary(val count: Int, val p50: Duration, val p95: Duration)

/**
 * Keeps the last [WINDOW] samples of each metric and logs each one as `"<wire> <ms> ms"` through [sink]: the metric
 * name and milliseconds only, never content or identifiers. Thread-safe.
 */
class LatencyLog(private val sink: (String) -> Unit = CoreLog::log) {
    private val lock = Any()
    private val samples = HashMap<LatencyMetric, ArrayDeque<Duration>>()

    /** Records one sample. A negative duration (the two clocks disagree) counts as zero. */
    fun record(metric: LatencyMetric, duration: Duration) {
        val value = if (duration < Duration.ZERO) Duration.ZERO else duration
        synchronized(lock) {
            val list = samples.getOrPut(metric) { ArrayDeque() }
            list.addLast(value)
            while (list.size > WINDOW) list.removeFirst()
        }
        sink("${metric.wire} ${value.inWholeMilliseconds} ms")
    }

    /** Count, median and 95th percentile (nearest rank) of the last [WINDOW] samples; null when none. */
    fun summary(metric: LatencyMetric): LatencySummary? {
        val sorted = synchronized(lock) { samples[metric]?.toList() ?: emptyList() }.sorted()
        if (sorted.isEmpty()) return null
        return LatencySummary(sorted.size, percentile(0.50, sorted), percentile(0.95, sorted))
    }

    companion object {
        const val WINDOW = 200

        private fun percentile(fraction: Double, sorted: List<Duration>): Duration {
            val rank = ceil(fraction * sorted.size).toInt()
            return sorted[rank.coerceIn(1, sorted.size) - 1]
        }
    }
}
