package com.shellx.core.update

/** A newer build in the store: its Play `versionCode`. */
data class AvailableUpdate(val versionCode: Long)

/**
 * The store (contracts §5; 3E implements it with Play In-App Updates: UPDATE_AVAILABLE and FLEXIBLE allowed →
 * `AvailableUpdate(availableVersionCode())`, else null; [startUpdate] starts the flexible flow).
 */
interface UpdateChecker {
    /** May throw; a failure changes nothing. */
    suspend fun check(): AvailableUpdate?

    suspend fun startUpdate(update: AvailableUpdate)
}
