package com.shellx.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.movableContentOf
import androidx.compose.runtime.remember
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.shellx.app.AppComposition
import com.shellx.app.PlatformServices
import com.shellx.app.demo.DemoFrame
import com.shellx.app.ui.nav.Routes
import com.shellx.app.ui.nav.ShellXNavHost
import com.shellx.app.ui.nav.bottomRoute
import com.shellx.app.ui.nav.rememberShellXNavigator
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

/**
 * The window (`ShellXApp.swift`, 1C's `DemoRootView`): while the demo runs, the "Demo · Exit" banner above the NavHost;
 * and the links into pairing. A `shellx-link` link waiting in the inbox opens the pairing page on its confirmation
 * step once the real account is signed in, its Macs loaded and no request sheet is open (AppComposition.takeLink); it
 * waits through the sign-in, the demo and an open sheet (Review Focus 2). [platform] (plan 3E's pieces; null in 3D's
 * host tests) gives the signed-in screens their mic, attachments, push taps and permission ask ([SignedInFrame]).
 */
@Composable
fun ShellXApp(composition: AppComposition, nav: NavHostController = rememberNavController(), platform: PlatformServices? = null) {
    val host = remember(composition, nav) { movableContentOf { ShellXNavHost(composition, nav) } }
    val navigator = rememberShellXNavigator(nav) { composition.active.value.scopes.current.value }
    val active by composition.active.collectAsStateWithLifecycle()
    val root by composition.root.collectAsStateWithLifecycle()
    val demo = active.isDemo

    DemoFrame(demo, exit = { composition.appScope.launch { composition.demo.exit() } }) {
        SignedInFrame(composition, nav, root, platform) { host() }
    }

    val hasLink by composition.inbox.hasLink.collectAsStateWithLifecycle()
    val scope by active.scopes.current.collectAsStateWithLifecycle()
    val noSheets = remember { MutableStateFlow(false) }
    val sheetsOpen by (scope?.sheets?.isAnyOpen ?: noSheets).collectAsStateWithLifecycle()
    val entry by nav.currentBackStackEntryAsState()
    LaunchedEffect(hasLink, root, scope, sheetsOpen, entry) {
        // Not before RootSync put the root at the bottom: a new root would close the pairing page again.
        if (!rootApplied(nav, root)) return@LaunchedEffect
        if (composition.takeLink()) navigator.showPairing()
    }
}

/** Whether the stack stands on [root] (or on the other signed-in root, which RootSync swaps once the top page closes). */
private fun rootApplied(nav: NavHostController, root: String): Boolean {
    val bottom = bottomRoute(nav)
    return bottom == root || (bottom in Routes.SIGNED_IN_ROOTS && root in Routes.SIGNED_IN_ROOTS)
}
