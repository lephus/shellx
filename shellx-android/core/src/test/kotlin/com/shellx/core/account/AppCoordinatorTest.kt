package com.shellx.core.account

import com.shellx.core.demo.FakeMac
import com.shellx.core.platform.MemoryKeyValueStore
import com.shellx.core.testing.CoordinatorRig
import com.shellx.core.testing.CountingWiper
import com.shellx.core.testing.FakeRelayAccount.Call
import com.shellx.core.testing.FakeRelayAccount.Function
import com.shellx.core.testing.FlakyWiper
import com.shellx.core.testing.GatedWiper
import com.shellx.core.testing.InMemorySecretStore
import com.shellx.core.testing.assertSameCase
import com.shellx.core.testing.coordinatorRig
import com.shellx.core.testing.eventually
import com.shellx.core.testing.hex
import com.shellx.link.account.AccountSession
import com.shellx.link.account.AccountSignIn
import com.shellx.link.account.PairedMachine
import com.shellx.link.account.PairedMachineListing
import com.shellx.link.account.RelayApiException
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest

class AppCoordinatorTest {
    private val account = AccountSession("u1", "d1", "tok-1")
    private val mac = PairedMachine("m1", "Mac", "s1", ByteArray(32) { 1 })

    /** The Swift rig signs in as [account] with email "a@b.c". */
    private suspend fun TestScope.rig(
        store: InMemorySecretStore = InMemorySecretStore(),
        extraWipers: List<LocalDataWiping> = emptyList(),
        pendingSettings: MemoryKeyValueStore = MemoryKeyValueStore(),
    ): CoordinatorRig {
        val rig = coordinatorRig(extraWipers = extraWipers, store = store, pendingSettings = pendingSettings)
        rig.relay.setGoogleSignIn(Result.success(AccountSignIn(account, "a@b.c")))
        return rig
    }

    @Test fun signedInStartsHubAndSignOutStopsIt() { runTest {
        val rig = rig()
        rig.coordinator.launch()
        assertNull(rig.coordinator.hub.value, "no hub while signed out")

        rig.coordinator.signInWithGoogle()
        val hub = assertNotNull(rig.coordinator.hub.value)
        rig.vault.setMachines(listOf(mac), "u1")
        rig.coordinator.launch()
        assertSame(hub, rig.coordinator.hub.value, "launching again keeps the running hub")

        rig.coordinator.signOut()
        assertNull(rig.coordinator.hub.value)

        // A stored session starts the hub at launch, with the saved Macs; a 401 drops it.
        rig.vault.setSession(StoredSession("u1", "d1", "t", "a@b.c"))
        rig.vault.setMachines(listOf(mac), "u1")
        rig.coordinator.launch()
        assertEquals(listOf(mac), rig.coordinator.hub.value?.machines?.map { it.machine })
        rig.coordinator.handleUnauthorized()
        assertNull(rig.coordinator.hub.value)
    } }

    @Test fun launchWithoutSessionIsSignedOut() { runTest {
        val rig = rig()
        assertEquals(AppPhase.Launching, rig.coordinator.phase.value)
        rig.coordinator.launch()
        assertEquals(AppPhase.SignedOut(false), rig.coordinator.phase.value)
    } }

    @Test fun launchWithSessionIsSignedIn() { runTest {
        val rig = rig()
        rig.vault.setSession(StoredSession("u1", "d1", "t", "a@b.c"))
        rig.coordinator.launch()
        assertEquals(AppPhase.SignedIn("a@b.c"), rig.coordinator.phase.value)
    } }

    @Test fun unavailableKeychainDoesNotSignOut() { runTest {
        val store = InMemorySecretStore()
        val rig = rig(store = store)
        rig.vault.setSession(StoredSession("u1", "d1", "t", "a@b.c"))
        store.failReads = SecretStoreException.Unavailable()
        rig.coordinator.launch()
        assertEquals(AppPhase.Launching, rig.coordinator.phase.value)

        store.failReads = null
        rig.coordinator.protectedDataBecameAvailable()
        assertEquals(AppPhase.SignedIn("a@b.c"), rig.coordinator.phase.value)
    } }

    @Test fun signInSendsStoredPhoneKey() { runTest {
        val rig = rig()
        rig.coordinator.launch()
        rig.coordinator.signInWithGoogle()
        val stored = rig.vault.phoneKey()
        assertEquals(
            listOf(Call.Nonce, Call.SignInWithGoogle("google-id-token", "nonce-1", "Phu's Pixel", stored.publicKey.hex())),
            rig.relay.calls,
        )
        assertEquals(AppPhase.SignedIn("a@b.c"), rig.coordinator.phase.value)
        assertEquals(StoredSession("u1", "d1", "tok-1", "a@b.c"), rig.vault.session())

        // A second sign-in reuses the same key.
        rig.coordinator.signInWithGoogle()
        val keys = rig.relay.calls.filterIsInstance<Call.SignInWithGoogle>().map { it.clientKeyHex }
        assertEquals(2, keys.size)
        assertEquals(keys[0], keys[1])
    } }

