package com.shellx.core.account

import com.shellx.core.link.MachineLinkConnecting
import com.shellx.core.link.RelayMachineConnector
import com.shellx.link.account.RelayApi
import okhttp3.OkHttpClient

/** Builds the relay client the app uses. */
object RelayClientFactory {
    private val VERSION = Regex("[0-9]{1,6}\\.[0-9]{1,6}\\.[0-9]{1,6}")

    /**
     * The relay stores `X-ShellX-Version` only when it is exactly `major.minor.patch` (`^\d{1,6}\.\d{1,6}\.\d{1,6}$`),
     * the form the Mac app sends. So the app sends its bare version name, or "0.0.0" when that is not in this form.
     */
    fun headerVersion(appVersion: String): String = if (VERSION.matches(appVersion)) appVersion else "0.0.0"

    /**
     * [apiBase] must be `https`, or `http` to a loopback host; `ShellXEndpoints` only hands out such URLs. Throws
     * `RelayException.InsecureTransport` for an http base that is not loopback, and `RelayException.ProtocolViolation`
     * for one that does not parse (3B's RelayApi init): build it inside a `try`.
     */
    fun make(apiBase: String, appVersion: String, okHttp: OkHttpClient = OkHttpClient()): RelayAccountClient =
        RelayAccountClient(api(apiBase, appVersion, okHttp))

    /** The connector that opens Link sessions through the same relay, with the vault's token and phone key.
     *  [appVersion] is also the `client_version` of the Link `hello`. Throws as [make]. */
    fun makeConnector(
        apiBase: String,
        appVersion: String,
        vault: AccountVault,
        deviceName: String,
        okHttp: OkHttpClient = OkHttpClient(),
    ): MachineLinkConnecting = RelayMachineConnector(api(apiBase, appVersion, okHttp), vault, headerVersion(appVersion), deviceName)

    private fun api(apiBase: String, appVersion: String, okHttp: OkHttpClient): RelayApi =
        RelayApi(apiBase, okHttp, headerVersion(appVersion))
}
