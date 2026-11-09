package com.shellx.app.ui.workspaces

import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.ManualClock
import com.shellx.app.testing.RecordingNavigator
import com.shellx.app.testing.mainComposition
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.demo.FakeMac
import com.shellx.link.core.AgentSession
import com.shellx.link.core.AgentState
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableSharedFlow
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** The home fed by a signed-in scope re-sorts as time passes (ledger 6.2-7). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w400dp-h1600dp")
class WorkspaceListViewTest {
    @get:Rule val rule = createComposeRule()
    @get:Rule val folder = TemporaryFolder()

    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    @After
    fun tearDown() {
        appScope.cancel()
    }

    @Test
    fun theHomeRegroupsEveryThirtySeconds() {
        val clock = ManualClock()
        val mac = FakeMac("MacBook Pro", appScope, nowMs = clock::nowMs)
        mac.setWorkspaces(
            listOf(
                LinkWorkspace(
                    "ws-shellx", "shellx", 0,
                    terminals = listOf(LinkTerminal("t1", "claude", 0, selected = true, sessionId = "s1")),
                ),
            ),
        )
        val working = AgentSession(
            "s1", "claude", "ws-shellx", "shellx", title = "Viết test", state = AgentState.WORKING,
            stateSinceMs = clock.nowMs(), lastActivityMs = clock.nowMs(),
        )
        mac.upsertSession(working)
        val t = mainComposition(folder.root, listOf(mac), appScope, clock = clock)
        t.composition.lifecycle.onStart()
        rule.waitUntil(10_000) { t.composition.real.scopes.current.value != null }
        val scope = t.composition.real.scopes.current.value!!
        val ticks = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
        rule.setContent { ShellXTheme { WorkspaceListView(scope, RecordingNavigator(), ticks) } }
        rule.waitUntil(10_000) { rule.onAllNodes(hasText("Running · 1", ignoreCase = true)).fetchSemanticsNodes().isNotEmpty() }

        mac.upsertSession(working.copy(state = AgentState.IDLE, stateSinceMs = clock.nowMs()))
        rule.waitUntil(10_000) { rule.onAllNodes(hasText("Just finished · 1", ignoreCase = true)).fetchSemanticsNodes().isNotEmpty() }

        clock.advance(3_601.seconds)
        ticks.tryEmit(Unit)
        rule.waitUntil(10_000) { rule.onAllNodes(hasText("Just finished · 1", ignoreCase = true)).fetchSemanticsNodes().isEmpty() }
    }
}
