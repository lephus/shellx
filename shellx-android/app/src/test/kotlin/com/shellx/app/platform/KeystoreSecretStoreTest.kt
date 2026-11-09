package com.shellx.app.platform

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import android.security.keystore.KeyPermanentlyInvalidatedException
import com.shellx.core.account.SecretItem
import com.shellx.core.account.SecretStoreException
import java.io.File
import java.security.InvalidKeyException
import java.security.KeyStoreException
import java.security.UnrecoverableKeyException
import javax.crypto.KeyGenerator
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith

/** Port of KeychainSecretStoreTests, plus the Android file scheme (S3 §7.3; review focus 4). */
@RunWith(AndroidJUnit4::class)
class KeystoreSecretStoreTest {
    @get:Rule val folder = TemporaryFolder()

    private fun memoryKey(): SecretKeyProvider {
        val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        return SecretKeyProvider { key }
    }

    private val keyA = memoryKey()
    private val store by lazy { KeystoreSecretStore(folder.root, keyA) }

    private fun file(item: SecretItem) = File(folder.root, "${item.account}.bin")

    @Test
    fun writeReadDeleteRoundTrips() {
        assertNull(store.read(SecretItem.SESSION))
        store.write("one".toByteArray(), SecretItem.SESSION)
        assertArrayEquals("one".toByteArray(), store.read(SecretItem.SESSION))
        store.write("two".toByteArray(), SecretItem.SESSION)
        assertArrayEquals("two".toByteArray(), store.read(SecretItem.SESSION))
        store.delete(SecretItem.SESSION)
        assertNull(store.read(SecretItem.SESSION))
        store.delete(SecretItem.SESSION)
    }

    @Test
    fun filesAreEncryptedAndBoundToTheirItem() {
        store.write("token-secret".toByteArray(), SecretItem.SESSION)
        val bytes = file(SecretItem.SESSION).readBytes()
        assertFalse(String(bytes, Charsets.ISO_8859_1).contains("token-secret"))
        file(SecretItem.SESSION).copyTo(file(SecretItem.PHONE_KEY))
        assertNull(store.read(SecretItem.PHONE_KEY))
        assertFalse(file(SecretItem.PHONE_KEY).exists())
        assertArrayEquals("token-secret".toByteArray(), store.read(SecretItem.SESSION))
    }

    @Test
    fun aLostKeyReadsAsAbsentAndDeletesTheFile() {
        store.write("one".toByteArray(), SecretItem.SESSION)
        val other = KeystoreSecretStore(folder.root, memoryKey())
        assertNull(other.read(SecretItem.SESSION))
        assertFalse(file(SecretItem.SESSION).exists())
        other.write("two".toByteArray(), SecretItem.SESSION)
        assertArrayEquals("two".toByteArray(), other.read(SecretItem.SESSION))
    }

    @Test
    fun aBusyKeystoreIsUnavailableAndKeepsTheFile() {
        store.write("one".toByteArray(), SecretItem.SESSION)
        val busy = KeystoreSecretStore(folder.root, SecretKeyProvider { throw KeyStoreException("busy") })
        val read = assertThrows(SecretStoreException.Unavailable::class.java) { busy.read(SecretItem.SESSION) }
        assertEquals("unavailable", read.message)
        assertTrue(file(SecretItem.SESSION).exists())
        val write = assertThrows(SecretStoreException.Failed::class.java) { busy.write("two".toByteArray(), SecretItem.SESSION) }
        assertEquals("failed", write.message)
        assertArrayEquals("one".toByteArray(), store.read(SecretItem.SESSION))
    }

    @Test
    fun aDamagedFileReadsAsAbsent() {
        store.write("one".toByteArray(), SecretItem.SESSION)
        val bytes = file(SecretItem.SESSION).readBytes()
        bytes[bytes.size - 1] = (bytes[bytes.size - 1].toInt() xor 1).toByte()
        file(SecretItem.SESSION).writeBytes(bytes)
        assertNull(store.read(SecretItem.SESSION))
        assertFalse(file(SecretItem.SESSION).exists())

        file(SecretItem.SESSION).writeBytes(ByteArray(10) { 1 })
        assertNull(store.read(SecretItem.SESSION))
        assertFalse(file(SecretItem.SESSION).exists())

        store.write("one".toByteArray(), SecretItem.SESSION)
        val versioned = file(SecretItem.SESSION).readBytes().also { it[0] = 2 }
        file(SecretItem.SESSION).writeBytes(versioned)
        assertNull(store.read(SecretItem.SESSION))
        assertFalse(file(SecretItem.SESSION).exists())
    }

    @Test
    fun noTemporaryFileStays() {
        store.write("one".toByteArray(), SecretItem.SESSION)
        assertEquals(listOf("session.bin"), folder.root.list()!!.toList())
    }

