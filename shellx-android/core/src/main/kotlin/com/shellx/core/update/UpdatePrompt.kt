package com.shellx.core.update

import com.shellx.core.platform.CoreLog
import com.shellx.core.platform.rethrowIfCancelled
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Whether to offer the user a newer Play version. The app calls [check] at launch and each time it comes to the front;
 * the prompt shows while [offered] is set. [later] hides it until the next check, so it comes back the next time the
 * app opens. Never required: the app works on either version.
 *
 * Main-confined. 3D makes one only in release builds (S3 §6.1: never in debug) and calls [check] at launch and on
 * every ON_START.
 */
class UpdatePrompt(private val installedVersionCode: Long, private val checker: UpdateChecker) {
    private val _offered = MutableStateFlow<AvailableUpdate?>(null)

    /** A newer versionCode than the installed one, or null. */
    val offered: StateFlow<AvailableUpdate?> = _offered.asStateFlow()

    private var checking = false

    /** Asks the store once; a check while one is under way does nothing. A failed check (no network, no Play
     *  services) changes nothing and says nothing. */
    suspend fun check() {
        if (checking) return
        checking = true
        try {
            val update = try {
                checker.check()
            } catch (e: Exception) {
                rethrowIfCancelled(e)
                return
            }
            _offered.value = update?.takeIf { it.versionCode > installedVersionCode }
        } finally {
            checking = false
        }
    }

    /** The user picked Later, or went to the store: hide the prompt until the next check. */
    fun later() {
        _offered.value = null
    }

    /** The user picked Update: starts the store's flow for the offered version, if there is one, then hides the
     *  prompt. A flow that fails to start is logged and hidden too; the next check offers it again. */
    suspend fun update() {
        val update = offered.value ?: return
        try {
            checker.startUpdate(update)
        } catch (e: Exception) {
            rethrowIfCancelled(e)
            CoreLog.log("update_start_failed")
        } finally {
            later()
        }
    }
}
