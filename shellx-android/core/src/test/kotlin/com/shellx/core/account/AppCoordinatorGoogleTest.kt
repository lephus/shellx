package com.shellx.core.account

import com.shellx.core.demo.FakeMac
import com.shellx.core.link.MachineHub
import com.shellx.core.platform.MemoryKeyValueStore
import com.shellx.core.testing.CoordinatorRig
import com.shellx.core.testing.FakeRelayAccount.Call
import com.shellx.core.testing.FakeRelayAccount.Function
import com.shellx.core.testing.FlakyWiper
import com.shellx.core.testing.Gate
import com.shellx.core.testing.assertSameCase
import com.shellx.core.testing.coordinatorRig
import com.shellx.core.testing.eventually
import com.shellx.core.testing.hex
import com.shellx.link.account.AccountSession
import com.shellx.link.account.AccountSignIn
import com.shellx.link.account.PairedMachine
import com.shellx.link.account.RelayApiException
import java.io.IOException
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

/** Google sign-in, sign-out's push call and account deletion (1C Tasks 6 and 7, S1 §6.3 and §6.8). */
class AppCoordinatorGoogleTest {
    private val google = AccountSignIn(AccountSession("u1", "d1", "tok-g"), "g@example.com")

    private suspend fun TestScope.rig(
        macs: List<FakeMac> = emptyList(),
        extraWipers: List<LocalDataWiping> = emptyList(),
        pendingSettings: MemoryKeyValueStore = MemoryKeyValueStore(),
    ): CoordinatorRig {
        val rig = coordinatorRig(macs = macs, extraWipers = extraWipers, pendingSettings = pendingSettings)
        rig.relay.setGoogleSignIn(Result.success(google))
        return rig
    }

    /** A stored session "tok-old" for u1, then launch(). */
    private suspend fun TestScope.signedInRig(macs: List<FakeMac> = emptyList()): CoordinatorRig {
        val rig = rig(macs)
        rig.vault.setSession(StoredSession("u1", "d1", "tok-old", "g@example.com"))
        rig.coordinator.launch()
        return rig
    }

    private fun assertNothingStored(rig: CoordinatorRig) {
        for (item in SecretItem.entries) assertNull(rig.store.read(item), "$item")
    }

    /** Every phase from now on, each one as it is set: an unconfined collector misses none. */
    private fun TestScope.recordPhases(rig: CoordinatorRig): List<AppPhase> {
        val phases = mutableListOf<AppPhase>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { rig.coordinator.phase.collect { phases += it } }
        return phases
    }

    @Test fun googleSignInSendsTheNonceTheTokenAndThePhoneKey() { runTest {
        val rig = rig()
        rig.coordinator.launch()
        rig.coordinator.signInWithGoogle()
        assertEquals(
            listOf(
                Call.Nonce,
                Call.SignInWithGoogle("google-id-token", "nonce-1", "Phu's Pixel", rig.vault.phoneKey().publicKey.hex()),
            ),
            rig.relay.calls,
        )
        assertEquals(listOf("nonce-1"), rig.identity.googleNonces)
        assertEquals(StoredSession("u1", "d1", "tok-g", "g@example.com"), rig.vault.session())
        assertEquals(AppPhase.SignedIn("g@example.com"), rig.coordinator.phase.value)
        assertNotNull(rig.coordinator.hub.value)
    } }

    @Test fun googleSignInCancelledChangesNothing() { runTest {
        val rig = rig()
        rig.coordinator.launch()
        rig.identity.googleResult = Result.failure(IdentityProviderException.Cancelled())
        assertSameCase(SignInException.Cancelled(), assertFails { rig.coordinator.signInWithGoogle() })
        assertEquals(listOf<Call>(Call.Nonce), rig.relay.calls)
        assertEquals(AppPhase.SignedOut(false), rig.coordinator.phase.value)
        assertNull(rig.coordinator.hub.value)

        rig.identity.googleResult = Result.success("google-id-token")
        rig.coordinator.signInWithGoogle()
        assertEquals(AppPhase.SignedIn("g@example.com"), rig.coordinator.phase.value)
    } }

