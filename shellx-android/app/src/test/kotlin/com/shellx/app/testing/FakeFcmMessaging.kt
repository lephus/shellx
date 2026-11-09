package com.shellx.app.testing

import com.shellx.app.platform.FcmMessaging
import java.io.IOException

/** FCM in tests: records each auto-init setting, in order, and hands out [token] (null: FCM refuses). Thread-safe. */
class FakeFcmMessaging(@Volatile var token: String? = "fcm-1") : FcmMessaging {
    private val settings = mutableListOf<Boolean>()

    val autoInit: List<Boolean> get() = synchronized(settings) { settings.toList() }

    override fun setAutoInit(enabled: Boolean) {
        synchronized(settings) { settings += enabled }
    }

    override suspend fun token(): String = token ?: throw IOException("SERVICE_NOT_AVAILABLE")
}
