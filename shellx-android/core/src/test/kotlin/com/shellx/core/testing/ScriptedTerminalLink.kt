package com.shellx.core.testing

import com.shellx.core.diagnostics.LatencyMetric
import com.shellx.core.terminal.TerminalHubEvent
import com.shellx.core.terminal.TerminalLink
import com.shellx.core.terminal.TerminalOpenResult
import com.shellx.link.core.TerminalInputUnit
import com.shellx.link.core.TerminalViewOpenOutcome
import kotlin.time.Duration
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.FlowCollector

/**
 * A [TerminalLink] the test drives (ScriptedTerminalLink in TerminalTestSupport.swift): it records every call, answers
 * each open from [openAnswers] (then OK), after [openGate] when one is set, and hands [emit] to every collection of
 * [terminalEvents] that is running, whatever Mac it names (the model filters by its own). Main-confined.
 */
class ScriptedTerminalLink : TerminalLink {
    sealed interface Call {
        data class Open(val id: String, val cols: Int, val rows: Int) : Call
        data class Close(val id: String) : Call
        data class Input(val id: String, val units: List<TerminalInputUnit>) : Call
        data class Resize(val id: String, val cols: Int, val rows: Int) : Call
        data class Resync(val id: String) : Call
    }

    /** In order. */
    val calls: MutableList<Call> = mutableListOf()
    var online = true
    var supportsViews = true
    val openAnswers: MutableList<TerminalOpenResult> = mutableListOf()
    var openGate: Gate? = null

    /** Every recordLatency call, in order. */
    val samples: MutableList<Pair<LatencyMetric, Duration>> = mutableListOf()
    private val subscribers = mutableListOf<Channel<TerminalHubEvent>>()

    val latencies: List<LatencyMetric> get() = samples.map { it.first }

    /** How many collections of [terminalEvents] are running: 1 once a model's run() has started. */
    val subscriberCount: Int get() = subscribers.size

    /** The terminal ids of the open calls. */
    val opens: List<String> get() = calls.filterIsInstance<Call.Open>().map { it.id }

    /** The units of the input calls. */
    val inputs: List<List<TerminalInputUnit>> get() = calls.filterIsInstance<Call.Input>().map { it.units }

    fun emit(event: TerminalHubEvent) {
        for (subscriber in subscribers.toList()) subscriber.trySend(event)
    }

    override fun terminalEvents(machineId: String): Flow<TerminalHubEvent> = object : Flow<TerminalHubEvent> {
        override suspend fun collect(collector: FlowCollector<TerminalHubEvent>) {
            val channel = Channel<TerminalHubEvent>(Channel.UNLIMITED)
            subscribers += channel
            try {
                for (event in channel) collector.emit(event)
            } finally {
                subscribers -= channel
            }
        }
    }

    override fun isOnline(machineId: String): Boolean = online

    override fun supportsTerminalView(machineId: String): Boolean = supportsViews

    override suspend fun openTerminalView(machineId: String, terminalId: String, cols: Int, rows: Int): TerminalOpenResult {
        calls += Call.Open(terminalId, cols, rows)
        openGate?.wait()
        return openAnswers.removeFirstOrNull() ?: TerminalOpenResult.Outcome(TerminalViewOpenOutcome.OK)
    }

    override suspend fun closeTerminalView(machineId: String, terminalId: String) {
        calls += Call.Close(terminalId)
    }

    override suspend fun sendTerminalInput(machineId: String, terminalId: String, units: List<TerminalInputUnit>) {
        calls += Call.Input(terminalId, units)
    }

    override suspend fun resizeTerminalView(machineId: String, terminalId: String, cols: Int, rows: Int) {
        calls += Call.Resize(terminalId, cols, rows)
    }

    override suspend fun resyncTerminalView(machineId: String, terminalId: String) {
        calls += Call.Resync(terminalId)
    }

    override fun recordLatency(metric: LatencyMetric, duration: Duration) {
        samples += metric to duration
    }
}