    @Test fun signInMapsInvalidCredentialsAndRateLimit() { runTest {
        val rig = rig()
        val cases: List<Pair<Exception, SignInException>> = listOf(
            RelayApiException.Http(401, "invalid_credentials") to SignInException.InvalidCredentials(),
            RelayApiException.Http(429, "rate_limited") to SignInException.RateLimited(),
            IOException("offline") to SignInException.Network(),
            RelayApiException.Http(500, "internal") to SignInException.Server("internal"),
            RelayApiException.BadResponse() to SignInException.Server("bad_response"),
        )
        for ((thrown, expected) in cases) {
            rig.relay.setGoogleSignIn(Result.failure(thrown))
            assertSameCase(expected, assertFails { rig.coordinator.signInWithGoogle() }, "$thrown")
        }
        assertNull(rig.vault.session())
    } }

    @Test fun signOutUnpairsLogsOutAndWipes() { runTest {
        val rig = rig()
        rig.relay.setGrants(
            listOf(
                PairedMachineListing("g1", "m1", "A", "macos", true, "s", "f"),
                PairedMachineListing("g2", "m2", "B", "macos", false, "s", "f"),
            ),
        )
        rig.coordinator.signInWithGoogle()
        rig.vault.setMachines(listOf(mac), "u1")
        rig.relay.resetCalls()

        rig.coordinator.signOut()

        assertEquals(
            listOf(
                Call.Machines("tok-1"), Call.Unpair("g1", "tok-1"), Call.Unpair("g2", "tok-1"),
                Call.UnsetPushToken("tok-1"), Call.Logout("tok-1"),
            ),
            rig.relay.calls,
        )
        for (item in SecretItem.entries) assertNull(rig.store.read(item))
        assertEquals(1, rig.wiper.wipes)
        assertEquals(AppPhase.SignedOut(false), rig.coordinator.phase.value)
    } }

    @Test fun signOutWipesEvenWhenRelayUnreachable() { runTest {
        val rig = rig()
        rig.coordinator.signInWithGoogle()
        rig.relay.setError(IOException("offline"), Function.MACHINES)
        rig.relay.setError(IOException("offline"), Function.UNPAIR)
        rig.relay.setError(IOException("offline"), Function.LOGOUT)
        rig.relay.setError(IOException("offline"), Function.UNSET_PUSH_TOKEN)

        rig.coordinator.signOut()

        for (item in SecretItem.entries) assertNull(rig.store.read(item))
        assertEquals(1, rig.wiper.wipes)
        assertEquals(AppPhase.SignedOut(false), rig.coordinator.phase.value)
    } }

    @Test fun expiredTokenKeepsMachinesForSameAccount() { runTest {
        val rig = rig()
        rig.coordinator.signInWithGoogle()
        rig.vault.setMachines(listOf(mac), "u1")
        val key = rig.vault.phoneKey()

        rig.coordinator.handleUnauthorized()
        assertEquals(AppPhase.SignedOut(true), rig.coordinator.phase.value)
        assertNull(rig.vault.session())
        assertEquals(0, rig.wiper.wipes)

        rig.coordinator.signInWithGoogle()
        assertEquals(listOf(mac), rig.vault.machines())
        assertContentEquals(key.publicKey, rig.vault.phoneKey().publicKey)
        assertEquals(0, rig.wiper.wipes)
    } }

    @Test fun signInAsOtherAccountDropsMachines() { runTest {
        val rig = rig()
        rig.vault.setMachines(listOf(mac), "someone-else")
        rig.coordinator.signInWithGoogle()
        assertEquals(emptyList(), rig.vault.machines())
        assertEquals("u1", rig.vault.machinesOwner())
        assertEquals(1, rig.wiper.wipes)
    } }

    @Test fun failedWipeOnOtherAccountSignInKeepsOwnerAndRetriesWipe() { runTest {
        val flaky = FlakyWiper()
        val rig = rig(extraWipers = listOf(flaky))
        rig.vault.setMachines(listOf(mac), "someone-else")

        // Sign-in must fail while the previous account's data is still on the phone.
        assertSameCase(SignInException.LocalWipePending(), assertFails { rig.coordinator.signInWithGoogle() })
        // Every wiper ran although the first threw; the owner is still the previous account.
        assertEquals(1, flaky.attempts)
        assertEquals(1, rig.wiper.wipes)
        assertEquals("someone-else", rig.vault.machinesOwner())
        assertNull(rig.vault.session())

        flaky.setFailing(false)
        rig.coordinator.signInWithGoogle()
        assertEquals(2, flaky.attempts)
        assertEquals(2, rig.wiper.wipes)
        assertEquals("u1", rig.vault.machinesOwner())
    } }

