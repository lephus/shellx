package com.shellx.core.pairing

import com.shellx.core.account.AccountVault
import com.shellx.core.account.AppPhase
import com.shellx.core.account.RelayAccountCalling
import com.shellx.core.account.SecretStoreException
import com.shellx.core.account.StoredSession
import com.shellx.core.demo.FakeMac
import com.shellx.core.demo.FakeMacFleet
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachineLinkState
import com.shellx.core.platform.MemoryKeyValueStore
import com.shellx.core.testing.FakeRelayAccount
import com.shellx.core.testing.FakeRelayAccount.Call
import com.shellx.core.testing.FakeRelayAccount.Function
import com.shellx.core.testing.Gate
import com.shellx.core.testing.InMemorySecretStore
import com.shellx.core.testing.ManualClock
import com.shellx.core.testing.ManualSleeper
import com.shellx.core.testing.coordinatorRig
import com.shellx.core.testing.eventually
import com.shellx.core.testing.hex
import com.shellx.core.testing.instantSleep
import com.shellx.link.account.PairedMachine
import com.shellx.link.account.PhonePairingException
import com.shellx.link.account.RelayApiException
import com.shellx.link.core.PairingOffer
import java.io.IOException
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest

private class PairingRig(
    val model: PairingModel,
    val hub: MachineHub,
    val vault: AccountVault,
    val relay: FakeRelayAccount,
    /** The relay's wait for the user to press Allow on the Mac. */
    val approval: ManualSleeper,
    val store: InMemorySecretStore,
)

/**
 * Session u1/d1/tok-1 stored, `saved` Macs saved; FakeRelayAccount(sleep = approval.sleep), wrapped by `relay`; a
 * started hub over FakeMacFleet(macs) with instantSleep; PairingModel(hub, relay(fake), vault, backgroundScope).
 */
private suspend fun TestScope.pairingRig(
    macs: List<FakeMac>,
    saved: List<FakeMac> = emptyList(),
    relay: (FakeRelayAccount) -> RelayAccountCalling = { it },
): PairingRig {
    val store = InMemorySecretStore()
    val vault = AccountVault(store, StandardTestDispatcher(testScheduler))
    vault.setSession(StoredSession("u1", "d1", "tok-1", "a@b.c"))
    if (saved.isNotEmpty()) vault.setMachines(saved.map { it.machine }, "u1")
    val approval = ManualSleeper()
    val fake = FakeRelayAccount(sleep = approval.sleep)
    val wrapped = relay(fake)
    val hub = MachineHub(
        vault, wrapped, FakeMacFleet(macs) { vault.phoneKey() }, LatencyLog(), MemoryKeyValueStore(), backgroundScope,
        ManualClock(), instantSleep,
    ) {}
    hub.start()
    return PairingRig(PairingModel(hub, wrapped, vault, backgroundScope), hub, vault, fake, approval, store)
}

/** A relay whose pair waits for the gate, ignoring cancellation (as a relay call that answers anyway), then answers
 *  like the base. */
private class HeldPairRelay(private val base: FakeRelayAccount, private val gate: Gate) : RelayAccountCalling by base {
    override suspend fun pair(offerUri: String, clientKey: ByteArray, token: String): PairedMachine {
        try {
            gate.wait()
        } catch (_: CancellationException) {
            // The relay call ignores the cancellation: the Mac's approval still comes back.
        }
        return base.pair(offerUri, clientKey, token)
    }
}

class PairingModelTest {
    private fun unpairCalls(relay: FakeRelayAccount): List<String> =
        relay.calls.filterIsInstance<Call.Unpair>().map { it.grantId }

    private fun pairCalls(relay: FakeRelayAccount): Int = relay.calls.count { it is Call.Pair }

    // Brief tests

    @Test fun validUriAsksConfirmationBeforeNetwork() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val rig = pairingRig(listOf(mac))
        val offer = mac.pairingOffer()

        rig.model.begin(offer.uri)

        assertEquals(PairingModel.Step.Confirm("MacBook Pro"), rig.model.step.value)
        assertEquals(emptyList(), rig.relay.calls, "nothing reaches the relay before the user confirms")
        assertTrue(rig.hub.machines.isEmpty())

