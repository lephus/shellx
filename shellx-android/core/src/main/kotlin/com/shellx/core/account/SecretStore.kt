package com.shellx.core.account

/**
 * The three secrets the app keeps. [account] is the store's name for the item (the iPhone's Keychain account names).
 * Contracts §5: SecretStore is implemented by :app (3D), with an AES-GCM key in the Android Keystore, excluded from
 * backup.
 */
enum class SecretItem(val account: String) {
    SESSION("session"),
    PHONE_KEY("phone-key"),
    MACHINES("machines"),
}

sealed class SecretStoreException(message: String, cause: Throwable? = null) : Exception(message, cause) {
    /** The store cannot be read right now, but the data is still there: never treat it as missing. */
    class Unavailable(cause: Throwable? = null) : SecretStoreException("unavailable", cause)

    class Failed(cause: Throwable? = null) : SecretStoreException("failed", cause)
}

/**
 * Where secrets live: the Keystore-backed store in the app, memory in tests and the demo.
 *
 * Blocking calls; AccountVault calls them on its io dispatcher only. [read] returns null for an item that is absent,
 * or that can no longer be decrypted (the implementation deletes it first: a lost Keystore key must not lock the user
 * out). It throws [SecretStoreException.Unavailable] only while the data is still there but unreadable for now, and
 * [SecretStoreException.Failed] otherwise.
 */
interface SecretStore {
    fun read(item: SecretItem): ByteArray?

    fun write(data: ByteArray, item: SecretItem)

    fun delete(item: SecretItem)
}
