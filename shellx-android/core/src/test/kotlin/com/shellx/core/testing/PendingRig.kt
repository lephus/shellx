package com.shellx.core.testing

import com.shellx.core.demo.FakeMac
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachineLinkState
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.PendingKey
import com.shellx.core.pending.DecisionCenter
import com.shellx.core.pending.DecisionSending
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.ReplyOutcome
import kotlinx.coroutines.test.TestScope

/**
 * A DecisionSending that answers from a script, for what the real Link cannot do quickly (its request timeout is
 * 10 s). Each call takes the next answer, and the last one repeats. With a gate, every call waits on it first.
 * Thread-safe.
 */
class ScriptedSender(answers: List<Answer>) : DecisionSending {
    sealed interface Answer {
        data class Outcome(val outcome: ReplyOutcome) : Answer

        data class Failure(val error: Exception) : Answer
    }

    private val lock = Any()
    private val script = ArrayList(answers)
    private val recorded = ArrayList<Pair<PendingKey, LinkDecision>>()

    /** Every call, in order. */
    val calls: List<Pair<PendingKey, LinkDecision>> get() = synchronized(lock) { recorded.toList() }

    /** When set, every call waits here before answering. */
    @Volatile var gate: Gate? = null

    override suspend fun reply(key: PendingKey, decision: LinkDecision): ReplyOutcome {
        synchronized(lock) { recorded += key to decision }
        gate?.wait()
        val answer = synchronized(lock) { if (script.size > 1) script.removeAt(0) else script[0] }
        return when (answer) {
            is Answer.Outcome -> answer.outcome
            is Answer.Failure -> throw answer.error
        }
    }
}

/** A signed-in hub connected to fake Macs, with a DecisionCenter over it (PendingRig.swift). */
class PendingRig(
    val hub: MachineHub,
    val center: DecisionCenter,
    val latency: LatencyLog,
    /** The hub's reconnect waits. */
    val backoff: ManualSleeper,
    /** The center's waits (the 2 s "handled elsewhere" linger). */
    val linger: ManualSleeper,
    private val test: TestScope,
) {
    fun key(mac: FakeMac, requestId: String): PendingKey = PendingKey(mac.machine.machineId, requestId)

    /** Waits until every Mac is online with [count] pending items, all actionable. */
    suspend fun synced(count: Int): Boolean = test.eventually {
        hub.machines.all { it.state == MachineLinkState.Online } && hub.pendingItems.size == count &&
            hub.pendingItems.all { it.actionable }
    }

    /** The cards as the app shows them: the center syncs with the hub's list, then the screen reads visibleItems. */
    val shown: List<MachinePendingItem>
        get() {
            center.sync(hub.pendingItems)
            return center.visibleItems(hub.pendingItems)
        }

    /** The request ids the cards show right now. */
    val visibleIds: List<String> get() = shown.map { it.item.requestId }
}

/**
 * A started hubRig (backoff = its ManualSleeper) whose relay lists no grant (as PendingRig.swift's FakeRelayAccount),
 * and a DecisionCenter(hub, latency, backgroundScope, clock, linger.sleep).
 */
suspend fun TestScope.pendingRig(macs: List<FakeMac>): PendingRig {
    val rig = hubRig(macs, start = true)
    rig.relay.setGrants(emptyList())
    val linger = ManualSleeper()
    val center = DecisionCenter(rig.hub, rig.latency, backgroundScope, rig.clock, linger.sleep)
    return PendingRig(rig.hub, center, rig.latency, rig.backoff, linger, this)
}
