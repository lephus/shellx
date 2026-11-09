package com.shellx.core.account

import com.shellx.core.link.MachineHub
import com.shellx.core.platform.CoreLog
import com.shellx.core.platform.DetachedRun
import com.shellx.core.platform.KeyValueStore
import com.shellx.core.platform.rethrowIfCancelled
import com.shellx.core.platform.runDetached
import com.shellx.link.account.AccountSignIn
import com.shellx.link.account.RelayApiException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Owns the account state of the app (AppCoordinator.swift, Google only): which screen to show, how to get in and out,
 * and the [MachineHub] of the signed-in account (made on sign-in, stopped and dropped on sign-out or a 401).
 *
 * Main-confined. Every action runs in [scope] through runDetached, and the caller only waits: cancelling the caller
 * (Back, a configuration change, a cleared viewModelScope) never leaves a sign-in, sign-out or deletion half done. A
 * hub's onUnauthorized calls [handleUnauthorized] from the hub's own scope, which the sign-out cancels; the work goes
 * on in [scope].
 *
 * A sign-in, sign-out or deletion runs once at a time (review 3a m-2): a call while the same action is still running
 * (its screen went, and the next screen's tap came before the relay answered) waits for that run and gets its result,
 * so there is never a second Google prompt, a second relay sign-in, or a device token left signed in.
 *
 * Nothing here logs a token, a key or an email; log lines carry event names only.
 */
class AppCoordinator(
    private val vault: AccountVault,
    private val relay: RelayAccountCalling,
    private val identity: IdentityProviding,
    private val deviceName: String,
    private val wipers: List<LocalDataWiping>,
    /** Holds the non-secret "local wipe pending" marker across launches. */
    private val pendingWipeSettings: KeyValueStore,
    private val scope: CoroutineScope,
    private val makeHub: () -> MachineHub,
) {
    companion object {
        const val PENDING_WIPE_KEY = "shellx.localWipePending"
    }

    private val _phase = MutableStateFlow<AppPhase>(AppPhase.Launching)
    val phase: StateFlow<AppPhase> = _phase.asStateFlow()

    private val _hub = MutableStateFlow<MachineHub?>(null)

    /** The paired Macs and their links; non-null exactly while signed in. */
    val hub: StateFlow<MachineHub?> = _hub.asStateFlow()

    /**
     * True while an account deletion is on the relay: a 401 then answers the token the relay is deleting, so
     * handleUnauthorized only remembers it.
     */
    private var accountChangeInProgress = false
    private var unauthorizedDuringChange = false

    private val signingIn = DetachedRun<Unit>()
    private val signingOut = DetachedRun<Unit>()
    private val deleting = DetachedRun<Unit>()

    /**
     * Reads the stored session. A secret store that is unavailable for now keeps the phase at Launching;
     * [protectedDataBecameAvailable] tries again.
     */
    suspend fun launch() {
        scope.runDetached { load() }
    }

    /** Android: call on every ON_START (3D). Only acts while the phase is still Launching. */
    suspend fun protectedDataBecameAvailable() {
        scope.runDetached { if (_phase.value == AppPhase.Launching) load() }
    }

    /**
     * Continue with Google: the relay's nonce, Google's ID token for it, then the relay's sign-in. Throws
     * [SignInException].
     */
    suspend fun signInWithGoogle() {
        signingIn.run(scope) {
            // A sign-out whose local wipe failed blocks every sign-in until the wipe succeeds.
            if (!retryPendingWipe()) throw SignInException.LocalWipePending()
            val key = phoneKey()
            val signIn = try {
                val nonce = relay.nonce()
                val idToken = identity.googleIdToken(nonce)
                relay.signInWithGoogle(idToken, nonce, deviceName, key)
            } catch (e: Exception) {
                rethrowIfCancelled(e)
                throw SignInException.of(e)
            }
            completeSignIn(signIn)
        }
    }

    /**
     * Removes this phone from its Macs and the relay (best effort: each Mac's grant, this phone's push token, then
     * logout), then forgets everything local.
     */
    suspend fun signOut() {
        signingOut.run(scope) {
            stopHub()
            val token = try {
                vault.session()?.token
            } catch (e: Exception) {
                rethrowIfCancelled(e)
                null
            }
            if (token != null) {
                try {
                    for (grant in relay.machines(token)) {
                        try {
                            relay.unpair(grant.grantId, token)
                        } catch (e: Exception) {
                            rethrowIfCancelled(e)
                            CoreLog.log("sign_out_unpair_failed")
                        }
                    }
                } catch (e: Exception) {
                    rethrowIfCancelled(e)
                    CoreLog.log("sign_out_list_failed")
                }
                // Contracts §8 (ledger A-8): the push token goes before the session that owns it.
                try {
                    relay.unsetPushToken(token)
                } catch (e: Exception) {
                    rethrowIfCancelled(e)
                    CoreLog.log("sign_out_push_failed")
                }
                try {
                    relay.logout(token)
                } catch (e: Exception) {
                    rethrowIfCancelled(e)
                    CoreLog.log("sign_out_logout_failed")
                }
            }
            forgetLocalData()
            _phase.value = AppPhase.SignedOut(false)
        }
    }

    /**
     * The relay refused the stored token: drops the session only. The phone key and the Macs stay, so signing in again
     * as the same account needs no new pairing (S1 §6.3). During an account deletion it only remembers the 401.
     */
    suspend fun handleUnauthorized() {
        scope.runDetached { expire() }
    }

    /**
     * S1 §6.8: signs in with Google again, deletes the account on the relay, then forgets everything local as
     * [signOut] does, without unpairing, push or logout calls (the account is gone). Throws [SignInException]; on a
     * failure the session and the hub stay, unless the relay refused the stored token.
     */
    suspend fun deleteAccount() {
        deleting.run(scope) {
            val stored = try {
                vault.session()
            } catch (e: Exception) {
                rethrowIfCancelled(e)
                null
            } ?: throw SignInException.Server("signed_out")
            val nonce: String
            val idToken: String
            try {
                nonce = relay.nonce()
                idToken = identity.googleIdToken(nonce)
            } catch (e: Exception) {
                rethrowIfCancelled(e)
                throw SignInException.of(e)
            }
            accountChangeInProgress = true
            unauthorizedDuringChange = false
            try {
                relay.deleteAccount(idToken, nonce, stored.token)
            } catch (e: Exception) {
                throw endFailedAccountChange(e)
            }
            try {
                stopHub()
                forgetLocalData()
                _phase.value = AppPhase.SignedOut(false)
            } finally {
                accountChangeInProgress = false
                unauthorizedDuringChange = false
            }
        }
    }

    // Steps (each runs inside an action's detached work)

    private suspend fun load() {
        retryPendingWipe()
        val session = try {
            vault.session()
        } catch (e: SecretStoreException.Unavailable) {
            CoreLog.log("launch_keychain_unavailable")
            return
        } catch (e: Exception) {
            rethrowIfCancelled(e)
            CoreLog.log("launch_session_unreadable")
            _phase.value = AppPhase.SignedOut(false)
            return
        }
        if (session != null) {
            _phase.value = AppPhase.SignedIn(session.email)
            startHub()
        } else {
            _phase.value = AppPhase.SignedOut(false)
        }
    }

    private suspend fun phoneKey(): ByteArray = try {
        vault.phoneKey().publicKey
    } catch (e: Exception) {
        rethrowIfCancelled(e)
        CoreLog.log("sign_in_keychain_failed")
        throw SignInException.Server("keychain")
    }

    private suspend fun completeSignIn(signIn: AccountSignIn) {
        val account = signIn.session
        // Another account's Macs and history must not survive into this one. Every wiper runs first; the owner changes
        // only when all succeeded, so a retry wipes again.
        val previousOwner = try {
            vault.machinesOwner()
        } catch (e: Exception) {
            rethrowIfCancelled(e)
            CoreLog.log("sign_in_store_failed")
            throw SignInException.Server("keychain")
        }
        val otherAccount = previousOwner != null && previousOwner != account.userId
        if (otherAccount && !runWipers()) throw SignInException.LocalWipePending()
        try {
            if (otherAccount) vault.setMachines(emptyList(), account.userId)
            vault.setSession(StoredSession(account.userId, account.deviceId, account.token, signIn.email))
        } catch (e: Exception) {
            rethrowIfCancelled(e)
            CoreLog.log("sign_in_store_failed")
            throw SignInException.Server("keychain")
        }
        _phase.value = AppPhase.SignedIn(signIn.email)
        startHub()
    }

    private suspend fun expire() {
        if (accountChangeInProgress) {
            unauthorizedDuringChange = true
            return
        }
        stopHub()
        try {
            vault.clearSession()
        } catch (e: Exception) {
            rethrowIfCancelled(e)
            CoreLog.log("unauthorized_clear_failed")
        }
        _phase.value = AppPhase.SignedOut(true)
    }

    /**
     * A deletion failed on the relay: the session and the hub stay, unless the stored token itself was refused (or a
     * 401 raced the call), which signs out as expired. Returns what the caller throws.
     */
    private suspend fun endFailedAccountChange(error: Exception): SignInException {
        accountChangeInProgress = false
        val sawUnauthorized = unauthorizedDuringChange
        unauthorizedDuringChange = false
        rethrowIfCancelled(error)
        if (error is RelayApiException.Http && error.status == 401 && error.code == "unauthorized") {
            expire()
            return SignInException.Server("unauthorized")
        }
        if (sawUnauthorized) expire()
        return SignInException.of(error)
    }

    /**
     * The local part of signing out: the marker first, then the vault and every wiper. A failed wipe keeps the marker
     * and is retried before anyone signs in. If the app dies in between, the vault no longer names an owner, so only
     * the marker makes the next launch or sign-in wipe the history.
     */
    private suspend fun forgetLocalData() {
        pendingWipeSettings.putBoolean(PENDING_WIPE_KEY, true)
        try {
            vault.wipe()
        } catch (e: Exception) {
            rethrowIfCancelled(e)
            CoreLog.log("sign_out_wipe_failed")
        }
        if (runWipers()) pendingWipeSettings.remove(PENDING_WIPE_KEY)
    }

    /** Runs every wiper, continuing past failures; true when all succeeded. */
    private suspend fun runWipers(): Boolean {
        var allSucceeded = true
        for (wiper in wipers) {
            try {
                wiper.wipe()
            } catch (e: Exception) {
                rethrowIfCancelled(e)
                CoreLog.log("local_wipe_failed")
                allSucceeded = false
            }
        }
        return allSucceeded
    }

    /** When a sign-out left its local wipe undone, wipes again; true when nothing is pending. */
    private suspend fun retryPendingWipe(): Boolean {
        if (!pendingWipeSettings.getBoolean(PENDING_WIPE_KEY)) return true
        if (!runWipers()) return false
        pendingWipeSettings.remove(PENDING_WIPE_KEY)
        return true
    }

    private suspend fun startHub() {
        if (_hub.value != null) return
        val hub = makeHub()
        _hub.value = hub
        hub.start()
    }

    private suspend fun stopHub() {
        val hub = _hub.value ?: return
        hub.stopAll()
        if (_hub.value === hub) _hub.value = null
    }
}
