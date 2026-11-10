package com.shellx.app.ui

import android.annotation.SuppressLint
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavGraph
import androidx.navigation.NavHostController
import com.shellx.app.AppComposition
import com.shellx.app.PlatformServices
import com.shellx.app.ui.nav.Routes
import com.shellx.app.ui.nav.WorkRoutes
import com.shellx.app.ui.nav.bottomRoute

/**
 * The one place a signed-in account's environment wraps the whole NavHost (the iPhone `SignedInView`'s environment and
 * tasks): with a scope and [platform], [SignedInWork] around [content]; otherwise [content] as it is. Never per
 * destination. [ShellXApp] passes [content] as movable content, and each branch calls it exactly once, so the NavHost
 * keeps its pages and their state when the wrapper appears or goes (3D note 7).
 *
 * A tapped alert opens the waiting requests right above the stack's real bottom ([bottomRoute], else [root]), dropping
 * the pages between (3D note 6). It is taken only once that bottom is the signed-in root itself (`home` or `first_mac`,
 * equal to [root]): a window starts on `launch`, and RootSync's swap to the root replaces the whole stack, which would
 * wipe a page opened before it (review C I-1: a tap that starts the app or recreates its window). While a
 * `first_mac`↔`home` swap waits for the page on top to close, the tap waits for it too. When the stack is already the root
 * and the whole list (no Mac or workspace filter), the tap is taken and nothing moves, so an open sheet and its typed
 * answer stay (the iPhone sets an equal path; final review I-1).
 * [platform] null (3D's host tests) leaves the wrapper out.
 */
@Composable
fun SignedInFrame(
    composition: AppComposition,
    nav: NavHostController,
    root: String,
    platform: PlatformServices? = null,
    content: @Composable () -> Unit,
) {
    val active by composition.active.collectAsStateWithLifecycle()
    val scope by active.scopes.current.collectAsStateWithLifecycle()
    val currentRoot by rememberUpdatedState(root)
    // The whole stack, as RootSync reads it: its bottom entry is the root once RootSync is done.
    @SuppressLint("RestrictedApi") // No public API gives the whole stack; RootSyncTest guards Navigation upgrades.
    val stack by nav.currentBackStack.collectAsState()
    val bottom = stack.firstOrNull { it.destination !is NavGraph }?.destination?.route
    val rootReady = root in Routes.SIGNED_IN_ROOTS && bottom == root
    val current = scope
    if (current == null || platform == null) {
        content()
    } else {
        SignedInWork(
            scope = current,
            platform = platform,
            push = active.push, // null in the demo
            settings = composition.settings,
            openPending = if (!rootReady) {
                null
            } else {
                {
                    // Already on the whole list: keep it, with its open sheet (Navigation pops for popUpTo before it
                    // checks launchSingleTop, so navigating would rebuild the page).
                    if (!showsEveryRequest(nav, currentRoot)) {
                        nav.navigate(WorkRoutes.pending()) {
                            popUpTo(bottomRoute(nav) ?: currentRoot)
                            launchSingleTop = true
                        }
                    }
                }
            },
        ) { content() }
    }
}

/** The stack is exactly [root] and, above it, the waiting requests with no Mac or workspace filter. */
@SuppressLint("RestrictedApi") // No public API gives the whole stack; RootSyncTest guards Navigation upgrades.
private fun showsEveryRequest(nav: NavHostController, root: String): Boolean {
    val pages = nav.currentBackStack.value.filter { it.destination !is NavGraph }
    val top = pages.getOrNull(1) ?: return false
    return pages.size == 2 && pages[0].destination.route == root && top.destination.route == WorkRoutes.PENDING &&
        top.arguments?.getString("machineId") == null && top.arguments?.getString("workspaceId") == null
}
