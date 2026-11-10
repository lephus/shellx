package com.shellx.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ManifestTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun asksForNotificationsAndTheMicrophoneButNeverBatteryExemptions() {
        val asked = context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
            .requestedPermissions.orEmpty().toSet()
        assertTrue(Manifest.permission.POST_NOTIFICATIONS in asked)
        assertTrue(Manifest.permission.RECORD_AUDIO in asked)
        assertFalse("android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" in asked) // S3 §7.4c
    }

    /** No FCM token or Firebase installation at a bare launch (3H Data safety). */
    @Test
    fun fcmMakesNoTokenBeforeTheAppAsksForOne() {
        val meta = context.packageManager.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA).metaData
        assertFalse(meta?.getBoolean("firebase_messaging_auto_init_enabled", true) ?: true)
    }
}
