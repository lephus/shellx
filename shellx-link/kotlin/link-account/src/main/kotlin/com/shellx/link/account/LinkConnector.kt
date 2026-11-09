package com.shellx.link.account

import com.shellx.link.core.LinkClient
import com.shellx.link.core.NoiseStaticKey
import com.shellx.link.core.RelayClientConnector
import com.shellx.link.core.RelaySocketFactory

object LinkConnector {
    /**
     * Connects to a paired machine: mints a connect ticket whose slot must be [PairedMachine.linkSlot], opens a relay
     * circuit (retrying while the Mac is between registrations), and runs the Noise handshake trusting only
     * [PairedMachine.hostKey], the key pinned at pairing.
     *
     * What a failure means: [RelayApiException.Http] 401 is a signed-out phone; `not_granted` or `machine_not_found`
     * is a revoked grant; `NoiseException.UntrustedPeer` or [RelayApiException.SlotMismatch] is a changed host key;
     * `LinkClientException.ProtocolMismatch` asks for an update; anything else (an `IOException`, `RelayException`,
     * `LinkClientException.SessionClosed` or `TimedOut`) is the network or the Mac being away.
     */
    suspend fun connect(
        machine: PairedMachine,
        key: NoiseStaticKey,
        api: RelayApi,
        token: String,
        clientVersion: String,
        deviceName: String,
        sockets: RelaySocketFactory = api.relaySockets,
    ): LinkClient {
        val minted = api.mintConnectTicket(machine.machineId, machine.linkSlot, token)
        val circuit = RelayClientConnector.connect(minted.relayUrl, machine.linkSlot, minted.ticket, sockets)
        return LinkClient.connect(circuit, key, machine.hostKey, clientVersion, deviceName)
    }
}
