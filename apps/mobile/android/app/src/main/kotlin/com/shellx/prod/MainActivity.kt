package com.shellx.prod

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth shows BiometricPrompt, which needs a FragmentActivity.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    // Push notifications arrive on this channel (AndroidManifest: FCM's
    // default_notification_channel_id). Creating it again only updates its name and description,
    // so a language change shows up; the user's own channel settings are kept. minSdk is 26, so
    // channels always exist.
    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            getString(R.string.notification_channel_id),
            getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        )
        channel.description = getString(R.string.notification_channel_description)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
