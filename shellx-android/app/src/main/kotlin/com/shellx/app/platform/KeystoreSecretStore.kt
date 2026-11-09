package com.shellx.app.platform

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.shellx.core.account.SecretItem
import com.shellx.core.account.SecretStore
import com.shellx.core.account.SecretStoreException
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.GeneralSecurityException
import java.security.InvalidKeyException
import java.security.KeyStore
import java.security.KeyStoreException
import java.security.ProviderException
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
 * `shellx-secret/1/<item.account>`, so a file copied onto another item does not open. A file that can no longer be
 * opened (the key was lost or replaced, the file is damaged) is deleted and reads as absent: a lost key signs the user
 * out instead of locking them out. A Keystore that is busy reads as [SecretStoreException.Unavailable] and keeps the file.
 */
class KeystoreSecretStore(
    private val directory: File,
    private val keys: SecretKeyProvider = AndroidKeystoreKey(),
) : SecretStore {
    private fun file(item: SecretItem) = File(directory, "${item.account}.bin")

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
        if (bytes.size < MIN_SIZE || bytes[0] != VERSION) return discard(file)
        val key = try {
            keys.key()
        } catch (e: KeyStoreException) {
            throw SecretStoreException.Unavailable(e)
        } catch (e: ProviderException) {
            throw SecretStoreException.Unavailable(e)
        } catch (e: GeneralSecurityException) {
            return discard(file) // UnrecoverableKeyException and the like: this file will never open
        }
        val cipher = try {
            Cipher.getInstance(TRANSFORMATION)
        } catch (e: GeneralSecurityException) {
            throw SecretStoreException.Failed(e)
        }
        return try {
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, bytes, 1, IV_SIZE))
            cipher.updateAAD(aad(item))
            cipher.doFinal(bytes, 1 + IV_SIZE, bytes.size - 1 - IV_SIZE)
        } catch (e: AEADBadTagException) {
            discard(file)
        } catch (e: InvalidKeyException) {
            discard(file) // KeyPermanentlyInvalidatedException included
        } catch (e: ProviderException) {
            throw SecretStoreException.Unavailable(e)
        } catch (e: GeneralSecurityException) {
            throw SecretStoreException.Failed(e)
        }
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
    }

    @Synchronized
    override fun delete(item: SecretItem) {
        val file = file(item)
        if (!file.delete() && file.exists()) throw SecretStoreException.Failed(IOException("delete failed"))
    }

    private fun discard(file: File): ByteArray? {
        file.delete()
        return null
    }

    companion object {
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val AAD_PREFIX = "shellx-secret/1/"
        private const val VERSION: Byte = 0x01
        private const val IV_SIZE = 12
        private const val TAG_BITS = 128
        private const val MIN_SIZE = 1 + IV_SIZE + TAG_BITS / 8 // 29: version, IV and an empty secret's tag

        fun directory(context: Context): File = File(context.noBackupFilesDir, "secrets")
    }
}
