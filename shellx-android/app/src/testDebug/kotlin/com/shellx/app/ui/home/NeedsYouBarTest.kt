package com.shellx.app.ui.home

import android.content.Context
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.ui.pending.PendingFixtures
import com.shellx.app.ui.theme.ShellXTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The "Needs you" bar is one TalkBack button that says what a tap does. */
@RunWith(AndroidJUnit4::class)
class NeedsYouBarTest {
    @get:Rule val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Test
    fun talkBackReadsTheHintOfItsOneButton() {
        var opens = 0
        compose.setContent {
            ShellXTheme { NeedsYouBar(listOf(PendingFixtures.mac(PendingFixtures.permission())), showsMachineName = false, open = { opens++ }) }
        }
        val hint = context.getString(R.string.home_needs_you_hint)
        val bar = compose.onNodeWithTag("home.needsYou").fetchSemanticsNode().config
        assertEquals(hint, bar[SemanticsActions.OnClick].label)
        assertEquals(Role.Button, bar[SemanticsProperties.Role])
        compose.onAllNodes(SemanticsMatcher("clicks with the hint") { it.config.getOrNull(SemanticsActions.OnClick)?.label == hint })
            .assertCountEquals(1)
        compose.onAllNodesWithTag("home.needsYou").assertCountEquals(1)
        compose.onNodeWithTag("home.needsYou").performClick()
        assertEquals(1, opens)
    }
}