    @Test fun signOutWithFailingWiperRetriesAtLaunchAndBlocksSignInUntilWiped() { runTest {
        val flaky = FlakyWiper()
        val pending = MemoryKeyValueStore()
        val rig = rig(extraWipers = listOf(flaky), pendingSettings = pending)
        flaky.setFailing(false)
        rig.coordinator.signInWithGoogle()
        flaky.setFailing(true)

        rig.coordinator.signOut()
        assertEquals(AppPhase.SignedOut(false), rig.coordinator.phase.value, "sign-out still completes")
        assertEquals(1, rig.wiper.wipes, "the other wiper ran although the first threw")
        // The vault is empty (no owner), so only the marker can force the retry.
        assertNull(rig.vault.machinesOwner())

        // A new launch retries and the wipe still fails: the marker stays and sign-in is refused.
        val relaunched = AppCoordinator(
            rig.vault, rig.relay, rig.identity, "iPhone", listOf(flaky, rig.wiper), pending, backgroundScope,
        ) { error("no hub expected") }
        relaunched.launch()
        assertEquals(2, flaky.attempts) // sign-out, then launch
        assertSameCase(SignInException.LocalWipePending(), assertFails { relaunched.signInWithGoogle() })
        assertEquals(AppPhase.SignedOut(false), relaunched.phase.value)

        // Once the wipe works, the next launch clears the marker.
        flaky.setFailing(false)
        relaunched.launch()
        assertEquals(4, flaky.attempts, "the blocked sign-in and this launch each retried once")
        assertFalse(pending.getBoolean(AppCoordinator.PENDING_WIPE_KEY))
        assertEquals(AppPhase.SignedOut(false), relaunched.phase.value)
    } }

    /**
     * The app dies during a sign-out after the vault was wiped (so no account owns the Macs any more) but before the
     * history wipers finished: the marker is already written, so the next launch wipes, and so would the next sign-in.
     */
    @Test fun signOutThatDiesBeforeTheWipersFinishIsWipedAtNextLaunch() { runTest {
        val gate = GatedWiper()
        val pending = MemoryKeyValueStore()
        val rig = rig(extraWipers = listOf(gate), pendingSettings = pending)
        rig.coordinator.signInWithGoogle()
        rig.vault.setMachines(listOf(mac), "u1")

        gate.hold()
        val signOut = launch { rig.coordinator.signOut() }
        assertTrue(eventually { gate.calls == 1 }, "the sign-out reached the history wipers")
        assertNull(rig.vault.machinesOwner(), "the vault is wiped already: only the marker can force the next wipe")
        assertTrue(pending.getBoolean(AppCoordinator.PENDING_WIPE_KEY), "the marker is written before anything is wiped")

        // The app dies here. The next launch finds the marker and wipes.
        val afterCrash = CountingWiper()
        val relaunched = AppCoordinator(
            rig.vault, rig.relay, rig.identity, "iPhone", listOf(afterCrash), pending, backgroundScope,
        ) { error("no hub expected") }
        relaunched.launch()
        assertEquals(1, afterCrash.wipes, "the launch finished the wipe")
        assertFalse(pending.getBoolean(AppCoordinator.PENDING_WIPE_KEY), "cleared once every wiper succeeded")

        gate.release()
        signOut.join()
    } }

    /** The marker stays set until every wiper succeeded, also when the vault itself was wiped fine. */
    @Test fun signOutClearsTheMarkerOnlyAfterEveryWiper() { runTest {
        val flaky = FlakyWiper()
        val pending = MemoryKeyValueStore()
        val rig = rig(extraWipers = listOf(flaky), pendingSettings = pending)
        flaky.setFailing(false)
        rig.coordinator.signInWithGoogle()

        rig.coordinator.signOut()
        assertFalse(pending.getBoolean(AppCoordinator.PENDING_WIPE_KEY), "all wipers succeeded")
        assertEquals(1, flaky.attempts)
        assertEquals(1, rig.wiper.wipes)
    } }

    // From MachineHubTests.swift

    @Test fun unauthorizedCallsCoordinator() { runTest {
        val a = FakeMac("MacBook Pro", backgroundScope)
        a.failNextConnects(RelayApiException.Http(401, "unauthorized"), 1)
        val rig = coordinatorRig(macs = listOf(a))
        rig.vault.setSession(StoredSession("u1", "d1", "tok-1", "a@b.c"))
        rig.vault.setMachines(listOf(a.machine), "u1")

        rig.coordinator.launch()

        assertTrue(
            eventually { rig.coordinator.phase.value == AppPhase.SignedOut(true) && rig.coordinator.hub.value == null },
            "${rig.coordinator.phase.value}",
        )
        assertEquals(listOf(a.machine), rig.vault.machines(), "an expired token keeps the paired Macs")
        assertEquals(1, a.connectCount)
    } }
}
