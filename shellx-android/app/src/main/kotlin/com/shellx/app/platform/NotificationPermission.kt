package com.shellx.app.platform

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import com.shellx.core.platform.KeyValueStore

/**
 * POST_NOTIFICATIONS (Android 13+), asked once by itself, the first time a Mac is paired (iPhone `registerIfAllowed`,
 * which iOS shows once). Afterwards Settings › Notifications offers Turn On (ledger A-26).
 */
object NotificationPermission {
    const val ASKED_KEY = "shellx.notifications.asked"

    /**
     * Asks unless below Android 13, already granted, or asked before. The one ask is spent only when the prompt
     * actually shows ([PermissionRequester] shows it only while the activity is resumed, and drops it if the caller
     * leaves first).
     */
    suspend fun requestOnce(requester: PermissionRequester, settings: KeyValueStore, sdkInt: Int = Build.VERSION.SDK_INT) {
        if (sdkInt < Build.VERSION_CODES.TIRAMISU) return
        if (requester.isGranted(Manifest.permission.POST_NOTIFICATIONS)) return
        if (settings.getBoolean(ASKED_KEY)) return
        requester.request(Manifest.permission.POST_NOTIFICATIONS) { settings.putBoolean(ASKED_KEY, true) }
    }

    /**
     * After an answer of "not granted": Android showed no dialog. It shows one only while it may still ask (never
     * denied, or denied once); once denied twice it answers at once. Its rationale flag tells them apart: off before
     * and after the launch means no dialog (the first dialog's "Don't allow" turns it on, the last one's turns it off
     * again). [before] null (not known) counts as a dialog shown.
     */
    fun noDialogShown(before: Boolean?, after: Boolean): Boolean = before == false && !after

    /** The app's notifications are on (and, from Android 13, permitted), and the "Needs you" channel, once made, is
     *  not turned off. */
    fun isOn(context: Context): Boolean {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val channel = context.getSystemService(NotificationManager::class.java).getNotificationChannel(PushNotifier.CHANNEL_ID)
        return channel == null || channel.importance != NotificationManager.IMPORTANCE_NONE
    }
}
