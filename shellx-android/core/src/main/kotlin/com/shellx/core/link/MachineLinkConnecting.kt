package com.shellx.core.link

import com.shellx.link.account.PairedMachine
import com.shellx.link.core.LinkSession

/** Opens one Link session to a paired Mac. [RelayMachineConnector] is the real one; FakeMacFleet is the fake. */
fun interface MachineLinkConnecting {
    suspend fun connect(machine: PairedMachine): LinkSession
}