    @Test fun googleSignInErrorsMap() { runTest {
        val rig = rig()
        rig.coordinator.launch()
        val relayCases: List<Pair<Exception, SignInException>> = listOf(
            RelayApiException.Http(409, "switch_from_signed_in_device") to SignInException.SwitchFromSignedInDevice(),
            RelayApiException.Http(401, "invalid_credentials") to SignInException.InvalidCredentials(),
            RelayApiException.Http(429, "rate_limited") to SignInException.RateLimited(),
            IOException("offline") to SignInException.Network(),
        )
        for ((thrown, expected) in relayCases) {
            rig.relay.setGoogleSignIn(Result.failure(thrown))
            assertSameCase(expected, assertFails { rig.coordinator.signInWithGoogle() }, "$thrown")
        }
        rig.relay.setGoogleSignIn(Result.success(google))
        val identityCases: List<Pair<Exception, SignInException>> = listOf(
            IdentityProviderException.NotConfigured() to SignInException.ProviderUnavailable(),
            IdentityProviderException.Failed() to SignInException.ProviderFailed(),
        )
        for ((thrown, expected) in identityCases) {
            rig.identity.googleResult = Result.failure(thrown)
            assertSameCase(expected, assertFails { rig.coordinator.signInWithGoogle() }, "$thrown")
        }
        assertNull(rig.vault.session())
    } }

    @Test fun googleSignInAsAnotherAccountWipesTheOldHistory() { runTest {
        val rig = rig()
        val m0 = PairedMachine("m0", "Mac", "s0", ByteArray(32) { 2 })
        rig.vault.setMachines(listOf(m0), "someone-else")
        rig.coordinator.launch()
        rig.coordinator.signInWithGoogle()
        assertEquals(1, rig.wiper.wipes)
        assertEquals(emptyList(), rig.vault.machines())
        assertEquals("u1", rig.vault.machinesOwner())
    } }

    @Test fun pendingWipeBlocksGoogleSignInBeforeAnyRelayCall() { runTest {
        val pending = MemoryKeyValueStore()
        pending.putBoolean(AppCoordinator.PENDING_WIPE_KEY, true)
        val rig = rig(extraWipers = listOf(FlakyWiper()), pendingSettings = pending)
        assertSameCase(SignInException.LocalWipePending(), assertFails { rig.coordinator.signInWithGoogle() })
        assertEquals(emptyList(), rig.relay.calls)
        assertEquals(emptyList(), rig.identity.googleNonces)
    } }

    @Test fun signOutDeletesThePushTokenBeforeLoggingOut() { runTest {
        val rig = rig()
        rig.coordinator.signInWithGoogle()
        rig.coordinator.signOut()
        assertEquals(listOf(Call.UnsetPushToken("tok-g"), Call.Logout("tok-g")), rig.relay.calls.takeLast(2))
    } }

    @Test fun deleteAccountReauthenticatesDeletesAndWipesLikeSignOut() { runTest {
        val rig = signedInRig()
        rig.identity.googleResult = Result.success("google-fresh")

        rig.coordinator.deleteAccount()

        // No unpair, push or logout call: the account is gone.
        assertEquals(listOf(Call.Nonce, Call.DeleteAccount("google-fresh", "nonce-1", "tok-old")), rig.relay.calls)
        assertNothingStored(rig)
        assertEquals(1, rig.wiper.wipes)
        assertFalse(rig.pendingSettings.getBoolean(AppCoordinator.PENDING_WIPE_KEY))
        assertEquals(AppPhase.SignedOut(false), rig.coordinator.phase.value)
        assertNull(rig.coordinator.hub.value)
    } }

    @Test fun cancelledOrRefusedDeleteKeepsEverything() { runTest {
        val rig = signedInRig()
        val hub = assertNotNull(rig.coordinator.hub.value)

        rig.identity.googleResult = Result.failure(IdentityProviderException.Cancelled())
        assertSameCase(SignInException.Cancelled(), assertFails { rig.coordinator.deleteAccount() })
        assertEquals(listOf<Call>(Call.Nonce), rig.relay.calls)

        rig.identity.googleResult = Result.success("google-fresh")
        rig.relay.setError(RelayApiException.Http(401, "reauth_required"), Function.DELETE_ACCOUNT)
        assertSameCase(SignInException.ReauthRequired(), assertFails { rig.coordinator.deleteAccount() })
        assertEquals("tok-old", rig.vault.session()?.token)
        assertSame(hub, rig.coordinator.hub.value)
        assertEquals(AppPhase.SignedIn("g@example.com"), rig.coordinator.phase.value)
    } }

    @Test fun deleteWithARefusedTokenSignsOutAsExpired() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        val rig = rig(listOf(mac))
        rig.vault.setSession(StoredSession("u1", "d1", "tok-old", "g@example.com"))
        rig.vault.setMachines(listOf(mac.machine), "u1")
        rig.coordinator.launch()
        rig.relay.setError(RelayApiException.Http(401, "unauthorized"), Function.DELETE_ACCOUNT)

        assertSameCase(SignInException.Server("unauthorized"), assertFails { rig.coordinator.deleteAccount() })

