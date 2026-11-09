package com.shellx.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.ui.home.NeedsYouBar
import com.shellx.app.ui.pending.FullTextSheet
import com.shellx.app.ui.pending.PendingCardView
import com.shellx.app.ui.pending.PendingFixtures.edit
import com.shellx.app.ui.pending.PendingFixtures.mac
import com.shellx.app.ui.pending.PendingFixtures.permission
import com.shellx.app.ui.pending.PendingFixtures.plan
import com.shellx.app.ui.pending.PendingFixtures.question
import com.shellx.app.ui.pending.PendingFixtures.unknown
import com.shellx.core.link.MachinePendingItem
import com.shellx.core.pending.DecisionFailure
import com.shellx.core.pending.DecisionStatus
import com.shellx.core.text.cutToUtf8
import com.shellx.core.text.utf8Size
import com.shellx.link.core.PendingItem
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The cards and the full-text sheet of `PendingCardRenderTests.swift`, and the "Needs you" bar. */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
class PendingCardRenderTest {
    @Composable
    private fun Cards(entries: List<Pair<MachinePendingItem, DecisionStatus?>>, machines: Boolean = false) {
        LazyColumn(
            Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(entries) { (item, status) -> PendingCardView(item, status, machines) }
        }
    }

    @Test
    fun pendingKinds() = assertRenders("pending-kinds") {
        Cards(listOf(mac(permission()) to null, mac(question()) to null, mac(plan()) to null))
    }

    @Test
    fun pendingKindsMore() = assertRenders("pending-kinds-more") {
        Cards(listOf(mac(edit) to null, mac(unknown) to null, mac(permission(preview = null)) to null), machines = true)
    }

    private fun state(label: String, status: DecisionStatus?, actionable: Boolean) = assertRenders("pending-state-$label") {
        Cards(listOf(mac(permission(), actionable) to status))
    }

    @Test fun stateSending() = state("sending", DecisionStatus.Sending, true)

    @Test fun stateOffline() = state("offline", DecisionStatus.Failed(DecisionFailure.OFFLINE), false)

    @Test fun stateNoAnswer() = state("no-answer", DecisionStatus.Failed(DecisionFailure.NO_ANSWER), true)

    @Test fun stateRejected() = state("rejected", DecisionStatus.Failed(DecisionFailure.REJECTED), true)

    @Test fun stateHandledElsewhere() = state("handled-elsewhere", DecisionStatus.HandledElsewhere, true)

    @Test fun stateReconnecting() = state("reconnecting", null, false)

    @Test
    fun pendingAx3() = assertRenders("pending-ax3") {
        LargeText { Cards(listOf(mac(permission()) to null, mac(question()) to DecisionStatus.Failed(DecisionFailure.NO_ANSWER)), machines = true) }
    }

    @Test
    fun pendingLongPreview() {
        // 8192 bytes of short lines mixing a command, Arabic (right to left) and emoji.
        val text = StringBuilder()
        var line = 0
        while (text.toString().utf8Size < 9000) {
            line += 1
            text.append("echo 'مرحبا' 🚀👩‍💻 ẩn $line\n")
        }
        val preview = text.toString().cutToUtf8(PendingItem.MAX_PREVIEW_BYTES)
        val long = mac(permission(preview = preview))
        // The same first lines, four of them: three show, the fourth is cut.
        val four = mac(permission(preview = preview.split("\n").take(4).joinToString("\n")))
        assertRenders("pending-long-preview") { Cards(listOf(long to null, four to null)) }
    }

    @Test
    fun pendingFullEdit() = assertRenders("pending-full-edit") { FullTextSheet(edit, close = {}) }

    @Test
    fun pendingFullCut() = assertRenders("pending-full-cut") { FullTextSheet(permission(preview = "x".repeat(8192)), close = {}) }

    @Test
    fun needsYouBar() = assertRenders("needs-you-bar") {
        Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(16.dp)) {
            NeedsYouBar(listOf(mac(permission()), mac(question())), showsMachineName = false, open = {})
        }
    }
}
