package com.shellx.core.link

import kotlinx.coroutines.flow.Flow

/**
 * The device's default network (contracts §5; 3D implements it with ConnectivityManager.registerDefaultNetworkCallback).
 * Emits the current path first, then every change. Status "satisfied" when a default network with INTERNET exists,
 * else "unsatisfied"; interfaces = [LinkProperties.interfaceName]; gateways = the default routes' gateway addresses.
 */
interface NetworkMonitor {
    val paths: Flow<NetworkPath>
}
