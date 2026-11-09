package com.shellx.core.link

import com.shellx.link.core.PendingItem

/** One Mac's pending requests at a revision, oldest first (by `createdAtMs`, then `requestId`). Immutable. */
class PendingSet(val revision: Long = 0, items: List<PendingItem> = emptyList()) {
    val items: List<PendingItem> = sorted(items)

    /** The set replaced with a snapshot. */
    fun reset(revision: Long, items: List<PendingItem>): PendingSet = PendingSet(revision, items)

    /**
     * Applies an `agent.changed` when it is the next revision; otherwise leaves the set as it was and says why
     * (PROTOCOL.md section 4).
     */
    fun apply(revision: Long, added: List<PendingItem>, resolved: List<String>): Revised<PendingSet> {
        val result = RevisionGate.check(this.revision, revision)
        if (result != RevisionGate.Result.APPLIED) return Revised(this, result)
        val replaced = added.map { it.requestId }.toSet() + resolved
        val gone = resolved.toSet()
        val kept = items.filter { it.requestId !in replaced } + added.filter { it.requestId !in gone }
        return Revised(PendingSet(revision, kept), result)
    }

    override fun equals(other: Any?): Boolean = other is PendingSet && revision == other.revision && items == other.items

    override fun hashCode(): Int = revision.hashCode() * 31 + items.hashCode()

    override fun toString(): String = "PendingSet(revision=$revision, items=$items)"

    private companion object {
        fun sorted(items: List<PendingItem>): List<PendingItem> =
            items.sortedWith(compareBy<PendingItem> { it.createdAtMs }.thenBy { it.requestId })
    }
}
