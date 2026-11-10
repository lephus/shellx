package com.shellx.app.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Laptop
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemColors
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.shellx.app.R
import com.shellx.app.ui.theme.AppAppearance
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.voice.VoiceService

/**
 * Settings (`SettingsView.swift`; contracts §15's order): Your Macs, Account, Appearance, Voice (while [voice] is set,
 * that is once the mic is set up), Notifications (plan 3E's slot) and About. [account] null is the demo: only the
 * e-mail shows.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    email: String,
    account: AccountActions?,
    appearance: AppAppearance,
    onAppearance: (AppAppearance) -> Unit,
    voice: VoiceService?,
    version: String,
    openMachines: () -> Unit,
    back: () -> Unit,
) {
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    val background = MaterialTheme.colorScheme.background
    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = background,
        topBar = {
            LargeTopAppBar(
                title = { Text(stringResource(R.string.settings_title)) },
                navigationIcon = {
                    IconButton(onClick = back) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.nav_back))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = background, scrolledContainerColor = background),
                scrollBehavior = scrollBehavior,
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding).testTag("settings.list"),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp),
        ) {
            item(key = "machines") {
                SettingsSection(title = null) {
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.machines_title)) },
                        modifier = Modifier.clickable(onClick = openMachines).testTag("settings.machines"),
                        leadingContent = { Icon(Icons.Outlined.Laptop, contentDescription = null) },
                        trailingContent = { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null) },
                        colors = settingsRowColors(),
                    )
                }
            }
            item(key = "account") { AccountSection(email, account) }
            item(key = "appearance") { AppearanceSection(appearance, onAppearance) }
            if (voice != null) item(key = "voice") { VoiceSection(voice) }
            item(key = "notifications") { NotificationsSettingsSection() }
            item(key = "about") { AboutSection(version) }
        }
    }
}

/**
 * One section's look, for every section here and for plan 3E's Notifications section: an optional title, a card of
 * rows ([ListItem]s with [settingsRowColors], [SettingsDivider] between them), and an optional footer. Each section
 * keeps its own room above it, so a section that renders nothing leaves no gap.
 */
@Composable
fun SettingsSection(title: String?, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    SettingsSectionLayout(
        title = title,
        footer = footer?.let { text -> { SettingsFooterText(text) } },
        content = content,
    )
}

/** [SettingsSection] with any footer (the Voice section's spinner while the recognizer is asked). */
@Composable
internal fun SettingsSectionLayout(
    title: String?,
    footer: (@Composable () -> Unit)?,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(Modifier.fillMaxWidth().padding(top = 24.dp)) {
        title?.let {
            Text(
                text = it,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp).semantics { heading() },
                style = MaterialTheme.typography.labelLarge,
                color = ShellXTheme.colors.accentText,
            )
        }
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(16.dp),
            color = MaterialTheme.colorScheme.surfaceContainer,
        ) { Column(content = content) }
        footer?.let {
            Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp)) { it() }
        }
    }
}

@Composable
internal fun SettingsFooterText(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        modifier = modifier,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

/** A row's colours inside a section's card: no container of its own. */
@Composable
fun settingsRowColors(): ListItemColors = ListItemDefaults.colors(containerColor = Color.Transparent)

/** The inset line between two rows of a section's card. */
@Composable
fun SettingsDivider() {
    HorizontalDivider(Modifier.padding(start = 16.dp), color = MaterialTheme.colorScheme.outlineVariant)
}
