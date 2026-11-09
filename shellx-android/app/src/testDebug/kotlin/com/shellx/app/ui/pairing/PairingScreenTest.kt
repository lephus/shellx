package com.shellx.app.ui.pairing

import androidx.compose.foundation.layout.Box
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.platform.CameraAccess
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.pairing.PairingFailure
import com.shellx.core.pairing.PairingModel.Step
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The pairing page's steps, its scanner, its buttons and what TalkBack hears; leaving it cancels the attempt. */
@RunWith(AndroidJUnit4::class)
class PairingScreenTest {
    @get:Rule val rule = createComposeRule()

    private val code = "shellx-link://pair?v=1&m=m1&s=s1&k=k&c=c&n=Mac"

    private class Counts {
        val scanned = mutableListOf<String>()
        var paste = 0
        var confirm = 0
        var retry = 0
        var close = 0
        var openSettings = 0

        val actions = PairingActions(
            scanned = { scanned += it },
            paste = { paste++ },
            confirm = { confirm++ },
            retry = { retry++ },
            close = { close++ },
            openSettings = { openSettings++ },
        )
    }

    @Test
    fun aScannedShellXCodeIsTakenOnce() {
        val counts = Counts()
        var feed: ((String) -> Unit)? = null
        rule.setContent {
            ShellXTheme {
                PairingScreenContent(
                    Step.Idle,
                    CameraAccess.AUTHORIZED,
                    counts.actions,
                    scanner = { modifier, onCode ->
                        feed = onCode
                        Box(modifier)
                    },
                )
            }
        }

        rule.runOnIdle {
            feed!!(code)
            feed!!(code)
        }
        assertEquals(listOf(code), counts.scanned)
        rule.onNodeWithTag("pairing.otherCode").assertDoesNotExist()

        rule.runOnIdle { feed!!("https://example.com") }
        rule.onNodeWithTag("pairing.otherCode").assertIsDisplayed()
        assertEquals(listOf(code), counts.scanned)
    }

    @Test
    fun eachStepsButtonsReachTheirActions() {
        val counts = Counts()
        var step by mutableStateOf<Step>(Step.Idle)
        rule.setContent { ShellXTheme { PairingScreenContent(step, CameraAccess.UNAVAILABLE, counts.actions) } }

        rule.onNodeWithTag("pairing.paste").performScrollTo().performClick()
        assertEquals(1, counts.paste)

        step = Step.Confirm("MacBook Pro")
        rule.onNodeWithTag("pairing.confirm").performScrollTo().performClick()
        assertEquals(1, counts.confirm)
        rule.onNodeWithTag("pairing.cancel").performScrollTo().performClick()
        assertEquals(1, counts.close)

        step = Step.WaitingForMac("MacBook Pro")
        rule.onNodeWithTag("pairing.cancel").performScrollTo().performClick()
        assertEquals(2, counts.close)

        step = Step.Paired("MacBook Pro")
        rule.onNodeWithTag("pairing.done").performScrollTo().performClick()
        assertEquals(3, counts.close)

        step = Step.Failed(PairingFailure.Expired)
        rule.onNodeWithTag("pairing.retry").performScrollTo().performClick()
        assertEquals(1, counts.retry)

        rule.onNodeWithTag("pairing.close").performClick()
        assertEquals(4, counts.close)
        assertEquals(0, counts.openSettings)
    }

    @Test
    fun aDeniedCameraOffersSettings() {
        val counts = Counts()
        rule.setContent { ShellXTheme { PairingScreenContent(Step.Idle, CameraAccess.DENIED, counts.actions) } }

        rule.onNodeWithTag("pairing.scanner").assertDoesNotExist()
        rule.onNodeWithTag("pairing.openSettings").performScrollTo().performClick()
        assertEquals(1, counts.openSettings)
    }

    @Test
    fun theStepTitleIsALiveRegion() {
        var step by mutableStateOf<Step>(Step.WaitingForMac("Studio"))
        rule.setContent { ShellXTheme { PairingScreenContent(step, CameraAccess.UNAVAILABLE) } }
        val polite = SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite)

        rule.onNodeWithTag("pairing.message").assert(polite)
        step = Step.Paired("Studio")
        rule.onNodeWithTag("pairing.message").assert(polite)
        step = Step.Failed(PairingFailure.Denied)
        rule.onNodeWithTag("pairing.message").assert(polite)
        step = Step.Confirm("Studio")
        rule.onNodeWithTag("pairing.message").assert(SemanticsMatcher.keyNotDefined(SemanticsProperties.LiveRegion))
    }

    @Test
    fun leavingTheScreenCancelsThePairingAndRecreationDoesNot() {
        val restoration = StateRestorationTester(rule)
        var cancels = 0
        lateinit var nav: NavHostController
        restoration.setContent {
            nav = rememberNavController()
            NavHost(nav, startDestination = "a") {
                composable("a") { Text("screen:a") }
                composable("pairing") {
                    CancelPairingWhenLeft { cancels++ }
                    Text("screen:pairing")
                }
            }
        }

        rule.runOnIdle { nav.navigate("pairing") }
        rule.onNodeWithText("screen:pairing").assertIsDisplayed()

        restoration.emulateSavedInstanceStateRestore()
        rule.onNodeWithText("screen:pairing").assertIsDisplayed()
        assertEquals("a recreated page keeps the attempt", 0, cancels)

        rule.runOnIdle { nav.popBackStack() }
        rule.waitForIdle()
        rule.onNodeWithText("screen:a").assertIsDisplayed()
        assertEquals("leaving the page cancels the attempt", 1, cancels)
    }

    @Test
    fun theViewfinderIsOneTaggedTalkBackElement() {
        rule.setContent {
            ShellXTheme { PairingScreenContent(Step.Idle, CameraAccess.AUTHORIZED, scanner = { modifier, _ -> Box(modifier) }) }
        }

        rule.onNodeWithTag("pairing.scanner").assertContentDescriptionEquals("QR code scanner")
    }
}
