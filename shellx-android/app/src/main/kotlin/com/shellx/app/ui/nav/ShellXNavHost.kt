package com.shellx.app.ui.nav

import android.annotation.SuppressLint
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraph
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.navArgument
import com.shellx.app.AppComposition
import com.shellx.app.BuildConfig
import com.shellx.app.SignedInScope
import com.shellx.app.ui.LaunchView
import com.shellx.app.ui.SignedInView
import com.shellx.app.ui.agent.AgentView
import com.shellx.app.ui.home.EndedSessionsView
import com.shellx.app.ui.machines.MachinesView
import com.shellx.app.ui.pairing.CancelPairingWhenLeft
import com.shellx.app.ui.pairing.PairingScreen
import com.shellx.app.ui.pending.PendingListView
import com.shellx.app.ui.settings.AccountActions
import com.shellx.app.ui.settings.SettingsScreen
import com.shellx.app.ui.settings.versionText
import com.shellx.app.ui.signin.SignInView
import com.shellx.app.ui.workspaces.OtherSessionsView
import com.shellx.app.ui.workspaces.WorkspaceView
import com.shellx.core.account.AppPhase
import com.shellx.core.link.SessionRef
import com.shellx.core.workspaces.WorkspaceRef
import kotlinx.coroutines.launch

private const val FADE_MS = 300

/**
 * The app's NavHost (contracts §5): `launch` first; [RootSync] keeps `composition.root` at the bottom of the stack, and
 * every other route is pushed above it. The three work routes (plan 3E) show the workspace, the agent's chat and the
 * waiting requests, each in its [SignedIn] wrapper. Pages fade in and out (300 ms), with the predictive back gesture
 * too. A back arrow goes through [NavControllerNavigator.back], which never closes the page
 * under a page that is still fading out (a bare `nav.popBackStack()` tapped twice can pop the root and leave a blank
 * window).
 */
