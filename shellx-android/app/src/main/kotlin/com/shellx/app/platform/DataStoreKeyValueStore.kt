package com.shellx.app.platform

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.core.handlers.ReplaceFileCorruptionHandler
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.stringPreferencesKey
import com.shellx.core.platform.CoreLog
import com.shellx.core.platform.KeyValueStore
import java.io.File
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.selects.select

/**
 * KeyValueStore over DataStore Preferences (S3 §7.3): reads come from an in-memory map filled once at load; a write
 * changes the map at once and reaches the file in call order, on `scope` (IO). Thread-safe.
 *
 * Strings and booleans share one key space, as in 3C's MemoryKeyValueStore: a key holds one value of one type.
 */
class DataStoreKeyValueStore private constructor(
    private val store: DataStore<Preferences>,
    private val values: ConcurrentHashMap<String, Any>,
    scope: CoroutineScope,
) : KeyValueStore {
    private sealed interface Write {
        class Put(val key: String, val value: Any?) : Write

        class Flush(val done: CompletableDeferred<Unit>) : Write
    }

    private val writes = Channel<Write>(Channel.UNLIMITED)

    /** Guards the map change and the queueing together, so the file ends with what the map holds. */
    private val lock = Any()

    /** One writer saves in call order. Puts already queued are saved in one edit; a flush completes after them. */
    private val writer: Job = scope.launch {
        val batch = mutableListOf<Write.Put>()
        for (first in writes) {
            var next: Write? = first
            while (next != null) {
                when (next) {
                    is Write.Put -> batch += next
                    is Write.Flush -> {
                        save(batch)
                        next.done.complete(Unit)
                    }
                }
                next = writes.tryReceive().getOrNull()
            }
            save(batch)
        }
    }

    /** Saves and clears [batch]. A failed write is logged and the writer goes on; cancellation propagates. */
    private suspend fun save(batch: MutableList<Write.Put>) {
        if (batch.isEmpty()) return
        val puts = batch.toList()
        batch.clear()
        try {
            store.edit { preferences ->
                for (put in puts) {
                    when (val value = put.value) {
                        null -> preferences.remove(stringPreferencesKey(put.key)) // removal goes by name
                        is String -> preferences[stringPreferencesKey(put.key)] = value
                        is Boolean -> preferences[booleanPreferencesKey(put.key)] = value
                    }
                }
            }
        } catch (e: IOException) {
            CoreLog.log("settings_write_failed")
        }
    }

    override fun getString(key: String): String? = values[key] as? String

    override fun putString(key: String, value: String?) = put(key, value)

    override fun getBoolean(key: String): Boolean = values[key] as? Boolean ?: false

    override fun putBoolean(key: String, value: Boolean) = put(key, value)

    override fun remove(key: String) = put(key, null)

    private fun put(key: String, value: Any?) {
        synchronized(lock) {
            if (value == null) values.remove(key) else values[key] = value
            writes.trySend(Write.Put(key, value))
        }
    }

    /** Waits until every write made so far is on disk (or failed and was logged). Returns at once once the scope ended. */
    override suspend fun flush() {
        val done = CompletableDeferred<Unit>()
        synchronized(lock) { writes.trySend(Write.Flush(done)) }
        if (!writer.isActive) return
        select {
            done.onAwait {}
            writer.onJoin {}
        }
    }

    companion object {
        /** Damaged file → empty (ReplaceFileCorruptionHandler); unreadable → empty and CoreLog "settings_load_failed". */
        suspend fun load(file: File, scope: CoroutineScope): DataStoreKeyValueStore {
            val store = PreferenceDataStoreFactory.create(
                corruptionHandler = ReplaceFileCorruptionHandler { emptyPreferences() },
                scope = scope,
                produceFile = { file },
            )
            val values = ConcurrentHashMap<String, Any>()
            try {
                for ((key, value) in store.data.first().asMap()) values[key.name] = value
            } catch (e: IOException) {
                CoreLog.log("settings_load_failed")
            }
            return DataStoreKeyValueStore(store, values, scope)
        }

        fun file(context: Context): File = File(context.noBackupFilesDir, "settings.preferences_pb")
    }
}
