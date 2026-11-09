package com.shellx.core.demo

import com.shellx.core.link.MachineLinkConnecting
import com.shellx.link.account.PairedMachine
import com.shellx.link.account.RelayApiException
import com.shellx.link.core.LinkSession
import com.shellx.link.core.NoiseStaticKey

/**
 * Connects each paired machine to the [FakeMac] with its machineId (FakeMacFleet.swift). A machine that is not in the
 * fleet answers as the relay does for a removed Mac: `RelayApiException.Http(404, "machine_not_found")`.
 */
class FakeMacFleet(macs: List<FakeMac>, phoneKey: suspend () -> NoiseStaticKey) : MachineLinkConnecting {
    private val connectors: Map<String, MachineLinkConnecting> =
        macs.associate { it.machine.machineId to it.connector(phoneKey) }

    override suspend fun connect(machine: PairedMachine): LinkSession {
        val connector = connectors[machine.machineId] ?: throw RelayApiException.Http(404, "machine_not_found")
        return connector.connect(machine)
    }
}
