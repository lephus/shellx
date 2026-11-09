package com.shellx.app.ui.nav

import androidx.compose.material3.Text
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.link.SessionRef
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The work routes' arguments survive Navigation: plain `pending` has none, `pendingIn` and `agent` decode theirs. */
@RunWith(AndroidJUnit4::class)
class WorkRoutesNavTest {
    @get:Rule
    val rule = createComposeRule()

    private lateinit var nav: NavHostController

    private fun host() {
        rule.setContent {
            nav = rememberNavController()
            NavHost(nav, startDestination = "start") {
                composable("start") { Text("start") }
                composable(
                    WorkRoutes.PENDING,
                    arguments = listOf(
                        navArgument("machineId") {
                            type = NavType.StringType
                            nullable = true
                            defaultValue = null
                        },
                        navArgument("workspaceId") {
                            type = NavType.StringType
                            nullable = true
                            defaultValue = null
                        },
                    ),
                ) { e -> Text("pending ${e.arguments?.getString("machineId")} | ${e.arguments?.getString("workspaceId")}") }
                composable(WorkRoutes.AGENT) { e ->
                    Text("agent ${e.arguments?.getString("machineId")} | ${e.arguments?.getString("sessionId")}")
                }
            }
        }
    }

    @Test
    fun pendingWithoutArgumentsShowsEverything() {
        host()
        rule.runOnIdle { nav.navigate(WorkRoutes.pending()) }
        rule.onNodeWithText("pending null | null").assertExists()
    }

    @Test
    fun pendingInCarriesItsWorkspace() {
        host()
        rule.runOnIdle { nav.navigate(WorkRoutes.pendingIn("m1", "ws 1")) }
        rule.onNodeWithText("pending m1 | ws 1").assertExists()
        rule.runOnIdle { nav.navigate(WorkRoutes.agent(SessionRef("m1", "s 1", "", ""))) }
        rule.onNodeWithText("agent m1 | s 1").assertExists()
    }
}
