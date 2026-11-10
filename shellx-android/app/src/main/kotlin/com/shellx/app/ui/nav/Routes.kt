package com.shellx.app.ui.nav

import android.net.Uri
import androidx.navigation.NamedNavArgument
import androidx.navigation.NavType
import androidx.navigation.navArgument

/** The two session lists of the `sessions/{kind}` route. */
enum class SessionListKind(val wire: String) {
    ENDED("ended"),
    OTHER("other"),
}

/** The shell's routes (contracts §5). The three work routes are [WorkRoutes]'. */
object Routes {
    const val LAUNCH = "launch"
    const val SIGN_IN = "sign_in"
    const val FIRST_MAC = "first_mac"
    const val PAIRING = "pairing"
    const val HOME = "home"
    const val DEMO = "demo"
    const val MACHINES = "machines"
    const val SETTINGS = "settings"

    /** Ended (`sessions/ended`) and the agents outside workspaces of one Mac (`sessions/other?machineId=…`). */
    const val SESSIONS = "sessions/{kind}?machineId={machineId}"

    val SESSIONS_ARGUMENTS: List<NamedNavArgument> = listOf(
        navArgument("kind") { type = NavType.StringType },
        navArgument("machineId") {
            type = NavType.StringType
            nullable = true
            defaultValue = null
        },
    )

    /** The two signed-in roots, which draw the same screen by state (Spec note 3). */
    val SIGNED_IN_ROOTS: Set<String> = setOf(FIRST_MAC, HOME)

    fun sessions(kind: SessionListKind, machineId: String? = null): String =
        if (machineId == null) "sessions/${kind.wire}" else "sessions/${kind.wire}?machineId=${Uri.encode(machineId)}"
}
