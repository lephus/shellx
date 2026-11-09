package com.shellx.app.ui.onboarding

import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.components.PrimaryButton
import com.shellx.app.ui.theme.ShellXTheme

/**
 * Shown after sign-in while no Mac is paired (`FirstMacView.swift`): what to do on the Mac, the button that opens the
 * scanner, and "Try with a sample Mac" ([tryDemo] null hides it). Settings is in the top bar.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FirstMacView(pair: () -> Unit, tryDemo: (() -> Unit)?, openSettings: () -> Unit, modifier: Modifier = Modifier) {
    val background = MaterialTheme.colorScheme.background
    val accentText = ShellXTheme.colors.accentText
    val fontScale = LocalDensity.current.fontScale
    Scaffold(
        modifier = modifier,
        containerColor = background,
        topBar = {
            TopAppBar(
                title = {},
                actions = {
                    IconButton(onClick = openSettings, modifier = Modifier.testTag("root.settings")) {
                        Icon(Icons.Outlined.Settings, contentDescription = stringResource(R.string.settings_title))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = background),
            )
        },
    ) { padding ->
        Box(
            modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()),
            contentAlignment = Alignment.TopCenter,
        ) {
            Column(
                modifier = Modifier.widthIn(max = 520.dp).fillMaxWidth().padding(horizontal = 16.dp, vertical = 24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Icon(
                    Icons.Outlined.Devices,
                    contentDescription = null,
                    tint = accentText,
                    modifier = Modifier.size((64 * fontScale).dp),
                )
                Text(
                    text = stringResource(R.string.pairing_title),
                    style = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.SemiBold),
                    color = MaterialTheme.colorScheme.onBackground,
                    modifier = Modifier.semantics { heading() },
                )
                Text(
                    text = stringResource(R.string.first_mac_subtitle),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Step(number = "1", text = R.string.pairing_instructions)
                Step(number = "2", text = R.string.first_mac_step2)
                PrimaryButton(onClick = pair, modifier = Modifier.fillMaxWidth().padding(top = 8.dp).testTag("firstMac.pair")) {
                    Icon(Icons.Filled.QrCodeScanner, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.first_mac_scan), style = MaterialTheme.typography.titleMedium)
                }
                if (tryDemo != null) {
                    TextButton(
                        onClick = tryDemo,
                        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("firstMac.demo"),
                    ) {
                        Text(stringResource(R.string.first_mac_demo), color = accentText)
                    }
                }
            }
        }
    }
}

/** One numbered step: a disc in the accent text colour (TalkBack skips it) beside the words. */
@Composable
private fun Step(number: String, @StringRes text: Int) {
    val disc = (24 * LocalDensity.current.fontScale).dp
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
        Box(
            modifier = Modifier.size(disc).background(ShellXTheme.colors.accentText, CircleShape).clearAndSetSemantics {},
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = number,
                style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
                color = MaterialTheme.colorScheme.onSecondary,
            )
        }
        Text(
            text = stringResource(text),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onBackground,
        )
    }
}
