package com.shellx.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.shellx.app.AccountGraph
import com.shellx.app.SignedInScope
import com.shellx.app.ui.nav.ShellXNavigator
import com.shellx.app.ui.onboarding.FirstMacView
import com.shellx.app.ui.workspaces.WorkspaceListView

/**
 * The signed-in root (`SignedInView.swift`'s root; routes `first_mac`, `home` and `demo`): [FirstMacView] while no Mac
 * is paired, otherwise the home ([WorkspaceListView]). [startDemo] ("Try with a sample Mac") is never offered inside
 * the demo. The scope already follows the hub's requests and sweeps the chat copies ([SignedInScope.start]); push
 * registration and the notification prompt are plan 3E's `SignedInWork`.
 */
@Composable
fun SignedInView(account: AccountGraph, scope: SignedInScope, navigator: ShellXNavigator, startDemo: (() -> Unit)?) {
    val hub by scope.hub.state.collectAsStateWithLifecycle()
    if (hub.machines.isEmpty()) {
        FirstMacView(
            pair = navigator::openPairing,
            tryDemo = startDemo.takeUnless { account.isDemo },
            openSettings = navigator::openSettings,
        )
    } else {
        WorkspaceListView(scope, navigator)
    }
}
