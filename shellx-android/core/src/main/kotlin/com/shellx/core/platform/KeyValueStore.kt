package com.shellx.core.platform

/**
 * Small non-secret settings (the iPhone's UserDefaults; S3 §7.3 DataStore). Synchronous: :app keeps every value in
 * memory, loaded before AppComposition is built, and writes through to DataStore in the background (3D).
 */
interface KeyValueStore {
    fun getString(key: String): String?

    /** A null [value] removes the key. */
    fun putString(key: String, value: String?)

    /** False when absent. */
    fun getBoolean(key: String): Boolean

    fun putBoolean(key: String, value: Boolean)

    fun remove(key: String)
}

/** In memory only: the demo's own settings, and tests. Thread-safe. */
class MemoryKeyValueStore : KeyValueStore {
    private val values = HashMap<String, Any>()

    override fun getString(key: String): String? = synchronized(values) { values[key] as? String }

    override fun putString(key: String, value: String?) {
        synchronized(values) { if (value == null) values.remove(key) else values[key] = value }
    }

    override fun getBoolean(key: String): Boolean = synchronized(values) { values[key] as? Boolean ?: false }

    override fun putBoolean(key: String, value: Boolean) {
        synchronized(values) { values[key] = value }
    }

    override fun remove(key: String) {
        synchronized(values) { values.remove(key) }
    }
}
