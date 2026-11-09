package com.shellx.core.link

/**
 * What about the device's network path decides whether live Link sessions may have died: its [status], the
 * [primaryInterface] (the one new connections use, `interfaces.firstOrNull()`) and the [gateways] (sorted, so their
 * order does not count). Interfaces behind the primary one do not count: cellular coming up while Wi-Fi carries the
 * sessions changes nothing. equals, hashCode and toString cover those three.
 */
class NetworkPath(val status: String, interfaces: List<String>, gateways: List<String>) {
    val primaryInterface: String? = interfaces.firstOrNull()

    val gateways: List<String> = gateways.sorted()

    override fun equals(other: Any?): Boolean = other is NetworkPath && status == other.status &&
        primaryInterface == other.primaryInterface && gateways == other.gateways

    override fun hashCode(): Int = (status.hashCode() * 31 + primaryInterface.hashCode()) * 31 + gateways.hashCode()

    override fun toString(): String =
        "NetworkPath(status=$status, primaryInterface=$primaryInterface, gateways=$gateways)"
}
