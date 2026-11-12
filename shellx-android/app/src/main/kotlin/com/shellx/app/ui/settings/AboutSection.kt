package com.shellx.app.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import com.shellx.app.R

/** The version as Settings shows it: "1.0.0 (100)". */
fun versionText(versionName: String, versionCode: Long): String = "$versionName ($versionCode)"

/** Settings › About: the version, and "Licenses", which opens the open-source licence notices inside the app (plan 3H). */
@Composable
fun AboutSection(version: String) {
    val context = LocalContext.current
    SettingsSection(title = stringResource(R.string.settings_about_title)) {
        ListItem(
            headlineContent = { Text(stringResource(R.string.settings_about_version)) },
            modifier = Modifier.semantics(mergeDescendants = true) {},
            trailingContent = {
                Text(version, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            },
            colors = settingsRowColors(),
        )
        SettingsDivider()
        ListItem(
            headlineContent = { Text(stringResource(R.string.settings_about_license)) },
            modifier = Modifier.clickable { openLicences(context) }.testTag("settings.about.license"),
            colors = settingsRowColors(),
        )
    }
}
