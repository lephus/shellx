package com.shellx.app.ui.onboarding

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.ui.theme.ShellXTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The first-Mac screen: scan, try the demo, open Settings. */
@RunWith(AndroidJUnit4::class)
class FirstMacViewTest {
    @get:Rule val rule = createComposeRule()

    @Test
    fun theButtonsDoWhatTheySay() {
        var pairs = 0
        var demos = 0
        var settings = 0
        var offersDemo by mutableStateOf(true)
        rule.setContent {
            ShellXTheme {
                FirstMacView(
                    pair = { pairs++ },
                    tryDemo = if (offersDemo) ({ demos++ }) else null,
                    openSettings = { settings++ },
                )
            }
        }

        rule.onNodeWithTag("firstMac.pair").performScrollTo().performClick()
        rule.onNodeWithTag("firstMac.demo").performScrollTo().performClick()
        rule.onNodeWithTag("root.settings").performClick()
        assertEquals(1, pairs)
        assertEquals(1, demos)
        assertEquals(1, settings)

        offersDemo = false
        rule.waitForIdle()
        rule.onNodeWithTag("firstMac.demo").assertDoesNotExist()
    }
}
