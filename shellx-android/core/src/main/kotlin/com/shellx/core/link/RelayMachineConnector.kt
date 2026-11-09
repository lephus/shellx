package com.shellx.core.link

import com.shellx.core.account.AccountVault
import com.shellx.link.account.LinkConnector
import com.shellx.link.account.PairedMachine
import com.shellx.link.account.RelayApi
import com.shellx.link.account.RelayApiException
import com.shellx.link.core.LinkSession

/**
 * Connects through the ShellX relay with the account's token and the phone's Link key, both read from the vault on
 * every attempt, so a new sign-in is used at once. Failures map to a [LinkFailure] (3B's `LinkConnector` KDoc).
 */
class RelayMachineConnector(
    private val api: RelayApi,
    private val vault: AccountVault,
    private val clientVersion: String,
    private val deviceName: String,
) : MachineLinkConnecting {
    /** Without a stored session it throws `RelayApiException.Http(401, "signed_out")` before any request, the same as
     *  a token the relay refuses. */
    override suspend fun connect(machine: PairedMachine): LinkSession {
        val token = vault.session()?.token ?: throw RelayApiException.Http(401, "signed_out")
        val key = vault.phoneKey()
        return LinkConnector.connect(machine, key, api, token, clientVersion, deviceName)
    }
}
