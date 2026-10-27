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
        try RelayAPI(baseURL: apiBase, session: session, clientVersion: headerVersion(for: appVersion))
    }
}
