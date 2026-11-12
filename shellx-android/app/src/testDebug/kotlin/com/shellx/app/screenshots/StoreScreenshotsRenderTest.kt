package com.shellx.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.HomeFixtures.NOW_MS
import com.shellx.app.testing.HomeFixtures.macbook
import com.shellx.app.testing.HomeFixtures.mockup
import com.shellx.app.ui.agent.AgentFixtures
import com.shellx.app.ui.agent.AgentFixtures.everyKind
import com.shellx.app.ui.agent.AgentScreen
import com.shellx.app.ui.components.LocalSpinner
import com.shellx.app.ui.onboarding.FirstMacView
import com.shellx.app.ui.pending.PendingCardView
import com.shellx.app.ui.pending.PendingFixtures.mac
import com.shellx.app.ui.pending.PendingFixtures.permission
import com.shellx.app.ui.pending.PendingFixtures.plan
import com.shellx.app.ui.pending.PendingSheetState
import com.shellx.app.ui.pending.PlanReviewSheet
import com.shellx.app.ui.settings.AccountActions
import com.shellx.app.ui.settings.SettingsScreen
import com.shellx.app.ui.settings.settingsVoiceService
import com.shellx.app.ui.terminal.TerminalPane
import com.shellx.app.ui.theme.AppAppearance
import com.shellx.app.ui.workspaces.WorkspaceListScreen
import com.shellx.core.composer.ComposerDraft
import com.shellx.core.demo.DemoTerminalScreens
import com.shellx.core.home.AgentStatusRow
import com.shellx.core.terminal.TerminalViewModel
import com.shellx.core.voice.VoiceLanguage
import com.shellx.link.core.AgentState
import com.shellx.link.core.TerminalScreen
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Google Play phone screenshots (plan 3H): 1080 x 1920 px, in light and dark, English and Vietnamese.
 * `dev.sh screenshots record <dir>` writes them as store-<NN>-<slug>-<theme>-<lang>.png, and
 * release/mobile/play/store_assets.py turns them into the listing's JPEGs. Each shot renders the same screen and
 * sample data as that screen's own render test.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = StoreScreenshotsRenderTest.STORE_QUALIFIERS)
class StoreScreenshotsRenderTest {
    companion object {
        const val STORE_QUALIFIERS = "w360dp-h640dp-xxhdpi"

        /** The shell's history rows kept above its screen: a pane that shows the last rows starts on a whole one. */
        const val HISTORY_ROWS = 3
    }

    private val voiceScope = CoroutineScope(SupervisorJob())

    @After
    fun tearDown() {
        voiceScope.cancel()
    }

    private fun shoot(name: String, content: @Composable ColumnScope.() -> Unit) {
        val shots = ShellXSnapshots.capture(name) {
            CompositionLocalProvider(LocalSpinner provides StillSpinner) {
                Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) { content() }
            }
        }
        assertEquals(listOf("light-en", "dark-en", "light-vi", "dark-vi"), shots.map { "${it.theme}-${it.language}" })
        for (shot in shots) {
            assertEquals(1080, shot.width)
            assertEquals(1920, shot.height)
        }
        assertFalse(shots[0].argb.contentEquals(shots[1].argb))
    }

    @Test
    fun store01Home() {
        shoot("store-01-home") {
            WorkspaceListScreen(groups = listOf(macbook), focus = mockup, pending = emptyList(), nowMs = NOW_MS, showsMachineNames = false)
        }
    }

    @Test
    fun store02Permission() {
        shoot("store-02-permission") {
            LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp, 160.dp, 16.dp, 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(listOf(mac(permission()))) { item -> PendingCardView(item, null, false) }
            }
        }
    }

    @OptIn(ExperimentalMaterial3Api::class)
    @Test
    fun store03Terminal() {
        val screen = TerminalScreen().apply {
            apply(DemoTerminalScreens.SHELL.copy(history = DemoTerminalScreens.SHELL.history.takeLast(HISTORY_ROWS)).snapshot)
            apply(DemoTerminalScreens.SHELL_TYPING)
        }
        shoot("store-03-terminal") {
            val model = TerminalViewModel.fixed("t-zsh", screen)
            TopAppBar(title = { Text("shellx-ios") })
            TerminalPane(model, model.terminalId ?: "t", "zsh", shown = true, modifier = Modifier.weight(1f), showsKeyBar = false)
        }
    }

    @Test
    fun store04Agent() {
        shoot("store-04-agent") {
            val row = AgentFixtures.session.let { AgentStatusRow.of(it, AgentFixtures.NOW_MS) }
            val canStop = row.online && (row.state == AgentState.WORKING || row.state == AgentState.NEEDS_INPUT)
            AgentScreen(
                ref = AgentFixtures.ref, place = "Claude Code · MacBook Pro", row = { row }, gone = false, offline = false,
                pending = emptyList(), showsMachineName = false, entries = everyKind.take(5), emptyState = null,
                machineName = "MacBook Pro", older = com.shellx.core.agent.AgentThreadModel.Older.NONE, loadingOlder = false,
                canStop = canStop, notice = null, draft = ComposerDraft(text = ""), onDraftChange = {}, embedded = false,
                canRemoveFromPhone = false,
            )
        }
    }

    @Test
    fun store05Plan() {
        shoot("store-05-plan") { PlanReviewSheet(mac(plan()), PendingSheetState(), send = {}, close = {}) }
    }

    @Test
    fun store06FirstMac() {
        shoot("store-06-first-mac") { FirstMacView(pair = {}, tryDemo = {}, openSettings = {}) }
    }

    @Test
    fun store07Settings() {
        val voice = settingsVoiceService(voiceScope, VoiceLanguage.ENGLISH)
        runBlocking { voice.refreshEngine() }
        // Settings is a scrolling list: at 640 dp the Voice and Notifications sections fall below the first screen, so the
        // shot lays the screen out at 0.7x density (the same 1080 x 1920 px, a taller and wider window in dp).
        val density = LocalDensity
        shoot("store-07-settings") {
            val now = density.current
            CompositionLocalProvider(density provides Density(now.density * 0.7f, now.fontScale)) {
                SettingsScreen(
                    email = "phu@example.com", account = AccountActions({}, {}), appearance = AppAppearance.SYSTEM, onAppearance = {},
                    voice = voice, version = "1.0.0 (100)", openMachines = {}, back = {},
                )
            }
        }
    }
}
