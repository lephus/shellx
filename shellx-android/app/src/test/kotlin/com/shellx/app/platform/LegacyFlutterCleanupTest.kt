package com.shellx.app.platform

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.platform.MemoryKeyValueStore
import java.io.File
import java.security.KeyStoreException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LegacyFlutterCleanupTest {
    @get:Rule val folder = TemporaryFolder()

    private class FakeAliases(private val aliases: List<String>, private val failList: Boolean = false) : KeystoreAliases {
        val deleted = mutableListOf<String>()

        override fun list(): List<String> {
            if (failList) throw KeyStoreException("busy")
            return aliases
        }

        override fun delete(alias: String) {
            deleted += alias
        }
    }

    private fun write(path: String) = File(folder.root, path).apply { parentFile!!.mkdirs(); writeText("x") }

    private fun leftovers() {
        write("app_flutter/state.json")
        write("shared_prefs/FlutterSharedPreferences.xml")
        write("shared_prefs/FlutterSecureStorage.xml")
        write("shared_prefs/com.google.firebase.messaging.xml")
        write("files/keep.txt")
    }

    @Test
    fun theFlutterAppsDataGoesOnce() {
        leftovers()
        val settings = MemoryKeyValueStore()
        val keystore = FakeAliases(listOf("com.shellx.prod.FlutterSecureStoragePluginKey", "shellx.secrets.v1", "other"))
        assertTrue(LegacyFlutterCleanup.run(folder.root, settings, keystore))
        assertFalse(File(folder.root, "app_flutter").exists())
        assertFalse(File(folder.root, "shared_prefs/FlutterSharedPreferences.xml").exists())
        assertFalse(File(folder.root, "shared_prefs/FlutterSecureStorage.xml").exists())
        assertTrue(File(folder.root, "shared_prefs/com.google.firebase.messaging.xml").exists())
        assertTrue(File(folder.root, "files/keep.txt").exists())
        assertEquals(listOf("com.shellx.prod.FlutterSecureStoragePluginKey"), keystore.deleted)
        assertTrue(settings.getBoolean(LegacyFlutterCleanup.DONE_KEY))

        write("app_flutter/state.json")
        assertTrue(LegacyFlutterCleanup.run(folder.root, settings, keystore))
        assertTrue(File(folder.root, "app_flutter/state.json").exists())
        assertEquals(1, keystore.deleted.size)
    }

    @Test
    fun aFailureLeavesTheMarkOff() {
        leftovers()
        val settings = MemoryKeyValueStore()
        assertFalse(LegacyFlutterCleanup.run(folder.root, settings, FakeAliases(emptyList(), failList = true)))
        assertFalse(File(folder.root, "app_flutter").exists())
        assertFalse(File(folder.root, "shared_prefs/FlutterSharedPreferences.xml").exists())
        assertFalse(File(folder.root, "shared_prefs/FlutterSecureStorage.xml").exists())
        assertFalse(settings.getBoolean(LegacyFlutterCleanup.DONE_KEY))
    }
}
