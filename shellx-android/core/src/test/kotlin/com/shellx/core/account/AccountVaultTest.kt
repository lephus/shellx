package com.shellx.core.account

import com.shellx.core.testing.InMemorySecretStore
import com.shellx.link.account.PairedMachine
import java.util.Collections
import java.util.concurrent.Executors
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class AccountVaultTest {
    private fun machine(id: String): PairedMachine = PairedMachine(id, "Mac $id", "slot-$id", ByteArray(32) { 7 })

    @Test fun phoneKeyCreatedOnceAndReused() { runTest {
        val store = InMemorySecretStore()
        val vault = AccountVault(store, StandardTestDispatcher(testScheduler))
        val first = vault.phoneKey()
        val second = vault.phoneKey()
        assertContentEquals(first.publicKey, second.publicKey)
        assertEquals(32, first.rawPrivate.size)
        assertEquals(1, store.writeCount(SecretItem.PHONE_KEY))

        // A new vault over the same store (a relaunch) restores the same key.
        val relaunched = AccountVault(store, StandardTestDispatcher(testScheduler)).phoneKey()
        assertContentEquals(first.publicKey, relaunched.publicKey)
        assertEquals(1, store.writeCount(SecretItem.PHONE_KEY))
    } }

    @Test fun sessionRoundTripAndRedactedDescription() { runTest {
        val vault = AccountVault(InMemorySecretStore(), StandardTestDispatcher(testScheduler))
        val initial = vault.session()
        assertNull(initial)
        val session = StoredSession("u1", "d1", "tok-secret", "a@b.c")
        vault.setSession(session)
        val stored = vault.session()
        assertEquals(session, stored)
        assertFalse("$session".contains("tok-secret"))
        assertFalse(listOf(session).toString().contains("tok-secret"))
        vault.clearSession()
        val cleared = vault.session()
        assertNull(cleared)
    } }

    @Test fun machinesRoundTripWithOwner() { runTest {
        val store = InMemorySecretStore()
        val vault = AccountVault(store, StandardTestDispatcher(testScheduler))
        val none = vault.machines()
        val noOwner = vault.machinesOwner()
        assertEquals(emptyList(), none)
        assertNull(noOwner)

        vault.setMachines(listOf(machine("a"), machine("b")), "u1")
        val machines = vault.machines()
        val owner = vault.machinesOwner()
        assertEquals(listOf(machine("a"), machine("b")), machines)
        assertEquals("u1", owner)

        val raw = assertNotNull(store.read(SecretItem.MACHINES))
        val json = Json.parseToJsonElement(raw.decodeToString()).jsonObject
        assertEquals(1, json["version"]?.jsonPrimitive?.int)
        assertEquals("u1", json["owner"]?.jsonPrimitive?.content)
        assertEquals(2, json["machines"]?.jsonArray?.size)
    } }

    @Test fun wipeRemovesEveryItem() { runTest {
        val store = InMemorySecretStore()
        val vault = AccountVault(store, StandardTestDispatcher(testScheduler))
        vault.setSession(StoredSession("u", "d", "t", "e"))
        vault.phoneKey()
        vault.setMachines(listOf(machine("a")), "u")
        vault.wipe()
        for (item in SecretItem.entries) {
            assertNull(store.read(item), "$item survived the wipe")
        }
    } }

    @Test fun unavailableSurfaces() { runTest {
        val store = InMemorySecretStore()
        store.failReads = SecretStoreException.Unavailable()
        val vault = AccountVault(store, StandardTestDispatcher(testScheduler))
        assertIs<SecretStoreException.Unavailable>(assertFails { vault.session() })
        assertIs<SecretStoreException.Unavailable>(assertFails { vault.phoneKey() })
        assertEquals(0, store.writeCount(SecretItem.PHONE_KEY), "an unreadable store must not get a fresh key")
    } }

    @Test fun storeWorkRunsOnTheIoDispatcher() {
        val executor = Executors.newSingleThreadExecutor { Thread(it, "vault-io") }
        val io = executor.asCoroutineDispatcher()
        try {
            runBlocking {
                val threads = Collections.synchronizedSet(mutableSetOf<String>())
                val inner = InMemorySecretStore()
                val store = object : SecretStore {
                    override fun read(item: SecretItem) = inner.read(item).also { threads += Thread.currentThread().name }
                    override fun write(data: ByteArray, item: SecretItem) { threads += Thread.currentThread().name; inner.write(data, item) }
                    override fun delete(item: SecretItem) { threads += Thread.currentThread().name; inner.delete(item) }
                }
                val vault = AccountVault(store, io)
                vault.setSession(StoredSession("u", "d", "t", "e")); vault.session(); vault.phoneKey()
                vault.setMachines(emptyList(), "u"); vault.machines(); vault.wipe()
                assertEquals(setOf("vault-io"), threads.toSet())
            }
        } finally { io.close() }
    }
}
