package com.shellx.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.shellx.app.AppComposition
import com.shellx.app.PlatformServices
import com.shellx.app.ui.nav.WorkRoutes
import com.shellx.app.ui.nav.bottomRoute

/**
 * The one place a signed-in account's environment wraps the whole NavHost (the iPhone `SignedInView`'s environment and
 * tasks): with a scope and [platform], [SignedInWork] around [content]; otherwise [content] as it is. Never per
 * destination. [ShellXApp] passes [content] as movable content, and each branch calls it exactly once, so the NavHost
 * keeps its pages and their state when the wrapper appears or goes (3D note 7).
 *
 * A tapped alert opens the waiting requests right above the stack's real bottom ([bottomRoute], else [root]: the two
 * differ while a `first_mac`↔`home` swap waits), dropping the pages between (3D note 6).
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
    val current = scope
    if (current == null || platform == null) {
        content()
    } else {
        SignedInWork(
            scope = current,
            platform = platform,
            push = active.push, // null in the demo
            settings = composition.settings,
            openPending = {
                nav.navigate(WorkRoutes.pending()) {
                    popUpTo(bottomRoute(nav) ?: currentRoot)
                    launchSingleTop = true
                }
            },
        ) { content() }
    }
}
