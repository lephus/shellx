package com.shellx.app.ui.nav

import androidx.activity.ComponentActivity
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import org.junit.Assert.assertSame
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The app's navigator: a double tap opens or closes one page, and a navigator held across a recreated window (a
 *  create still on its way) opens its page in the new window. */
@RunWith(AndroidJUnit4::class)
class NavControllerNavigatorTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()

    private lateinit var nav: NavHostController
    private lateinit var navigator: ShellXNavigator

    @Composable
    private fun Host() {
        val controller = rememberNavController().also { nav = it }
        navigator = rememberShellXNavigator(controller) { null }
        NavHost(controller, startDestination = Routes.HOME) {
            for (route in listOf(Routes.HOME, Routes.SETTINGS, Routes.MACHINES)) composable(route) { Text("screen:$route") }
        }
    }

    private fun current(): String? = nav.currentBackStackEntry?.destination?.route

    @Test
    fun aDoubleTapOpensOnePage() {
        rule.setContent { Host() }
        rule.waitForIdle()

        rule.runOnUiThread {
            navigator.openSettings()
            navigator.openSettings()
        }
        rule.waitForIdle()

        assertEquals(Routes.SETTINGS, current())
        assertEquals(Routes.HOME, nav.previousBackStackEntry?.destination?.route)
    }

    @Test
    fun aDoubleTapOnBackClosesOnePage() {
        rule.setContent { Host() }
        rule.waitForIdle()
        rule.runOnUiThread { navigator.openSettings() }
        rule.waitForIdle()

        // The second tap lands while the page fades out: the home is not resumed yet.
        rule.runOnUiThread {
            navigator.back()
            navigator.back()
        }
        rule.waitForIdle()

        assertEquals("the root stays", Routes.HOME, current())
        rule.onNodeWithText("screen:home").assertIsDisplayed()
        assertNull(nav.previousBackStackEntry)
    }

    @Test
    fun aNavigatorFromBeforeARecreationOpensInTheNewWindow() {
        rule.setContent { Host() }
        rule.waitForIdle()
        val before = navigator

        rule.activityRule.scenario.recreate()
        rule.setContent { Host() }
        rule.waitForIdle()
        assertSame("the screens get the same navigator", before, navigator)

        rule.runOnUiThread { before.openSettings() }
        rule.waitForIdle()

        rule.onNodeWithText("screen:settings").assertIsDisplayed()
        assertEquals(Routes.SETTINGS, current())
    }
}
