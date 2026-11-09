package com.shellx.core.demo

import com.shellx.core.account.SecretItem
import com.shellx.core.account.SecretStore

/** The demo's secrets, in memory only: nothing reaches the Keystore. Thread-safe. */
class DemoSecretStore : SecretStore {
    private val lock = Any()
    private val items = HashMap<SecretItem, ByteArray>()

    override fun read(item: SecretItem): ByteArray? = synchronized(lock) { items[item]?.copyOf() }

    override fun write(data: ByteArray, item: SecretItem) {
        synchronized(lock) { items[item] = data.copyOf() }
    }

    override fun delete(item: SecretItem) {
        synchronized(lock) { items.remove(item) }
    }
}
