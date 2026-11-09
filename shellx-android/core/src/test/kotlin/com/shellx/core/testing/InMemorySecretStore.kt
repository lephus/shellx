package com.shellx.core.testing

import com.shellx.core.account.SecretItem
import com.shellx.core.account.SecretStore
import com.shellx.core.account.SecretStoreException

/** A SecretStore in memory, for tests. Each operation can be made to fail. Thread-safe. */
class InMemorySecretStore : SecretStore {
    private val lock = Any()
    private val items = HashMap<SecretItem, ByteArray>()
    private val writes = HashMap<SecretItem, Int>()

    @Volatile var failReads: SecretStoreException? = null

    @Volatile var failWrites: SecretStoreException? = null

    @Volatile var failDeletes: SecretStoreException? = null

    /** How many times [item] was written successfully. */
    fun writeCount(item: SecretItem): Int = synchronized(lock) { writes[item] ?: 0 }

    override fun read(item: SecretItem): ByteArray? = synchronized(lock) {
        failReads?.let { throw it }
        items[item]?.copyOf()
    }

    override fun write(data: ByteArray, item: SecretItem) {
        synchronized(lock) {
            failWrites?.let { throw it }
            items[item] = data.copyOf()
            writes[item] = (writes[item] ?: 0) + 1
        }
    }

    override fun delete(item: SecretItem) {
        synchronized(lock) {
            failDeletes?.let { throw it }
            items.remove(item)
        }
    }
}