    @Test
    fun theDirectoryIsNotBackedUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        assertEquals(File(context.noBackupFilesDir, "secrets"), KeystoreSecretStore.directory(context))
    }

    // Review A I-2: which Keystore errors lose the secrets and which only wait. The platform wraps keystore2's errors in
    // android.security.KeyStoreException (API 33+), the cause of an UnrecoverableKeyException from getKey and of an
    // InvalidKeyException from Cipher.init.

    /** android.security.KeyStoreException(int, String) is hidden; Robolectric's SDK 35 has it. */
    private fun keystoreError(matches: (android.security.KeyStoreException) -> Boolean): android.security.KeyStoreException {
        val make = android.security.KeyStoreException::class.java.getConstructor(Int::class.javaPrimitiveType, String::class.java)
        return (-100..100).asSequence().map { make.newInstance(it, "keystore2") }.first(matches)
    }

    private val transient by lazy { keystoreError { it.isTransientFailure } }
    private val keyGone by lazy {
        keystoreError {
            it.numericErrorCode == android.security.KeyStoreException.ERROR_KEY_DOES_NOT_EXIST && !it.isTransientFailure &&
                it.retryPolicy == android.security.KeyStoreException.RETRY_NEVER && !it.isSystemError
        }
    }
    private val systemError by lazy {
        keystoreError { it.isSystemError && !it.isTransientFailure && it.retryPolicy == android.security.KeyStoreException.RETRY_NEVER }
    }

    private fun failing(error: () -> Exception) = SecretKeyProvider { throw error() }

    private fun written(item: SecretItem = SecretItem.SESSION): File {
        store.write("one".toByteArray(), item)
        return file(item)
    }

    @Test
    fun aPermanentlyInvalidatedKeyReadsAsAbsentAndDeletesTheFile() {
        val file = written()
        assertNull(KeystoreSecretStore(folder.root, failing { KeyPermanentlyInvalidatedException("x") }).read(SecretItem.SESSION))
        assertFalse(file.exists())
    }

    @Test
    fun aKeystoreErrorThatWillNotPassReadsAsAbsent() {
        val file = written()
        val lost = failing { UnrecoverableKeyException("Failed to obtain information about key").apply { initCause(keyGone) } }
        assertNull(KeystoreSecretStore(folder.root, lost).read(SecretItem.SESSION))
        assertFalse(file.exists())
    }

    @Test
    fun aTransientKeystoreErrorIsUnavailableAndKeepsTheFile() {
        val file = written()
        for (error in listOf<() -> Exception>(
            { UnrecoverableKeyException("Failed to obtain information about key").apply { initCause(transient) } },
            { InvalidKeyException("Keystore operation failed", transient) },
        )) {
            repeat(4) { // every start: a transient error never runs out
                val busy = KeystoreSecretStore(folder.root, failing(error))
                val thrown = assertThrows(SecretStoreException.Unavailable::class.java) { busy.read(SecretItem.SESSION) }
                assertEquals("unavailable", thrown.message)
            }
            assertTrue(file.exists())
        }
        assertArrayEquals("one".toByteArray(), store.read(SecretItem.SESSION))
    }

    @Test
    fun beforeApi33AnUnclearKeyErrorIsUnavailableUntilTheThirdStart() {
        val file = written()
        val unclear = failing { UnrecoverableKeyException("Failed to obtain information about key") }
        for (start in 1..2) {
            val store = KeystoreSecretStore(folder.root, unclear, sdkInt = 32)
            repeat(2) { assertThrows(SecretStoreException.Unavailable::class.java) { store.read(SecretItem.SESSION) } }
            assertTrue("start $start", file.exists())
        }
        assertNull(KeystoreSecretStore(folder.root, unclear, sdkInt = 32).read(SecretItem.SESSION))
        assertFalse(file.exists())
        assertEquals(emptyList<String>(), folder.root.list()!!.toList())

        val machines = written(SecretItem.MACHINES)
        val invalid = KeystoreSecretStore(folder.root, failing { InvalidKeyException("Keystore operation failed") }, sdkInt = 32)
        assertThrows(SecretStoreException.Unavailable::class.java) { invalid.read(SecretItem.MACHINES) }
        assertTrue(machines.exists())
    }

    @Test
    fun aSuccessfulReadStartsTheCountAgain() {
        val file = written()
        val unclear = failing { InvalidKeyException("Keystore operation failed") }
        repeat(2) { assertThrows(SecretStoreException.Unavailable::class.java) { KeystoreSecretStore(folder.root, unclear, sdkInt = 32).read(SecretItem.SESSION) } }
        assertArrayEquals("one".toByteArray(), KeystoreSecretStore(folder.root, keyA, sdkInt = 32).read(SecretItem.SESSION))
        repeat(2) { assertThrows(SecretStoreException.Unavailable::class.java) { KeystoreSecretStore(folder.root, unclear, sdkInt = 32).read(SecretItem.SESSION) } }
        assertTrue(file.exists())
        assertNull(KeystoreSecretStore(folder.root, unclear, sdkInt = 32).read(SecretItem.SESSION))
        assertFalse(file.exists())
    }

    @Test
    fun aKeystoreSystemErrorIsUnclearToo() {
        val file = written()
        val system = failing { InvalidKeyException("Keystore operation failed", systemError) }
        repeat(2) { assertThrows(SecretStoreException.Unavailable::class.java) { KeystoreSecretStore(folder.root, system).read(SecretItem.SESSION) } }
        assertTrue(file.exists())
        assertNull(KeystoreSecretStore(folder.root, system).read(SecretItem.SESSION))
        assertFalse(file.exists())
    }
}
