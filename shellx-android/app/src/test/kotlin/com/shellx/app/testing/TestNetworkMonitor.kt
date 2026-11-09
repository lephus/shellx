package com.shellx.app.testing

import com.shellx.core.link.NetworkMonitor
import com.shellx.core.link.NetworkPath
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow

/** The network in tests: the test emits paths into [flow]; [subscribers] says whether anyone watches. */
class TestNetworkMonitor : NetworkMonitor {
    val flow: MutableSharedFlow<NetworkPath> = MutableSharedFlow(replay = 1)

    override val paths: Flow<NetworkPath> get() = flow

    val subscribers: Int get() = flow.subscriptionCount.value
}
