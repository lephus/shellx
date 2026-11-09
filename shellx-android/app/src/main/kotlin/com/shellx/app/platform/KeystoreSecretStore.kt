package com.shellx.app.platform

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import androidx.annotation.RequiresApi
import com.shellx.core.account.SecretItem
import com.shellx.core.account.SecretStore
import com.shellx.core.account.SecretStoreException
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.InvalidKeyException
import java.security.KeyStore
import java.security.KeyStoreException
import java.security.ProviderException
import java.security.UnrecoverableKeyException
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** The Keystore key the store encrypts with. Throws KeyStoreException, ProviderException or GeneralSecurityException. */
fun interface SecretKeyProvider {
    fun key(): SecretKey
}

/** AES-256-GCM key in the Android Keystore: non-exportable, no user authentication, made on first use. Synchronized. */
class AndroidKeystoreKey(private val alias: String = ALIAS) : SecretKeyProvider {
    @Synchronized
    override fun key(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keyStore.getKey(alias, null) as SecretKey?)?.let { return it }
        val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).apply { init(spec) }.generateKey()
    }

    companion object {
        const val ALIAS = "shellx.secrets.v1"
        private const val KEYSTORE = "AndroidKeyStore"
    }
}

/**
 * SecretStore over the Keystore (S3 §7.3; the iPhone's KeychainSecretStore): one file per item in [directory], never
 * backed up. Blocking; 3C's AccountVault calls it on its io dispatcher.
 *
 * A file is `0x01` (format version) ‖ IV (12 bytes) ‖ AES-GCM ciphertext with its 16-byte tag, sealed with the AAD
 * `shellx-secret/1/<item.account>`, so a file copied onto another item does not open.
 *
 * A read that fails never deletes secrets on an error that may pass (review A I-2; ledger A-19). Deleting loses the
 * phone's Link key too, so every Mac would have to be paired again.
 * - **Lost** (the file is deleted and reads as absent, which signs the user out instead of locking them out): a damaged
 *   file, `AEADBadTagException` (the key alias was gone and a new key was made), `KeyPermanentlyInvalidatedException`,
 *   and on API 33+ an `android.security.KeyStoreException` that will not pass (`ERROR_KEY_DOES_NOT_EXIST`,
 *   `ERROR_KEY_CORRUPTED`, or any error that is neither transient nor a system or authentication error).
 * - **Busy** ([SecretStoreException.Unavailable], the file stays; the launch screen waits for the next start): on API
 *   33+ a transient `android.security.KeyStoreException` (or one whose retry policy is not RETRY_NEVER), and
 *   `java.security.KeyStoreException`, `ProviderException` or an `IOException` from the key.
 * - **Unclear** (Unavailable, the file stays, until [LOST_AFTER_STARTS] app starts in a row saw the item fail so; then
 *   lost): `UnrecoverableKeyException` and `InvalidKeyException` that carry no deciding `android.security.KeyStoreException`
 *   (always before API 33), and on API 33+ a Keystore system or authentication error. A broken key cannot hold the
 *   launch screen forever. The count lives in `<item.account>.failures` next to the item; a successful read or write
 *   resets it.
 * - Anything else is [SecretStoreException.Failed], and the file stays.
 *
 * One store per process: it counts at most one unclear failure per item per app start.
 */
