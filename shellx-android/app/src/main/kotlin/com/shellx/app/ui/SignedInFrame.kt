package com.shellx.app.ui

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import com.shellx.app.AppComposition

/**
 * The one place a signed-in account's environment wraps the whole NavHost (the iPhone `SignedInView`'s environment and
 * tasks). In plan 3D it draws [content] as it is.
 *
 * Plan 3E (Task 12) wraps it here, once for the whole NavHost and never per destination:
 * `val scope = <the active AccountGraph's scopes.current, collected>; if (scope == null) content() else
 * SignedInWork(scope, platform, active.push /* null in the demo */, composition.settings, openPending = {
 * nav.navigate(WorkRoutes.pending()) { popUpTo(root); launchSingleTop = true } }) { content() }`.
 * [ShellXApp] passes [content] as movable content, so the NavHost keeps its state when the wrapper appears or goes.
 */
@Composable
@Suppress("UNUSED_PARAMETER")
fun SignedInFrame(composition: AppComposition, nav: NavHostController, root: String, content: @Composable () -> Unit) {
    content()
}