@Composable
fun ShellXNavHost(composition: AppComposition, nav: NavHostController, modifier: Modifier = Modifier) {
    val navigator = rememberShellXNavigator(nav) { composition.active.value.scopes.current.value }
    val root by composition.root.collectAsStateWithLifecycle()
    val startDemo: () -> Unit = { composition.appScope.launch { composition.demo.start() } }
    // The work screens open routes by string (WorkRoutes); like the navigator's opens, a double tap opens one page.
    val open: (String) -> Unit = { route -> nav.navigate(route) { launchSingleTop = true } }

    NavHost(
        navController = nav,
        startDestination = Routes.LAUNCH,
        modifier = modifier,
        enterTransition = { fadeIn(tween(FADE_MS)) },
        exitTransition = { fadeOut(tween(FADE_MS)) },
        popEnterTransition = { fadeIn(tween(FADE_MS)) },
        popExitTransition = { fadeOut(tween(FADE_MS)) },
    ) {
        composable(Routes.LAUNCH) { LaunchView() }
        composable(Routes.SIGN_IN) {
            val phase by composition.real.coordinator.phase.collectAsStateWithLifecycle()
            SignInView(
                expired = (phase as? AppPhase.SignedOut)?.expired == true,
                signIn = { composition.real.coordinator.signInWithGoogle() },
                startDemo = startDemo,
            )
        }
        // The three roots draw by the current state, so a root still waiting to be swapped is never stale.
        for (route in listOf(Routes.FIRST_MAC, Routes.HOME, Routes.DEMO)) {
            composable(route) {
                SignedIn(composition) { scope ->
                    val active by composition.active.collectAsStateWithLifecycle()
                    SignedInView(active, scope, navigator, startDemo = if (active.isDemo) null else startDemo)
                }
            }
        }
        composable(Routes.PAIRING) {
            SignedIn(composition) { scope ->
                CancelPairingWhenLeft { scope.pairing.cancel() }
                PairingScreen(scope.pairing, close = navigator::back)
            }
        }
        composable(WorkRoutes.WORKSPACE) { e ->
            SignedIn(composition) { scope ->
                WorkspaceView(
                    scope,
                    WorkspaceRef(e.arguments?.getString("machineId").orEmpty(), e.arguments?.getString("workspaceId").orEmpty()),
                    open = open,
                    back = navigator::back,
                )
            }
        }
        composable(WorkRoutes.AGENT) { e ->
            SignedIn(composition) { scope ->
                val ref = remember(e) {
                    WorkRoutes.sessionRef(
                        scope.hub.state.value,
                        e.arguments?.getString("machineId").orEmpty(),
                        e.arguments?.getString("sessionId").orEmpty(),
                    )
                }
                AgentView(scope, ref, open = open, back = navigator::back)
            }
        }
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
        ) { e ->
            SignedIn(composition) { scope ->
                val m = e.arguments?.getString("machineId")
                val w = e.arguments?.getString("workspaceId")
                PendingListView(
                    scope.hub, scope.decisions, scope.sheets,
                    only = if (m != null && w != null) ({ it.isIn(m, w) }) else null,
                    back = navigator::back,
                )
            }
        }
        composable(Routes.SESSIONS, Routes.SESSIONS_ARGUMENTS) { e ->
            SignedIn(composition) { scope ->
                if (e.arguments?.getString("kind") == SessionListKind.ENDED.wire) {
                    EndedSessionsView(scope, navigator)
                } else {
                    OtherSessionsView(scope, e.arguments?.getString("machineId").orEmpty(), navigator)
                }
            }
        }
        composable(Routes.MACHINES) { SignedIn(composition) { scope -> MachinesView(scope, navigator) } }
        composable(Routes.SETTINGS) {
            SignedIn(composition) { scope ->
                val active by composition.active.collectAsStateWithLifecycle()
                val phase by active.coordinator.phase.collectAsStateWithLifecycle()
                val appearance by composition.appearance.appearance.collectAsStateWithLifecycle()
                val account = remember(active) {
                    if (active.isDemo) null else AccountActions({ active.coordinator.signOut() }, { active.coordinator.deleteAccount() })
                }
                SettingsScreen(
                    email = (phase as? AppPhase.SignedIn)?.email.orEmpty(),
                    account = account,
                    appearance = appearance,
                    onAppearance = composition.appearance::set,
                    voice = scope.voice,
                    version = versionText(BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE.toLong()),
                    openMachines = navigator::openMachines,
                    back = navigator::back,
                    // The real account's, as the automatic ask's (SignedInFrame).
                    settings = composition.settings,
                )
            }
        }
    }
    RootSync(nav, root)
}

/**
 * Keeps `root` as the only root destination: a new root replaces the whole stack (signing in or out, the demo), except
 * that a switch between `first_mac` and `home` (pairing the first Mac, unpairing the last one) waits until the page on
 * top closes, so the user is never pulled off it. It compares with the stack's real bottom entry, so a stack that lost
 * its root (popped, or restored apart from this) is put back on it rather than left blank or on `launch`.
 */
@Composable
fun RootSync(nav: NavHostController, root: String) {
    // The whole stack, not the current entry: popping the last entry empties the stack without a new current entry.
    @SuppressLint("RestrictedApi") // No public API gives the whole stack or its emptying; RootSyncTest guards upgrades.
    val stack by nav.currentBackStack.collectAsState()
    LaunchedEffect(root, stack) {
        val bottom = bottomRoute(nav)
        if (root == bottom) return@LaunchedEffect
        val atRoot = nav.previousBackStackEntry == null
        // Pairing the first Mac, or unpairing the last one, never pulls the user off the page they are on.
        if (bottom in Routes.SIGNED_IN_ROOTS && root in Routes.SIGNED_IN_ROOTS && !atRoot) return@LaunchedEffect
        nav.navigate(root) {
            popUpTo(nav.graph.id) { inclusive = true }
            launchSingleTop = true
        }
    }
}

