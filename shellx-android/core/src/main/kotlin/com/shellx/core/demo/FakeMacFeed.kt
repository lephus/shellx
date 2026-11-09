package com.shellx.core.demo

import com.shellx.link.core.LinkDecision
import com.shellx.link.core.PendingChange
import com.shellx.link.core.PendingItem
import com.shellx.link.core.PendingSnapshot
import com.shellx.link.core.ReplyOutcome
import kotlin.time.Duration
import kotlinx.coroutines.delay

/** [FakeMac]'s pending requests (FakeMacFeed.swift). Every member takes the Mac's lock. */
internal class FakeMacFeed(private val live: FakeMacLive) {
    private val lock = live.lock
    private val items = HashMap<String, PendingItem>()
    private val resolved = HashSet<String>()
    private var revision = 0L
    private var presetOutcome: ReplyOutcome? = null
    private var replyDelay = Duration.ZERO
    private var presetResolves = true
    private val replies = ArrayList<FakeMac.Decision>()
    private var snapshots = 0

    /** Snapshot requests wait while it holds (the session stays connected but never syncs). */
    val snapshotHold = FakeMacHold(lock)

    val decisions: List<FakeMac.Decision> get() = synchronized(lock) { replies.toList() }
    val snapshotCount: Int get() = synchronized(lock) { snapshots }

    fun add(item: PendingItem) {
        synchronized(lock) {
            items[item.requestId] = item
            broadcastLocked(listOf(item), emptyList())
        }
    }

    fun resolve(requestId: String) {
        synchronized(lock) { resolveLocked(requestId) }
    }

    /** Raises the revision without telling anyone, so the next change skips one. */
    fun skipRevision() {
        synchronized(lock) { revision += 1 }
    }

    fun setReplyOutcome(outcome: ReplyOutcome?, delay: Duration, resolves: Boolean) {
        synchronized(lock) {
            presetOutcome = outcome
            replyDelay = delay
            presetResolves = resolves
        }
    }

    suspend fun snapshot(): PendingSnapshot {
        snapshotHold.pass()
        return synchronized(lock) {
            snapshots += 1
            PendingSnapshot(revision, items.values.sortedBy { it.requestId })
        }
    }

    suspend fun reply(requestId: String, decision: LinkDecision): ReplyOutcome {
        val (preset, wait, resolves) = synchronized(lock) {
            replies += FakeMac.Decision(requestId, decision)
            Triple(presetOutcome, replyDelay, presetResolves)
        }
        if (wait > Duration.ZERO) delay(wait)
        return synchronized(lock) {
            when {
                preset != null -> {
                    if (preset == ReplyOutcome.DELIVERED && resolves) resolveLocked(requestId)
                    preset
                }
                items.containsKey(requestId) -> {
                    resolveLocked(requestId)
                    ReplyOutcome.DELIVERED
                }
                requestId in resolved -> ReplyOutcome.ALREADY_HANDLED
                else -> ReplyOutcome.UNKNOWN
            }
        }
    }

    private fun resolveLocked(requestId: String) {
        if (items.remove(requestId) == null) return
        resolved += requestId
        broadcastLocked(emptyList(), listOf(requestId))
    }

    private fun broadcastLocked(added: List<PendingItem>, resolved: List<String>) {
        revision += 1
        val change = PendingChange(revision, added, resolved)
        live.broadcastLocked { it.pendingQueue.trySend(change) }
    }
}