        assertEquals(AppPhase.SignedOut(true), rig.coordinator.phase.value)
        assertNull(rig.coordinator.hub.value)
        assertEquals(listOf(mac.machine), rig.vault.machines())
    } }

    /**
     * A 401 while the deletion is on the relay answers the token being deleted, so it is only remembered (review 3a
     * I-1): the hub stays, and "session expired" never shows on the way to SignedOut(false).
     */
    @Test fun unauthorizedDuringDeleteEndsSignedOutNotExpired() { runTest {
        val rig = signedInRig()
        val hub = assertNotNull(rig.coordinator.hub.value)
        val phases = recordPhases(rig)
        var phaseAfter401: AppPhase? = null
        var hubAfter401: MachineHub? = null
        rig.relay.setHook({
            rig.coordinator.handleUnauthorized()
            phaseAfter401 = rig.coordinator.phase.value
            hubAfter401 = rig.coordinator.hub.value
        }, Function.DELETE_ACCOUNT)

        rig.coordinator.deleteAccount()

        assertEquals(AppPhase.SignedIn("g@example.com"), phaseAfter401, "the 401 is only remembered")
        assertSame(hub, hubAfter401, "the hub is not stopped before the relay answered")
        assertFalse(AppPhase.SignedOut(true) in phases, "$phases")
        assertEquals(AppPhase.SignedOut(false), rig.coordinator.phase.value)
        assertNothingStored(rig)
    } }

    /** Review 3a I-1: a 401 raced the deletion, which then failed: the stored token is dead, so it signs out as expired. */
    @Test fun unauthorizedDuringAFailedDeleteSignsOutAsExpired() { runTest {
        val mac = FakeMac("Mac", backgroundScope)
        val rig = rig(listOf(mac))
        rig.vault.setSession(StoredSession("u1", "d1", "tok-old", "g@example.com"))
        rig.vault.setMachines(listOf(mac.machine), "u1")
        rig.coordinator.launch()
        rig.relay.setHook({ rig.coordinator.handleUnauthorized() }, Function.DELETE_ACCOUNT)
        rig.relay.setError(RelayApiException.Http(500, "internal"), Function.DELETE_ACCOUNT)

        assertSameCase(SignInException.Server("internal"), assertFails { rig.coordinator.deleteAccount() })

        assertEquals(AppPhase.SignedOut(true), rig.coordinator.phase.value)
        assertNull(rig.coordinator.hub.value)
        assertNull(rig.vault.session())
        assertEquals(listOf(mac.machine), rig.vault.machines(), "the Macs stay, as after any 401")
        assertEquals(0, rig.wiper.wipes)
    } }

    @Test fun deleteWithoutASessionIsSignedOut() { runTest {
        val rig = rig()
        rig.coordinator.launch()
        assertSameCase(SignInException.Server("signed_out"), assertFails { rig.coordinator.deleteAccount() })
        assertEquals(emptyList(), rig.relay.calls)
    } }

    /** Review Focus 1: the screen that started the sign-out went away in the middle of it. */
    @Test fun aCancelledSignOutStillWipes() { runTest {
        val rig = rig()
        rig.coordinator.signInWithGoogle()
        val gate = Gate()
        rig.relay.setHook({ gate.wait() }, Function.LOGOUT)

        val caller = launch { rig.coordinator.signOut() }
        assertTrue(eventually { gate.waiting == 1 })
        // The gate holds the logout whatever happens, so a caller stuck behind it would hang a cancelAndJoin: look
        // whether the wait ended, then open the gate.
        caller.cancel()
        runCurrent()
        val released = caller.isCompleted
        gate.open()
        caller.join()
        assertTrue(released, "the caller's wait ends at once")

        assertTrue(eventually { rig.coordinator.phase.value == AppPhase.SignedOut(false) })
        assertNothingStored(rig)
        assertEquals(1, rig.wiper.wipes)
    } }

    /**
     * Review 1 M-3: a step that throws a CancellationException of its own (an inner timeout, a Deferred cancelled
     * elsewhere) while nobody cancelled the action is a failure: the caller never mistakes it for its own cancellation,
     * and a sign-out still wipes.
     */
    @Test fun aStepThatCancelsItselfIsAFailureNotASilentEnd() { runTest {
        val rig = rig()
        rig.coordinator.launch()
        rig.identity.googleResult = Result.failure(CancellationException("own"))
        val failure = assertFails { rig.coordinator.signInWithGoogle() }
        assertSameCase(SignInException.Server("unknown"), failure)
        assertEquals(AppPhase.SignedOut(false), rig.coordinator.phase.value)

        rig.identity.googleResult = Result.success("google-id-token")
        rig.coordinator.signInWithGoogle()
        rig.relay.setError(CancellationException("own"), Function.LOGOUT)
        rig.coordinator.signOut()
        assertEquals(AppPhase.SignedOut(false), rig.coordinator.phase.value)
        assertNothingStored(rig)
        assertEquals(1, rig.wiper.wipes)
    } }
}
