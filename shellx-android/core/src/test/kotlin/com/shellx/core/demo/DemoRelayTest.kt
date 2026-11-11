package com.shellx.core.demo

import com.shellx.core.account.SecretItem
import com.shellx.core.testing.assertSameCase
import com.shellx.link.account.PairedMachine
import com.shellx.link.account.RelayApiException
import com.shellx.link.core.PairingOffer
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertNull
import kotlin.time.Duration
import kotlinx.coroutines.test.runTest

/** The demo's relay never reaches the network: it lists and pairs the demo Macs and refuses every account call. */
class DemoRelayTest {
    private val a = PairedMachine("mac-a", "Mac A", "slot-a", ByteArray(32) { 1 })

    private fun offer(id: String): PairingOffer = PairingOffer.make(id, "slot-$id", ByteArray(32) { 2 }, "Mac $id")

    @Test fun listsPairsAndUnpairsTheDemoMacs() { runTest {
        val relay = DemoRelay(listOf(a), setOf("mac-b"), Duration.ZERO)
        val first = relay.machines("demo-token")
        assertEquals(listOf("mac-a"), first.map { it.machineId })
        val paired = relay.pair(offer("mac-b").uri, ByteArray(32) { 3 }, "demo-token")
        assertEquals(PairedMachine("mac-b", "Mac mac-b", "slot-mac-b", ByteArray(32) { 2 }), paired)
        assertContentEquals(ByteArray(32) { 2 }, paired.hostKey)
        val both = relay.machines("demo-token")
        assertEquals(listOf("mac-a", "mac-b"), both.map { it.machineId })
        relay.unpair("grant-mac-a", "demo-token")
        val left = relay.machines("demo-token")
        assertEquals(listOf("mac-b"), left.map { it.machineId })
    } }

    @Test fun codesOfOtherMacsAreRefused() { runTest {
        val relay = DemoRelay(emptyList(), setOf("mac-b"), Duration.ZERO)
        assertSameCase(
            RelayApiException.Http(404, "machine_not_found"),
            assertFails { relay.pair(offer("mac-z").uri, ByteArray(32) { 3 }, "t") },
        )
    } }

    @Test fun everyAccountCallIsRefused() { runTest {
        val relay = DemoRelay(emptyList(), emptySet(), Duration.ZERO)
        val key = ByteArray(32) { 3 }
        val calls: List<Pair<String, suspend () -> Unit>> = listOf(
            "nonce" to { relay.nonce() },
            "signInWithGoogle" to { relay.signInWithGoogle("i", "n", "p", key) },
            "deleteAccount" to { relay.deleteAccount("i", "n", "t") },
            "requestEmailCode" to { relay.requestEmailCode("a@b.c", "en") },
            "signInWithEmailCode" to { relay.signInWithEmailCode("c", "123456", "p", key) },
            "deleteAccountWithEmailCode" to { relay.deleteAccountWithEmailCode("c", "123456", "t") },
        )
        for ((name, call) in calls) {
            assertSameCase(DemoRelay.REFUSAL, assertFails(name) { call() }, name)
        }
    } }

    @Test fun demoSecretsStayInMemory() {
        val store = DemoSecretStore()
        store.write("x".encodeToByteArray(), SecretItem.SESSION)
        assertContentEquals("x".encodeToByteArray(), store.read(SecretItem.SESSION))
        store.delete(SecretItem.SESSION)
        assertNull(store.read(SecretItem.SESSION))
    }
}