        // A code pasted with blanks or a line break around it is still the code.
        rig.model.cancel()
        assertEquals(PairingModel.Step.Idle, rig.model.step.value)
        rig.model.begin("  ${offer.uri}\n")
        assertEquals(PairingModel.Step.Confirm("MacBook Pro"), rig.model.step.value)
        assertEquals(emptyList(), rig.relay.calls)
    } }

    @Test fun confirmPairsSavesAndConnects() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val rig = pairingRig(listOf(mac))
        val offer = mac.pairingOffer()
        rig.model.begin(offer.uri)

        rig.model.confirm()

        assertEquals(PairingModel.Step.Paired("MacBook Pro"), rig.model.step.value)
        val key = rig.vault.phoneKey().publicKey
        assertEquals(listOf<Call>(Call.Pair(offer.uri, key.hex(), "tok-1")), rig.relay.calls)
        assertEquals(listOf(mac.machine), rig.vault.machines(), "the hub saved the Mac, with the host key from the QR code")
        assertEquals("u1", rig.vault.machinesOwner())
        assertEquals(listOf("MacBook Pro"), rig.hub.machines.map { it.name })
        assertTrue(eventually { rig.hub.machines.firstOrNull()?.state == MachineLinkState.Online }, "${rig.hub.machines.map { it.state }}")

        // The offer was used up: confirming again sends nothing.
        rig.model.confirm()
        assertEquals(1, pairCalls(rig.relay))
    } }

    @Test fun repairReplacesSameMachine() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val rig = pairingRig(listOf(mac), saved = listOf(mac))
        assertTrue(eventually { rig.hub.machines.firstOrNull()?.state == MachineLinkState.Online })
        mac.rotateHostKey()
        mac.dropLiveSessions()
        assertTrue(
            eventually { rig.hub.machines.firstOrNull()?.state == MachineLinkState.HostKeyChanged },
            "${rig.hub.machines.map { it.state }}",
        )

        val offer = mac.pairingOffer()
        assertFalse(offer.hostKey.contentEquals(mac.machine.hostKey))
        rig.model.begin(offer.uri)
        rig.model.confirm()

        assertEquals(PairingModel.Step.Paired("MacBook Pro"), rig.model.step.value)
        val saved = rig.vault.machines()
        assertEquals(listOf(mac.machine.machineId), saved.map { it.machineId }, "one record per Mac")
        assertContentEquals(offer.hostKey, saved.firstOrNull()?.hostKey, "the new key is pinned")
        assertEquals(1, rig.hub.machines.size)
        assertTrue(eventually { rig.hub.machines.firstOrNull()?.state == MachineLinkState.Online }, "${rig.hub.machines.map { it.state }}")
    } }

    @Test fun deniedAndExpiredMapped() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val rig = pairingRig(listOf(mac))
        val offer = mac.pairingOffer()

        for ((error, failure) in listOf(PhonePairingException.Denied() to PairingFailure.Denied, PhonePairingException.Expired() to PairingFailure.Expired)) {
            rig.relay.setError(error, Function.PAIR)
            rig.model.begin(offer.uri)
            rig.model.confirm()
            assertEquals(PairingModel.Step.Failed(failure), rig.model.step.value)
        }

        assertTrue(rig.hub.machines.isEmpty())
        assertEquals(emptyList(), rig.vault.machines())
    } }

    @Test fun otherAccountMapped() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val rig = pairingRig(listOf(mac))
        rig.relay.setError(RelayApiException.Http(404, "machine_not_found"), Function.PAIR)

        rig.model.begin(mac.pairingOffer().uri)
        rig.model.confirm()

        assertEquals(PairingModel.Step.Failed(PairingFailure.OtherAccount), rig.model.step.value)
        assertTrue(rig.hub.machines.isEmpty())
    } }

    @Test fun badUriMapped() { runTest {
        val rig = pairingRig(emptyList())
        val good = PairingOffer("m1", "s1", ByteArray(32) { 7 }, ByteArray(16) { 9 }, "Mac").uri

        /** [good] with the query field [name] set to [value], or removed when [value] is null. */
        fun variant(name: String, value: String?): String {
            val (head, query) = good.split("?", limit = 2)
            val items = query.split("&").mapNotNull { item ->
                if (item.substringBefore("=") != name) item else value?.let { "$name=$it" }
            }
            return "$head?${items.joinToString("&")}"
        }
        val cases = listOf(
            "" to PairingFailure.NotShellXCode,
            "hello" to PairingFailure.NotShellXCode,
            "https://shellx.pro/pair?v=1" to PairingFailure.NotShellXCode,
            variant("v", "2") to PairingFailure.NeedsUpdate,
            variant("k", "short") to PairingFailure.DamagedCode,
            variant("n", null) to PairingFailure.DamagedCode,
        )
        for ((text, failure) in cases) {
            rig.model.begin(text)
            assertEquals(PairingModel.Step.Failed(failure), rig.model.step.value, text)
        }
        // A good code still works after a bad one.
        rig.model.begin(good)
        assertEquals(PairingModel.Step.Confirm("Mac"), rig.model.step.value)
        assertEquals(emptyList(), rig.relay.calls)
    } }

    @Test fun cancelStopsWaiting() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val rig = pairingRig(listOf(mac))
        rig.relay.setApprovalDelay(2.seconds)
        rig.model.begin(mac.pairingOffer().uri)

        val confirming = launch { rig.model.confirm() }
        assertTrue(eventually { rig.approval.waiting.size == 1 })
        assertEquals(PairingModel.Step.WaitingForMac("MacBook Pro"), rig.model.step.value)

        rig.model.cancel()

        assertEquals(PairingModel.Step.Idle, rig.model.step.value)
        confirming.join()
        assertEquals(PairingModel.Step.Idle, rig.model.step.value, "a cancelled attempt reports nothing")
        assertEquals(1, rig.approval.cancelled, "the wait for the Mac stopped")
        assertTrue(rig.hub.machines.isEmpty())
        assertEquals(emptyList(), rig.vault.machines())

        // The offer was dropped with the attempt.
        rig.model.confirm()
        assertEquals(1, pairCalls(rig.relay))
    } }

    // More

    @Test fun networkAndServerErrorsMapped() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val rig = pairingRig(listOf(mac))
        val offer = mac.pairingOffer()
        val cases: List<Pair<Exception, PairingFailure>> = listOf(
            IOException("offline") to PairingFailure.Network,
            RelayApiException.Http(500, "internal") to PairingFailure.Server("internal"),
            RelayApiException.BadResponse() to PairingFailure.Server("bad_response"),
        )
        for ((error, failure) in cases) {
            rig.relay.setError(error, Function.PAIR)
            rig.model.begin(offer.uri)
            rig.model.confirm()
            assertEquals(PairingModel.Step.Failed(failure), rig.model.step.value)
        }
    } }

    /**
     * The Mac approves just as the user cancels (the relay call ignores the cancellation): the cancelled attempt must
     * not save or connect anything, and takes back the grant the relay made, so the Mac does not list a phone that does
     * not know it.
     */
    @Test fun approvalAfterCancelIsIgnored() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val gate = Gate()
        val rig = pairingRig(listOf(mac), relay = { HeldPairRelay(it, gate) })
        rig.model.begin(mac.pairingOffer().uri)

        val confirming = launch { rig.model.confirm() }
        assertTrue(eventually { gate.waiting == 1 })
        rig.model.cancel()
        gate.open()
        confirming.join()

        assertEquals(PairingModel.Step.Idle, rig.model.step.value)
        assertTrue(rig.hub.machines.isEmpty())
        assertEquals(emptyList(), rig.vault.machines())
        assertEquals(listOf("grant-${mac.machine.machineId}"), unpairCalls(rig.relay), "the orphan grant was withdrawn")
        assertEquals(emptyList(), rig.relay.machines("tok-1"))
    } }

    /** The Mac approved but the phone could not save it: the grant is taken back too. */
    @Test fun saveFailureAfterApprovalWithdrawsGrant() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val rig = pairingRig(listOf(mac))
        rig.vault.phoneKey()
        rig.store.failWrites = SecretStoreException.Failed()
        rig.model.begin(mac.pairingOffer().uri)

        rig.model.confirm()

        assertEquals(PairingModel.Step.Failed(PairingFailure.Server("keychain")), rig.model.step.value)
        assertTrue(rig.hub.machines.isEmpty())
        assertEquals(listOf("grant-${mac.machine.machineId}"), unpairCalls(rig.relay))
        assertEquals(emptyList(), rig.relay.machines("tok-1"))
    } }

    /** Withdrawing is best effort: a relay that cannot be reached leaves the failure as it was. */
    @Test fun withdrawErrorsAreIgnored() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val rig = pairingRig(listOf(mac))
        rig.vault.phoneKey()
        rig.store.failWrites = SecretStoreException.Failed()
        rig.relay.setError(IOException("offline"), Function.UNPAIR)
        rig.model.begin(mac.pairingOffer().uri)

        rig.model.confirm()

        assertEquals(PairingModel.Step.Failed(PairingFailure.Server("keychain")), rig.model.step.value)
    } }

    /** Cancelling a re-pair of a Mac this phone already keeps must not take away its grant: it is not an orphan. */
    @Test fun cancelledRepairKeepsTheGrantOfAPairedMac() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val gate = Gate()
        val rig = pairingRig(listOf(mac), saved = listOf(mac), relay = { HeldPairRelay(it, gate) })
        rig.model.begin(mac.pairingOffer().uri)

        val confirming = launch { rig.model.confirm() }
        eventually { gate.waiting == 1 }
        rig.model.cancel()
        gate.open()
        confirming.join()

        assertEquals(emptyList(), unpairCalls(rig.relay))
        assertEquals(listOf(mac.machine.machineId), rig.hub.machines.map { it.id })
    } }

    /**
     * The system routes a link whatever the scheme's case, and the parser wants it lowercase: the inbox and the model
     * agree, so `SHELLX-LINK://pair…` reaches the confirmation, and the relay gets the code with a lowercase scheme.
     */
    @Test fun uppercaseSchemeLinkReachesConfirmation() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val rig = pairingRig(listOf(mac))
        val uri = mac.pairingOffer().uri
        val shouted = "SHELLX-LINK" + uri.drop("shellx-link".length)
        val inbox = PairingInbox()

        assertTrue(inbox.receive(shouted))
        rig.model.begin(assertNotNull(inbox.take()))

        assertEquals(PairingModel.Step.Confirm("MacBook Pro"), rig.model.step.value)
        rig.model.confirm()
        assertEquals(PairingModel.Step.Paired("MacBook Pro"), rig.model.step.value)
        val key = rig.vault.phoneKey().publicKey
        assertEquals(Call.Pair(uri, key.hex(), "tok-1"), rig.relay.calls.firstOrNull())
    } }

    /**
     * The relay refuses the token while pairing: the app signs out to the "session expired" sign-in, instead of leaving
     * the user retrying a pairing that cannot work.
     */
    @Test fun unauthorizedWhilePairingSignsOut() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val saved = FakeMac("Mac mini", backgroundScope)
        val rig = coordinatorRig(macs = listOf(mac, saved))
        rig.vault.setSession(StoredSession("u1", "d1", "tok-1", "a@b.c"))
        rig.vault.setMachines(listOf(saved.machine), "u1")
        rig.coordinator.launch()
        val hub = assertNotNull(rig.coordinator.hub.value)
        rig.relay.setError(RelayApiException.Http(401, "unauthorized"), Function.PAIR)
        val model = PairingModel(hub, rig.relay, rig.vault, backgroundScope)
        model.begin(mac.pairingOffer().uri)

        model.confirm()

        assertEquals(AppPhase.SignedOut(true), rig.coordinator.phase.value, "sign-in says the session expired")
        assertNull(rig.vault.session())
        assertEquals(listOf(saved.machine), rig.vault.machines(), "the paired Macs stay for the same account")
    } }

    /** A second link while waiting replaces the attempt: the first stops and asks again. */
    @Test fun newLinkWhileWaitingStartsOver() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val other = FakeMac("Mac mini", backgroundScope)
        val rig = pairingRig(listOf(mac, other))
        rig.relay.setApprovalDelay(2.seconds)
        rig.model.begin(mac.pairingOffer().uri)
        val confirming = launch { rig.model.confirm() }
        eventually { rig.approval.waiting.size == 1 }

        rig.model.begin(other.pairingOffer().uri)

        assertEquals(PairingModel.Step.Confirm("Mac mini"), rig.model.step.value, "a new link always asks first")
        confirming.join()
        assertEquals(PairingModel.Step.Confirm("Mac mini"), rig.model.step.value)
        assertEquals(1, rig.approval.cancelled)
        assertTrue(rig.hub.machines.isEmpty())
    } }

    // Android (Review Focus 1, review 1 M-3)

    /** The screen went away while the Mac was asked: the Mac's Allow still pairs it. */
    @Test fun cancellingTheCallerOfConfirmStillSavesTheMac() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val rig = pairingRig(listOf(mac))
        rig.relay.setApprovalDelay(1.seconds)
        rig.model.begin(mac.pairingCode())
        val caller = launch { rig.model.confirm() }
        assertTrue(eventually { rig.approval.waiting.size == 1 })
        caller.cancelAndJoin() // the screen went away
        rig.approval.release()
        assertTrue(eventually { rig.model.step.value == PairingModel.Step.Paired("MacBook Pro") })
        assertEquals(listOf(mac.machine), rig.vault.machines())
        assertTrue(eventually { rig.hub.machines.singleOrNull()?.state == MachineLinkState.Online })
    } }

    /** A relay call that throws a CancellationException of its own (nobody cancelled) fails the attempt, instead of
     *  leaving the sheet waiting for the Mac forever. */
    @Test fun aPairCallThatCancelsItselfFails() { runTest {
        val mac = FakeMac("MacBook Pro", backgroundScope)
        val rig = pairingRig(listOf(mac)) { base ->
            object : RelayAccountCalling by base {
                override suspend fun pair(offerUri: String, clientKey: ByteArray, token: String): PairedMachine =
                    throw CancellationException("own")
            }
        }
        rig.model.begin(mac.pairingCode())

        rig.model.confirm()

        assertEquals(PairingModel.Step.Failed(PairingFailure.Server("unknown")), rig.model.step.value)
        assertTrue(rig.hub.machines.isEmpty())
    } }
}