class KeystoreSecretStore(
    private val directory: File,
    private val keys: SecretKeyProvider = AndroidKeystoreKey(),
    /** Build.VERSION.SDK_INT; tests pass an older level to reach the API 26–32 rules on Robolectric's SDK 35. */
    private val sdkInt: Int = Build.VERSION.SDK_INT,
) : SecretStore {
    private enum class Failure { LOST, BUSY, UNCLEAR, OTHER }

    /** Items whose unclear failure this app start has counted already. */
    private val countedThisStart = mutableSetOf<SecretItem>()

    private fun file(item: SecretItem) = File(directory, "${item.account}.bin")

    private fun counter(item: SecretItem) = File(directory, "${item.account}.failures")

    private fun aad(item: SecretItem) = "$AAD_PREFIX${item.account}".toByteArray(Charsets.UTF_8)

    @Synchronized
    override fun read(item: SecretItem): ByteArray? {
        val file = file(item)
        if (!file.exists()) return null
        val bytes = try {
            file.readBytes()
        } catch (e: IOException) {
            throw SecretStoreException.Unavailable(e)
        }
        if (bytes.size < MIN_SIZE || bytes[0] != VERSION) return discard(item)
        val plain = try {
            val key = keys.key()
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, bytes, 1, IV_SIZE))
            cipher.updateAAD(aad(item))
            cipher.doFinal(bytes, 1 + IV_SIZE, bytes.size - 1 - IV_SIZE)
        } catch (e: Exception) {
            return when (classify(e)) {
                Failure.LOST -> discard(item)
                Failure.BUSY -> throw SecretStoreException.Unavailable(e)
                Failure.UNCLEAR -> if (countUnclearFailure(item) >= LOST_AFTER_STARTS) {
                    discard(item)
                } else {
                    throw SecretStoreException.Unavailable(e)
                }
                Failure.OTHER -> throw SecretStoreException.Failed(e)
            }
        }
        resetCount(item)
        return plain
    }

    private fun classify(error: Exception): Failure {
        val chain = generateSequence<Throwable>(error) { it.cause }.take(8).toList()
        if (error is AEADBadTagException || chain.any { it is KeyPermanentlyInvalidatedException }) return Failure.LOST
        if (sdkInt >= 33) keystoreFailure(chain)?.let { return it }
        return when (error) {
            is KeyStoreException, is ProviderException, is IOException -> Failure.BUSY
            is UnrecoverableKeyException, is InvalidKeyException -> Failure.UNCLEAR
            else -> Failure.OTHER
        }
    }

    /** What keystore2's own error says, when the platform passed one on (API 33+). */
    @RequiresApi(33)
    private fun keystoreFailure(chain: List<Throwable>): Failure? {
        val error = chain.firstNotNullOfOrNull { it as? android.security.KeyStoreException } ?: return null
        return when {
            error.isTransientFailure || error.retryPolicy != android.security.KeyStoreException.RETRY_NEVER -> Failure.BUSY
            error.numericErrorCode == android.security.KeyStoreException.ERROR_KEY_DOES_NOT_EXIST ||
                error.numericErrorCode == android.security.KeyStoreException.ERROR_KEY_CORRUPTED -> Failure.LOST
            error.isSystemError || error.requiresUserAuthentication() -> Failure.UNCLEAR
            else -> Failure.LOST
        }
    }

    /** Counts this app start's unclear failure of [item] once, and returns the starts in a row that saw one. */
    private fun countUnclearFailure(item: SecretItem): Int {
        val counter = counter(item)
        val seen = try {
            counter.readText().trim().toInt()
        } catch (e: Exception) {
            0
        }
        if (!countedThisStart.add(item)) return seen
        val count = seen + 1
        try {
            counter.writeText("$count")
        } catch (e: IOException) {
            // Not counted: the item stays unavailable, which keeps the secrets.
        }
        return count
    }

    private fun resetCount(item: SecretItem) {
        countedThisStart.remove(item)
        val counter = counter(item)
        if (counter.exists()) counter.delete()
    }

    @Synchronized
    override fun write(data: ByteArray, item: SecretItem) {
        val file = file(item)
        val temporary = File(directory, "${item.account}.tmp")
        try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, keys.key()) // the provider picks the IV
            cipher.updateAAD(aad(item))
            val sealed = cipher.doFinal(data)
            val iv = cipher.iv
            check(iv.size == IV_SIZE) { "unexpected IV size" }
            directory.mkdirs()
            FileOutputStream(temporary).use { out ->
                out.write(byteArrayOf(VERSION))
                out.write(iv)
                out.write(sealed)
                out.fd.sync()
            }
            if (!temporary.renameTo(file)) throw IOException("rename failed")
        } catch (e: Exception) {
            temporary.delete()
            throw SecretStoreException.Failed(e)
        }
        // A fresh, healthy item: unclear failures of the old one never count against it (re-review A).
        resetCount(item)
    }

    @Synchronized
    override fun delete(item: SecretItem) {
        val file = file(item)
        if (!file.delete() && file.exists()) throw SecretStoreException.Failed(IOException("delete failed"))
        resetCount(item)
    }

    /** The item can never be read again: delete it, so it reads as absent. */
    private fun discard(item: SecretItem): ByteArray? {
        file(item).delete()
        resetCount(item)
        return null
    }

    companion object {
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val AAD_PREFIX = "shellx-secret/1/"
        private const val VERSION: Byte = 0x01
        private const val IV_SIZE = 12
        private const val TAG_BITS = 128
        private const val MIN_SIZE = 1 + IV_SIZE + TAG_BITS / 8 // 29: version, IV and an empty secret's tag

        /** App starts in a row with an unclear failure of one item before it reads as lost (review A I-2 ruling). */
        const val LOST_AFTER_STARTS = 3

        fun directory(context: Context): File = File(context.noBackupFilesDir, "secrets")
    }
}
