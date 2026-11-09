package com.shellx.app.platform

import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import com.shellx.core.link.NetworkMonitor
import com.shellx.core.link.NetworkPath
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

object NetworkPaths {
    /** Status "satisfied" with internet, else "unsatisfied"; interfaces = listOfNotNull(interfaceName). */
    fun of(hasInternet: Boolean, interfaceName: String?, defaultGateways: List<String>): NetworkPath =
        NetworkPath(if (hasInternet) "satisfied" else "unsatisfied", listOfNotNull(interfaceName), defaultGateways)

    fun of(caps: NetworkCapabilities?, link: LinkProperties?): NetworkPath = of(
        caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true,
        link?.interfaceName,
        // A default route has prefix length 0 (RouteInfo.isDefaultRoute is API 29).
        link?.routes.orEmpty().filter { it.destination.prefixLength == 0 }.mapNotNull { it.gateway?.hostAddress },
    )
}

/**
 * NetworkMonitor (contracts §5) over ConnectivityManager.registerDefaultNetworkCallback (S3 §7.3; the iPhone's
 * NWPathMonitor in NetworkPathWatcher.swift). The current path first, then one per change; unregisters when collection
 * ends. What counts as a change, and the settling, is 3C's NetworkChangeFilter.
 */
class NetworkPathWatcher(private val connectivity: ConnectivityManager) : NetworkMonitor {
    override val paths: Flow<NetworkPath> = callbackFlow {
        val active = connectivity.activeNetwork
        trySend(NetworkPaths.of(active?.let(connectivity::getNetworkCapabilities), active?.let(connectivity::getLinkProperties)))
        val callback = object : ConnectivityManager.NetworkCallback() {
            // Called on ConnectivityManager's thread, one at a time.
            private var network: Network? = null
            private var caps: NetworkCapabilities? = null
            private var link: LinkProperties? = null

            /** A new default network starts without the old one's capabilities or link properties. */
            private fun follow(network: Network) {
                if (network == this.network) return
                this.network = network
                caps = null
                link = null
            }

            override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                follow(network)
                caps = networkCapabilities
                trySend(NetworkPaths.of(caps, link))
            }

            override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
                follow(network)
                link = linkProperties
                trySend(NetworkPaths.of(caps, link))
            }

            override fun onLost(network: Network) {
                if (this.network != null && network != this.network) return // an old default, already replaced
                this.network = null
                caps = null
                link = null
                trySend(NetworkPaths.of(null, null))
            }
        }
        connectivity.registerDefaultNetworkCallback(callback)
        awaitClose { connectivity.unregisterNetworkCallback(callback) }
    }
}
