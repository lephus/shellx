import Foundation
import ShellXLinkAccount

/// Builds the relay client the app uses.
public enum RelayClientFactory {
    /// The relay stores `X-ShellX-Version` only when it is exactly `major.minor.patch`
    /// (`^\d{1,6}\.\d{1,6}\.\d{1,6}$`), the form the Mac app sends. So the app sends its bare marketing
    /// version, or `0.0.0` when that is not in this form.
    public static func headerVersion(for appVersion: String) -> String {
        appVersion.wholeMatch(of: /[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}/) != nil ? appVersion : "0.0.0"
    }

    /// `apiBase` must be `https` (or loopback `http`); `ShellXEndpoints` only hands out such URLs.
    public static func make(
        apiBase: URL, appVersion: String, session: URLSession = .shared
    ) throws -> any RelayAccountCalling {
        try api(apiBase: apiBase, appVersion: appVersion, session: session)
    }

    /// The connector that opens Link sessions through the same relay, with the vault's token and
    /// phone key. `appVersion` is also the `client_version` of the Link `hello`.
    public static func makeConnector(
        apiBase: URL, appVersion: String, vault: AccountVault, deviceName: String, session: URLSession = .shared
    ) throws -> any MachineLinkConnecting {
        RelayMachineConnector(
            api: try api(apiBase: apiBase, appVersion: appVersion, session: session), vault: vault,
            clientVersion: headerVersion(for: appVersion), deviceName: deviceName)
    }

    private static func api(apiBase: URL, appVersion: String, session: URLSession) throws -> RelayAPI {
        try RelayAPI(baseURL: apiBase, session: session, clientVersion: headerVersion(for: appVersion))
    }
}
