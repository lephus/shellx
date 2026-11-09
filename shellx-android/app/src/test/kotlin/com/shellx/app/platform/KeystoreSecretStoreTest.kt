package com.shellx.app.platform

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.account.SecretItem
import com.shellx.core.account.SecretStoreException
import java.io.File
import java.security.KeyStoreException
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
        val busy = KeystoreSecretStore(folder.root) { throw KeyStoreException("busy") }
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
}
