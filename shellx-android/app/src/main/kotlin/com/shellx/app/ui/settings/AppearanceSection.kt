package com.shellx.app.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.theme.AppAppearance

/** Settings › Appearance (`AppearanceSection.swift`): "Match phone", "Light" or "Dark", applied at once (the app's
 *  windows and the system bars, Spec note 12). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppearanceSection(appearance: AppAppearance, onAppearance: (AppAppearance) -> Unit) {
    SettingsSection(title = stringResource(R.string.settings_appearance_title)) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = stringResource(R.string.settings_appearance_mode),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
            val choices = AppAppearance.entries
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().testTag("settings.appearance")) {
                choices.forEachIndexed { index, choice ->
                    SegmentedButton(
                        selected = choice == appearance,
                        onClick = { onAppearance(choice) },
                        shape = SegmentedButtonDefaults.itemShape(index, choices.size),
                        // As the iPhone's segmented control: the words only, so the three fit.
                        icon = {},
                    ) { Text(stringResource(choice.title), textAlign = TextAlign.Center) }
                }
            }
        }
    }
}
