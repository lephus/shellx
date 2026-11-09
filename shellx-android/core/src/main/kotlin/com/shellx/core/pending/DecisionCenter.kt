package com.shellx.core.pending

import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.diagnostics.LatencyMetric
import com.shellx.core.link.LinkCallException
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.link.PendingKey
import com.shellx.core.platform.Clock
import com.shellx.core.platform.rethrowIfCancelled
import com.shellx.core.platform.runDetached
import com.shellx.core.text.utf8Size
import com.shellx.link.core.LinkClientException
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.ReplyOutcome
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** What the cards show about the user's decisions ([DecisionCenter.state]). */
data class DecisionCenterState(
    /** Each item's decision, by item. No entry: nothing sent (or the item is gone). */
    val status: Map<PendingKey, DecisionStatus> = emptyMap(),
    /** Items whose "handled elsewhere" was shown long enough. */
    val dismissed: Set<PendingKey> = emptySet(),
    /** Items handled elsewhere, as last shown, kept on screen through the linger even when they left the set. */
    val lingering: Map<PendingKey, MachinePendingItem> = emptyMap(),
)

/**
 * Sends the user's decisions on pending items and keeps, per item, what its card says about it (DecisionCenter.swift).
 *
 * Rules (A1, spec section 7.5):
 * - A tap on an item that is Sending (or already Done or handled elsewhere) does nothing.
 * - `delivered`: Done, and the card goes at once, without waiting for the Mac's `agent.changed`. The time from the tap
 *   to that answer is recorded as REPLY_ROUND_TRIP (A2).
 * - `already_handled`: HandledElsewhere; the card says so, then goes after [HANDLED_ELSEWHERE_LINGER], also when the
 *   item left the pending set meanwhile.
 * - `unknown`, an outcome this app does not know, or an error the Mac answered: Failed(REJECTED).
 * - No answer in time: sent once more (safe: replies are idempotent); still none, Failed(NO_ANSWER).
 * - No live, synced session (LinkCallException.Offline, LinkClientException.SessionClosed, or a card shown not
 *   actionable): Failed(OFFLINE). Nothing is queued.
 * - Feedback over [MAX_FEEDBACK_BYTES] is not sent at all (the sheet counts bytes and stops it first).
 * - An item that left the pending set loses its status.
 *
 * Main-confined. [send] and [retry] run through runDetached in [scope], so a card whose screen went away still gets its
 * final status; the linger timers also run there.
 */