/** The route of the stack's bottom destination (the root), or null when the stack is empty. */
@SuppressLint("RestrictedApi") // No public API gives the stack's bottom entry; RootSyncTest guards Navigation upgrades.
internal fun bottomRoute(nav: NavHostController): String? =
    nav.currentBackStack.value.firstOrNull { it.destination !is NavGraph }?.destination?.route

/** A signed-in destination's body: the active account's scope (its state starts afresh with each scope), or
 *  [LaunchView] while there is none (a sign-out, a deletion or a 401 under way; never "signed out" on that alone). */
@Composable
fun SignedIn(composition: AppComposition, content: @Composable (SignedInScope) -> Unit) {
    val active by composition.active.collectAsStateWithLifecycle()
    val current by active.scopes.current.collectAsStateWithLifecycle()
    val scope = current
    if (scope == null) LaunchView() else key(scope) { content(scope) }
}

/**
 * The app's [ShellXNavigator] over [nav]. Each `open…` navigates with `launchSingleTop`, which drops a double tap;
 * `openPairing` cancels the pairing model first (a fresh scan), `showPairing` opens the page on its current step.
 * [back] closes the page on top only while it is resumed, so a second tap during the fade never closes the page under
 * it (the root above all).
 */
class NavControllerNavigator(private val nav: NavHostController, private val scope: () -> SignedInScope?) : ShellXNavigator {
    private fun go(route: String) = nav.navigate(route) { launchSingleTop = true }

    override fun openWorkspace(ref: WorkspaceRef) = go(WorkRoutes.workspace(ref))

    override fun openAgent(ref: SessionRef) = go(WorkRoutes.agent(ref))

    override fun openPending(only: WorkspaceRef?) =
        go(if (only == null) WorkRoutes.pending() else WorkRoutes.pendingIn(only.machineId, only.workspaceId))

    override fun openSessions(kind: SessionListKind, machineId: String?) = go(Routes.sessions(kind, machineId))

    override fun openMachines() = go(Routes.MACHINES)

    override fun openSettings() = go(Routes.SETTINGS)

    override fun openPairing() {
        scope()?.pairing?.cancel()
        showPairing()
    }

    override fun showPairing() = go(Routes.PAIRING)

    override fun back() {
        val top = nav.currentBackStackEntry ?: return
        if (top.lifecycle.currentState != Lifecycle.State.RESUMED || nav.previousBackStackEntry == null) return
        nav.popBackStack()
    }
}

/**
 * The navigator the screens get, kept by the window's ViewModel: it forwards to the [NavControllerNavigator] of the
 * newest window. Work that outlives a recreated window (a workspace being made) then opens its page in the new one.
 */
internal class NavigatorRelay : ViewModel(), ShellXNavigator {
    var current: ShellXNavigator? = null

    override fun openWorkspace(ref: WorkspaceRef) {
        current?.openWorkspace(ref)
    }

    override fun openAgent(ref: SessionRef) {
        current?.openAgent(ref)
    }

    override fun openPending(only: WorkspaceRef?) {
        current?.openPending(only)
    }

    override fun openSessions(kind: SessionListKind, machineId: String?) {
        current?.openSessions(kind, machineId)
    }

    override fun openMachines() {
        current?.openMachines()
    }

    override fun openSettings() {
        current?.openSettings()
    }

    override fun openPairing() {
        current?.openPairing()
    }

    override fun showPairing() {
        current?.showPairing()
    }

    override fun back() {
        current?.back()
    }

    override fun onCleared() {
        current = null
    }
}

/** The window's navigator over [nav] (see [NavigatorRelay]); [scope] is the active account's scope, for openPairing. */
@Composable
internal fun rememberShellXNavigator(nav: NavHostController, scope: () -> SignedInScope?): ShellXNavigator {
    val relay = viewModel { NavigatorRelay() }
    val currentScope by rememberUpdatedState(scope)
    val direct = remember(nav) { NavControllerNavigator(nav) { currentScope() } }
    DisposableEffect(relay, direct) {
        relay.current = direct
        onDispose { if (relay.current === direct) relay.current = null }
    }
    return relay
}
