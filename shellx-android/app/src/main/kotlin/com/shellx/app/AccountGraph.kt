package com.shellx.app

import com.shellx.core.account.AccountVault
import com.shellx.core.account.AppCoordinator
import com.shellx.core.account.RelayAccountCalling
import com.shellx.core.link.MachineHub
import com.shellx.core.platform.KeyValueStore
import com.shellx.core.push.PushRegistration
import com.shellx.core.update.UpdatePrompt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * One [SignedInScope] per hub the coordinator makes: made, then started once. Null while there is no hub (signed out,
 * and during a sign-out, a deletion or a 401, while the phase still says SignedIn). Main-confined.
 */
class SignedInScopes(coordinator: AppCoordinator, scope: CoroutineScope, make: (MachineHub) -> SignedInScope) {
    private val _current = MutableStateFlow<SignedInScope?>(null)
    val current: StateFlow<SignedInScope?> = _current.asStateFlow()

    init {
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            coordinator.hub.collect { hub ->
                when {
                    hub == null -> _current.value = null
                    _current.value?.hub !== hub -> make(hub).also {
                        _current.value = it
                        it.start()
                    }
                }
            }
        }
    }
}

/** One account the app can show: the real one, or the demo's (`AppGraph.swift`). */
class AccountGraph(
    val coordinator: AppCoordinator,
    val relay: RelayAccountCalling,
    val vault: AccountVault,
    val settings: KeyValueStore,
    val scopes: SignedInScopes,
    val launch: LaunchMark,
    /** Keeps the relay holding this phone's FCM token; null in the demo. */
    val push: PushRegistration?,
    /** Offers a newer Play version; null in debug builds and in the demo. */
    val updatePrompt: UpdatePrompt?,
    val isDemo: Boolean,
)
