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

    private val sessionBeforeAuthMethods = """{"userID":"u1","deviceID":"d1","token":"t","email":"a@b.c"}"""

    @Test fun aSessionStoredBeforeAuthMethodsIsAGoogleSession() { runTest {
        val store = InMemorySecretStore()
        store.write(sessionBeforeAuthMethods.encodeToByteArray(), SecretItem.SESSION)
        val session = AccountVault(store, StandardTestDispatcher(testScheduler)).session()
        assertEquals(StoredSession("u1", "d1", "t", "a@b.c", AccountAuthMethod.GOOGLE), session)
        assertEquals(AccountAuthMethod.GOOGLE, StoredSession("u1", "d1", "t", "a@b.c").authMethod)
    } }

    @Test fun theAuthMethodIsStoredUnderTheIPhonesKey() { runTest {
        val store = InMemorySecretStore()
        val vault = AccountVault(store, StandardTestDispatcher(testScheduler))
        val session = StoredSession("u1", "d1", "t", "a@b.c", AccountAuthMethod.EMAIL)
        vault.setSession(session)

        val raw = assertNotNull(store.read(SecretItem.SESSION))
        val json = Json.parseToJsonElement(raw.decodeToString()).jsonObject
        assertEquals("email", json["auth_method"]?.jsonPrimitive?.content)
        assertEquals(true, json["auth_method"]?.jsonPrimitive?.isString)
        assertEquals("u1", json["userID"]?.jsonPrimitive?.content)
        assertEquals("d1", json["deviceID"]?.jsonPrimitive?.content)
        assertEquals("t", json["token"]?.jsonPrimitive?.content)
        assertEquals("a@b.c", json["email"]?.jsonPrimitive?.content)
        assertEquals(listOf("userID", "deviceID", "token", "email", "auth_method"), json.keys.toList())
        val stored = vault.session()
        assertEquals(session, stored)

        // A Google session says so too.
        vault.setSession(StoredSession("u1", "d1", "t", "a@b.c"))
        val google = Json.parseToJsonElement(assertNotNull(store.read(SecretItem.SESSION)).decodeToString()).jsonObject
        assertEquals("google", google["auth_method"]?.jsonPrimitive?.content)
        assertEquals(listOf("google", "email"), AccountAuthMethod.entries.map { it.wire })
        assertEquals(AccountAuthMethod.EMAIL, AccountAuthMethod.ofWire("email"))
        assertNull(AccountAuthMethod.ofWire("apple"))
    } }

    @Test fun anUnknownAuthMethodIsUnreadable() { runTest {
        for (method in listOf("\"passkey\"", "7", "null")) {
            val store = InMemorySecretStore()
            val raw = sessionBeforeAuthMethods.dropLast(1) + ""","auth_method":$method}"""
            store.write(raw.encodeToByteArray(), SecretItem.SESSION)
            val session = AccountVault(store, StandardTestDispatcher(testScheduler)).session()
            assertNull(session, raw.substringAfter("auth_method"))
        }
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
                // Under -ea, kotlinx-coroutines' debug mode appends " @coroutine#N" to the name while a coroutine runs.
                fun thread() = Thread.currentThread().name.substringBefore(" @coroutine#")
                val inner = InMemorySecretStore()
                val store = object : SecretStore {
                    override fun read(item: SecretItem) = inner.read(item).also { threads += thread() }
                    override fun write(data: ByteArray, item: SecretItem) { threads += thread(); inner.write(data, item) }
                    override fun delete(item: SecretItem) { threads += thread(); inner.delete(item) }
                }
                val vault = AccountVault(store, io)
                vault.setSession(StoredSession("u", "d", "t", "e")); vault.session(); vault.phoneKey()
                vault.setMachines(emptyList(), "u"); vault.machines(); vault.wipe()
                assertEquals(setOf("vault-io"), threads.toSet())
            }
        } finally { io.close() }
    }
}
