import Foundation
import os

/// The ShellX servers the app talks to.
///
/// Release builds always use ``production``. A Debug build takes `SHELLX_API_BASE` from its
/// environment when it is an `https` URL, or an `http` URL to the loopback host (`localhost`,
/// `127.0.0.0/8`, `::1`), so a relay running on the Mac is reachable from the simulator. Any other
/// value is dropped with the log line `api_override_rejected`.
public struct ShellXEndpoints: Equatable, Sendable {
    public static let production = URL(string: "https://relay.shellx.pro")!

    /// The environment variable a Debug build reads its API base from.
    public static let overrideVariable = "SHELLX_API_BASE"

    public let apiBase: URL

    public init(debugBuild: Bool, environment: [String: String]) {
        guard debugBuild, let raw = environment[Self.overrideVariable], !raw.isEmpty else {
            apiBase = Self.production
            return
        }
        guard let url = Self.acceptedOverride(raw) else {
            Logger(subsystem: "com.shellx.app", category: "config").notice("api_override_rejected")
            apiBase = Self.production
            return
        }
        apiBase = url
    }

    private static func acceptedOverride(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty
        else { return nil }
        switch scheme {
        case "https":
            return url
        case "http":
            return isLoopback(host) ? url : nil
        default:
            return nil
        }
    }

    private static func isLoopback(_ host: String) -> Bool {
        let bare = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
        if bare == "localhost" || bare == "::1" { return true }
        let octets = bare.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        let values = octets.compactMap { octet -> Int? in
            guard !octet.isEmpty, octet.count <= 3, octet.allSatisfy(\.isASCII), octet.allSatisfy(\.isNumber) else {
                return nil
            }
            return Int(octet)
        }
        return values.count == 4 && values[0] == 127 && values.allSatisfy { $0 <= 255 }
    }
}
