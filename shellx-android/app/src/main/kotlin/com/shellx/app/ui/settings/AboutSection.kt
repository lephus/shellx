package com.shellx.app.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.shellx.app.R

/** Where "Licenses" goes, and the host it shows (a web address is never translated). */
object AboutLinks {
    const val WEBSITE = "https://shellx.pro"
    const val WEBSITE_HOST = "shellx.pro"
}

/** The version as Settings shows it: "1.0.0 (100)". */
fun versionText(versionName: String, versionCode: Long): String = "$versionName ($versionCode)"

/** Settings › About (`AboutSection.swift`): the version, and "Licenses", which opens shellx.pro in the browser. */
@Composable
fun AboutSection(version: String) {
    val uriHandler = LocalUriHandler.current
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
            modifier = Modifier.clickable { uriHandler.openUri(AboutLinks.WEBSITE) }.testTag("settings.about.license"),
            trailingContent = {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        AboutLinks.WEBSITE_HOST,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    // Only tells the eye that the row leaves the app.
                    Icon(
                        Icons.AutoMirrored.Outlined.OpenInNew,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            },
            colors = settingsRowColors(),
        )
    }
}
