package com.shellx.app.ui.nav

import com.shellx.core.account.AppPhase

/** What decides the root destination: the active account's phase, its hub and its scope. */
data class RootState(
    val demo: Boolean,
    val phase: AppPhase,
    val hubLoaded: Boolean,
    val hasMachines: Boolean,
    val scopeReady: Boolean,
)

/**
 * The one root destination (`RootView.swift`): launch while the account is read, sign-in when signed out, and the
 * signed-in screens once the hub is loaded and its scope made. A null or unloaded hub while SignedIn (a sign-out, a
 * deletion or a 401 under way) keeps launch, never sign-in (carry 3D-4).
 */
object RootRoutes {
    fun of(state: RootState): String {
        val ready = state.hubLoaded && state.scopeReady
        if (state.demo) return if (state.phase is AppPhase.SignedIn && ready) Routes.DEMO else Routes.LAUNCH
        return when (state.phase) {
            AppPhase.Launching -> Routes.LAUNCH
            is AppPhase.SignedOut -> Routes.SIGN_IN
            is AppPhase.SignedIn -> when {
                !ready -> Routes.LAUNCH
                state.hasMachines -> Routes.HOME
                else -> Routes.FIRST_MAC
            }
        }
    }
}
