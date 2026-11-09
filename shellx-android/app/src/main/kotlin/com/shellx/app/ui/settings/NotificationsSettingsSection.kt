package com.shellx.app.ui.settings

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.shellx.app.R
import com.shellx.app.platform.NotificationPermission
import com.shellx.app.ui.components.SecondaryButton
import com.shellx.core.platform.CoreLog
import com.shellx.core.platform.KeyValueStore

/**
 * Settings › Notifications (S3 §7.4c; ledger A-1, A-28): whether alerts are on, Turn On when they are off, and
 * "Notifications arriving late?" with this phone maker's steps. Read again each time the screen resumes, so a change
 * made in the system's settings shows on return.
 *
 * [settings] (the phone's): Turn On's dialog is one of the two Android shows, so it spends the automatic ask too
 * ([NotificationPermission.ASKED_KEY], review C m-8). Null records nothing.
 */
@Composable
fun NotificationsSettingsSection(settings: KeyValueStore? = null) {
    val context = LocalContext.current
    var on by remember { mutableStateOf(NotificationPermission.isOn(context)) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { on = NotificationPermission.isOn(context) }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        on = NotificationPermission.isOn(context)
        // Android shows the dialog at most twice; after that only the system page can turn alerts on.
        if (!granted) open(context, NotificationSettingsIntents.appNotifications(context))
    }
    val guide = remember { OemGuide.of(Build.MANUFACTURER) }
    NotificationsSettingsContent(
        on = on,
        guide = guide,
        turnOn = {
            val permitted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
            if (permitted) {
                open(context, NotificationSettingsIntents.appNotifications(context))
            } else {
                ask.launch(Manifest.permission.POST_NOTIFICATIONS)
                settings?.putBoolean(NotificationPermission.ASKED_KEY, true)
            }
        },
        openAppSettings = { open(context, NotificationSettingsIntents.appDetails(context)) },
    )
}

/** The section from plain values (render and UI tests). [lateOpen]: the guide starts open. */
@Composable
internal fun NotificationsSettingsContent(
    on: Boolean,
    guide: OemGuide,
    turnOn: () -> Unit,
    openAppSettings: () -> Unit,
    lateOpen: Boolean = false,
) {
    var showsGuide by rememberSaveable { mutableStateOf(lateOpen) }
    SettingsSection(
        title = stringResource(R.string.settings_notifications_title),
        footer = stringResource(if (on) R.string.settings_notifications_on_footer else R.string.settings_notifications_off_footer),
    ) {
        ListItem(
            headlineContent = { Text(stringResource(R.string.settings_notifications_allow)) },
            modifier = Modifier.semantics(mergeDescendants = true) {},
            trailingContent = {
                Text(
                    stringResource(if (on) R.string.settings_notifications_on else R.string.settings_notifications_off),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            },
            colors = settingsRowColors(),
        )
        if (!on) {
            SecondaryButton(
                onClick = turnOn,
                modifier = Modifier.testTag("settings.notifications.turnOn").fillMaxWidth()
                    .padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
            ) { Text(stringResource(R.string.settings_notifications_turn_on)) }
        }
        SettingsDivider()
        ListItem(
            headlineContent = { Text(stringResource(R.string.settings_notifications_late)) },
            modifier = Modifier.testTag("settings.notifications.late").clickable { showsGuide = !showsGuide },
            trailingContent = {
                // Only tells the eye that the row opens; the guide below is read in order.
                Icon(
                    if (showsGuide) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            },
            colors = settingsRowColors(),
        )
        if (showsGuide) {
            Column(
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    stringResource(R.string.settings_notifications_late_intro),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    stringResource(guide.text),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                SecondaryButton(
                    onClick = openAppSettings,
                    modifier = Modifier.testTag("settings.notifications.openAppSettings").fillMaxWidth(),
                ) { Text(stringResource(R.string.settings_notifications_open_app_settings)) }
            }
        }
    }
}

/** Opens a system page; a phone without it (some work profiles, custom ROMs) opens nothing and logs only a name. */
private fun open(context: Context, intent: Intent) {
    if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try {
        context.startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        CoreLog.log("settings_page_missing")
    } catch (_: SecurityException) {
        CoreLog.log("settings_page_refused")
    }
}
