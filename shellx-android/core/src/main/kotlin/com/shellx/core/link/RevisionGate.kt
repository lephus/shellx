package com.shellx.core.link

/** The revision rule of ShellX Link (PROTOCOL.md section 4) for the pending set, the session list and the workspaces. */
object RevisionGate {
    enum class Result {
        /** The change is the next one: apply it. */
        APPLIED,

        /** The change is at or below the current revision: it is already in the set. */
        IGNORED,

        /** One or more changes were missed: ask the host for the full set again. */
        GAP,
    }

    /** How a change at revision [incoming] relates to a set at revision [current]. */
    fun check(current: Long, incoming: Long): Result = when {
        incoming <= current -> Result.IGNORED
        incoming == current + 1 -> Result.APPLIED
        else -> Result.GAP
    }
}

/** A set, and what a change did to it: [value] is the changed set when APPLIED, else the set unchanged. */
data class Revised<T>(val value: T, val result: RevisionGate.Result)
