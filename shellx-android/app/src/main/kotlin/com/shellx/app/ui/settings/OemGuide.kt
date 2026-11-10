package com.shellx.app.ui.settings

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.annotation.StringRes
import com.shellx.app.R
import java.util.Locale

/**
 * The steps for "Notifications arriving late?" (S3 §7.4c; ledger A-1): Xiaomi, OPPO and vivo hold FCM back for apps
 * swiped away from Recents, Samsung puts unused apps to sleep. The guide only explains; the app never asks for a
 * battery exemption.
 */
enum class OemGuide(@StringRes val text: Int) {
    XIAOMI(R.string.settings_notifications_late_xiaomi),
    OPPO(R.string.settings_notifications_late_oppo),
    VIVO(R.string.settings_notifications_late_vivo),
    SAMSUNG(R.string.settings_notifications_late_samsung),
    OTHER(R.string.settings_notifications_late_other),
    ;

    companion object {
        /** Case-insensitive: xiaomi, redmi, poco → XIAOMI; oppo, realme, oneplus → OPPO; vivo, iqoo → VIVO; samsung →
         *  SAMSUNG; else OTHER. */
        fun of(manufacturer: String): OemGuide = when (manufacturer.trim().lowercase(Locale.ROOT)) {
            "xiaomi", "redmi", "poco" -> XIAOMI
            "oppo", "realme", "oneplus" -> OPPO
            "vivo", "iqoo" -> VIVO
            "samsung" -> SAMSUNG
            else -> OTHER
        }
    }
}

/** The system pages Settings › Notifications opens. */
object NotificationSettingsIntents {
    /** This app's notification settings. */
    fun appNotifications(context: Context): Intent =
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)

    /** This app's system page (battery, autostart on some phones). */
    fun appDetails(context: Context): Intent =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
}
