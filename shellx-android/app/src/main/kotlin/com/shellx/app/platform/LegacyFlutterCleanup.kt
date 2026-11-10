package com.shellx.app.platform

import com.shellx.core.platform.CoreLog
import com.shellx.core.platform.KeyValueStore
import java.io.File
import java.security.KeyStore

/** The Keystore's aliases, behind a seam for tests. */
interface KeystoreAliases {
    fun list(): List<String>

    fun delete(alias: String)
}

/** The app's own entries in the Android Keystore. */
object AndroidKeystoreAliases : KeystoreAliases {
    private fun keyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    override fun list(): List<String> = keyStore().aliases().toList()

    override fun delete(alias: String) = keyStore().deleteEntry(alias)
}

/**
 * S3 §3: the native app replaces the Flutter app under the same app id and reads none of its data. The first launch
 * deletes what it left: `app_flutter/`, `shared_prefs/Flutter*` and its Keystore aliases. Blocking: run it on io.
 */
object LegacyFlutterCleanup {
    const val DONE_KEY = "shellx.legacyFlutterCleaned"

    /** Deletes the old Flutter app's leftovers once. Returns true when everything is gone (DONE_KEY then true). */
    fun run(dataDir: File, settings: KeyValueStore, keystore: KeystoreAliases = AndroidKeystoreAliases): Boolean {
        if (settings.getBoolean(DONE_KEY)) return true
        var failed = false
        fun attempt(step: () -> Boolean) {
            val ok = try {
                step()
            } catch (e: Exception) {
                false
            }
            if (!ok) {
                failed = true
                CoreLog.log("legacy_cleanup_failed")
            }
        }
        attempt { File(dataDir, "app_flutter").deleteRecursively() }
        File(dataDir, "shared_prefs").listFiles().orEmpty().filter { it.name.startsWith("Flutter") }.forEach { file ->
            attempt { file.delete() || !file.exists() }
        }
        attempt {
            keystore.list().filter { it.contains("flutter", ignoreCase = true) }.forEach { alias ->
                attempt { keystore.delete(alias); true }
            }
            true
        }
        if (!failed) settings.putBoolean(DONE_KEY, true)
        return !failed
    }
}
