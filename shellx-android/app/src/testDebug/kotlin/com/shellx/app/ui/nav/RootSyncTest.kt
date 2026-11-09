package com.shellx.app.ui.nav

import androidx.activity.ComponentActivity
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** RootSync keeps the account's root at the bottom of the stack, and never pulls the user off a page for a Mac count. */
@RunWith(AndroidJUnit4::class)
class RootSyncTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()

    private var root by mutableStateOf(Routes.LAUNCH)
    private lateinit var nav: NavHostController

    private val screens = listOf(
        Routes.LAUNCH, Routes.SIGN_IN, Routes.FIRST_MAC, Routes.HOME, Routes.DEMO, Routes.PAIRING, Routes.SETTINGS,
        Routes.MACHINES,
    )

    private fun start() {
        rule.setContent {
            val controller = rememberNavController().also { nav = it }
            NavHost(controller, startDestination = Routes.LAUNCH) {
                for (route in screens) composable(route) { Text("screen:$route") }
                composable(Routes.SESSIONS, Routes.SESSIONS_ARGUMENTS) { entry ->
                    Text("${entry.arguments?.getString("kind")}|${entry.arguments?.getString("machineId")}")
                }
            }
            RootSync(controller, root)
        }
        rule.waitForIdle()
    }

    private fun rootBecomes(route: String) {
        root = route
        rule.waitForIdle()
    }

    private fun navigate(route: String) {
        rule.runOnUiThread { nav.navigate(route) }
        rule.waitForIdle()
    }

    private fun current(): String? = nav.currentBackStackEntry?.destination?.route

    @Test
    fun theRootFollowsTheAccount() {
        start()
        rule.onNodeWithText("screen:launch").assertIsDisplayed()

        rootBecomes(Routes.SIGN_IN)
        rule.onNodeWithText("screen:sign_in").assertIsDisplayed()
        rootBecomes(Routes.HOME)

        rule.onNodeWithText("screen:home").assertIsDisplayed()
        assertNull("home is the only page", nav.previousBackStackEntry)
    }

    @Test
    fun signingOutClearsEveryScreen() {
        start()
        rootBecomes(Routes.HOME)
        navigate(Routes.SETTINGS)
        navigate(Routes.MACHINES)

        rootBecomes(Routes.SIGN_IN)

        assertEquals(Routes.SIGN_IN, current())
        assertNull(nav.previousBackStackEntry)
    }

    @Test
    fun aFirstMacWaitsUntilThePageOnTopCloses() {
        start()
        rootBecomes(Routes.FIRST_MAC)
        navigate(Routes.PAIRING)

        rootBecomes(Routes.HOME)
        assertEquals("the Paired step stays on screen", Routes.PAIRING, current())

        rule.runOnUiThread { nav.popBackStack() }
        rule.waitForIdle()
        assertEquals(Routes.HOME, current())
        assertNull(nav.previousBackStackEntry)
    }

    @Test
    fun losingTheLastMacAtTheRootSwitchesAtOnce() {
        start()
        rootBecomes(Routes.HOME)

        rootBecomes(Routes.FIRST_MAC)

        assertEquals(Routes.FIRST_MAC, current())
        assertNull(nav.previousBackStackEntry)
    }

    @Test
    fun systemBackReturnsToTheRoot() {
        start()
        rootBecomes(Routes.HOME)
        navigate(Routes.SETTINGS)
        rule.onNodeWithText("screen:settings").assertIsDisplayed()

        rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        rule.waitForIdle()

        rule.onNodeWithText("screen:home").assertIsDisplayed()
        assertEquals(Routes.HOME, current())
    }

    /** Review D m-3: a root popped off the stack (a stray `nav.popBackStack()`) comes back; the window is never blank. */
    @Test
    fun aPoppedRootComesBack() {
        start()
        rootBecomes(Routes.HOME)

        rule.runOnUiThread { nav.popBackStack() }
        rule.waitForIdle()

        rule.onNodeWithText("screen:home").assertIsDisplayed()
        assertEquals(Routes.HOME, current())
        assertNull(nav.previousBackStackEntry)
    }

    /** Review D m-3: a stack whose bottom is not the root (restored apart from RootSync) is put back on the root. */
    @Test
    fun aStackLeftOnAnotherRootIsPutBackOnTheRoot() {
        start()
        rootBecomes(Routes.HOME)

        rule.runOnUiThread {
            nav.navigate(Routes.LAUNCH) {
                popUpTo(nav.graph.id) { inclusive = true }
            }
        }
        rule.waitForIdle()

        rule.onNodeWithText("screen:home").assertIsDisplayed()
        assertEquals(Routes.HOME, current())
        assertNull(nav.previousBackStackEntry)
    }

    @Test
    fun sessionArgumentsRoundTrip() {
        start()
        rootBecomes(Routes.HOME)

        navigate(Routes.sessions(SessionListKind.OTHER, "m 1"))
        rule.onNodeWithText("other|m 1").assertIsDisplayed()

        navigate(Routes.sessions(SessionListKind.ENDED))
        rule.onNodeWithText("ended|null").assertIsDisplayed()
    }
}
