package com.shellx.core.platform

/**
 * Where the core's log lines go (:app sends them to android.util.Log, 3D). Lines are event names with error codes,
 * counts or sizes: never a token, key, pairing code, id, name, path or content.
 */
object CoreLog {
    @Volatile var sink: (String) -> Unit = {}

    fun log(line: String) {
        sink(line)
    }
}