class DecisionCenter(
    private val sender: DecisionSending,
    private val latency: LatencyLog,
    private val scope: CoroutineScope,
    private val clock: Clock,
    private val sleep: suspend (Duration) -> Unit = { delay(it) },
) {
    companion object {
        /** The most UTF-8 bytes of a plan's feedback. */
        const val MAX_FEEDBACK_BYTES = 4096

        /** How long a card says "handled elsewhere" before it goes. */
        val HANDLED_ELSEWHERE_LINGER: Duration = 2.seconds

        private fun failure(error: Throwable): DecisionFailure = when (error) {
            // Nothing was sent. A Mac to be paired again has dropped its items, so its cards are gone before this
            // line could show.
            is LinkCallException.Offline, is LinkCallException.NeedsPairing, is LinkClientException.SessionClosed ->
                DecisionFailure.OFFLINE
            is LinkClientException.Remote, is LinkCallException.UnknownMachine -> DecisionFailure.REJECTED
            // Timed out twice, or failed in a way that says nothing about the item: trying again is safe, since a
            // reply is idempotent.
            else -> DecisionFailure.NO_ANSWER
        }
    }

    private val _state = MutableStateFlow(DecisionCenterState())
    val state: StateFlow<DecisionCenterState> = _state.asStateFlow()

    val status: Map<PendingKey, DecisionStatus> get() = state.value.status

    /** The hub's items at the last [sync]: what the cards show (read by [send]). */
    private var shown: Map<PendingKey, MachinePendingItem> = emptyMap()

    /** The last decision sent per item, for [retry]. */
    private val lastDecision = HashMap<PendingKey, LinkDecision>()

    /** Items whose reply is still out: their status survives the item leaving the set. */
    private val inFlight = HashSet<PendingKey>()

    /** Sends [decision] for the item and updates its status as the rules say. Returns when the status is final for
     *  this tap. */
    suspend fun send(decision: LinkDecision, key: PendingKey) {
        send(decision, key) {}
    }

    /**
     * [send], then [ended] with the item's status once the work ends, from inside the detached work: it runs even after
     * the caller was cancelled (the pending sheet's own result, review 3a m-1).
     */
    internal suspend fun send(decision: LinkDecision, key: PendingKey, ended: (DecisionStatus?) -> Unit) {
        scope.runDetached {
            try {
                sendNow(decision, key)
            } finally {
                ended(status[key])
            }
        }
    }

    /**
     * Takes the hub's whole pending list (never a subset: what is missing counts as resolved):
     * - forgets the status of every item that left it (unless its reply is still out, or its "handled elsewhere" is
     *   still showing);
     * - clears Failed(OFFLINE) of an item that can act again (it was not actionable, or not there, at the last sync).
     */
    fun sync(pendingItems: List<MachinePendingItem>) {
        val before = shown
        val now = LinkedHashMap<PendingKey, MachinePendingItem>()
        for (item in pendingItems) now.putIfAbsent(item.id, item)
        shown = now
        forgetGone(now)
        for ((key, item) in now) {
            if (item.actionable && before[key]?.actionable != true &&
                status[key] == DecisionStatus.Failed(DecisionFailure.OFFLINE)
            ) {
                setStatus(key, null)
            }
        }
    }

    /** "Try again" on a failed item: sends its last decision once more. */
    suspend fun retry(key: PendingKey) {
        scope.runDetached {
            if (status[key] !is DecisionStatus.Failed) return@runDetached
            val decision = lastDecision[key] ?: return@runDetached
            sendNow(decision, key)
        }
    }

    /**
     * The items to show as cards, out of [items] (the hub's pendingItems, or any part of it):
     * - without the Done ones (the Mac's `agent.changed` may still be on its way);
     * - with the ones handled elsewhere until their linger is over, kept even when they left the set meanwhile (then
     *   not actionable).
     *
     * Only reads, so a screen may call it while drawing.
     */
    fun visibleItems(items: List<MachinePendingItem>): List<MachinePendingItem> {
        val s = state.value
        val present = items.map { it.id }.toSet()
        val visible = items.filter { s.status[it.id] != DecisionStatus.Done && it.id !in s.dismissed }
        val kept = s.lingering.filter { it.key !in present && it.key !in s.dismissed }.values
        if (kept.isEmpty()) return visible
        // The hub's order: oldest first.
        return (visible + kept).sortedWith(
            compareBy<MachinePendingItem>({ it.item.createdAtMs }, { it.machineId }, { it.item.requestId }),
        )
    }

    // Private

    private suspend fun sendNow(decision: LinkDecision, key: PendingKey) {
        when (status[key]) {
            DecisionStatus.Sending, DecisionStatus.Done, DecisionStatus.HandledElsewhere -> return
            is DecisionStatus.Failed, null -> Unit
        }
        if (decision is LinkDecision.ExitPlan) {
            val feedback = decision.feedback
            if (feedback != null && feedback.utf8Size > MAX_FEEDBACK_BYTES) return
        }
        val item = shown[key]
        lastDecision[key] = decision
        // The card showed no live data: the tap raced the redraw that turned its buttons off.
        if (item?.actionable == false) {
            setStatus(key, DecisionStatus.Failed(DecisionFailure.OFFLINE))
            return
        }
        setStatus(key, DecisionStatus.Sending)
        inFlight += key
        try {
            val start = clock.monotonic.markNow()
            var resent = false
            while (true) {
                val outcome = try {
                    sender.reply(key, decision)
                } catch (e: Exception) {
                    // A CancellationException of the work itself ends it; one the call threw of its own is a failure.
                    rethrowIfCancelled(e)
                    if (e is LinkClientException.TimedOut && !resent) {
                        resent = true
                        continue
                    }
                    setStatus(key, DecisionStatus.Failed(failure(e)))
                    return
                }
                when (outcome) {
                    ReplyOutcome.DELIVERED -> {
                        latency.record(LatencyMetric.REPLY_ROUND_TRIP, start.elapsedNow())
                        setStatus(key, DecisionStatus.Done)
                    }
                    ReplyOutcome.ALREADY_HANDLED -> {
                        setStatus(key, DecisionStatus.HandledElsewhere)
                        linger(key, item)
                    }
                    else -> setStatus(key, DecisionStatus.Failed(DecisionFailure.REJECTED))
                }
                return
            }
        } finally {
            inFlight -= key
        }
    }

    private fun linger(key: PendingKey, item: MachinePendingItem?) {
        if (item != null) _state.update { it.copy(lingering = it.lingering + (key to item.copy(actionable = false))) }
        scope.launch {
            try {
                sleep(HANDLED_ELSEWHERE_LINGER)
            } catch (e: Exception) {
                rethrowIfCancelled(e)
            } finally {
                // A cancelled or failed wait still ends the linger: the card must not stay forever.
                endLinger(key)
            }
        }
    }

    private fun endLinger(key: PendingKey) {
        _state.update { it.copy(lingering = it.lingering - key) }
        if (shown[key] != null) {
            _state.update { it.copy(dismissed = it.dismissed + key) }
        } else {
            // Gone from the set already: nothing left to hide.
            forget(key)
        }
    }

    /** Drops what is kept about items that are neither pending, nor on their way, nor lingering. */
    private fun forgetGone(present: Map<PendingKey, MachinePendingItem>) {
        val s = state.value
        val known = s.status.keys + s.dismissed + lastDecision.keys
        val gone = known.filter { present[it] == null && it !in inFlight && it !in s.lingering }
        for (key in gone) forget(key)
    }

    private fun forget(key: PendingKey) {
        _state.update { it.copy(status = it.status - key, dismissed = it.dismissed - key) }
        lastDecision -= key
    }

    private fun setStatus(key: PendingKey, value: DecisionStatus?) {
        _state.update { if (value == null) it.copy(status = it.status - key) else it.copy(status = it.status + (key to value)) }
    }
}
