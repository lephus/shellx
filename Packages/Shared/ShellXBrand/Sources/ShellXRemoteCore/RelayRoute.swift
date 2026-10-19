import Foundation

public enum RelayRouteError: Error, Equatable, Sendable { case unsupported }

public enum RelayRoute {
    /// D6: `wss://host/path` becomes `relay+wss://host/path`, `ws://` becomes `relay+ws://`; the path is kept.
    public static func cmuxRoute(from url: String) throws -> String {
        guard let c = URLComponents(string: url), let scheme = c.scheme?.lowercased(),
              scheme == "wss" || scheme == "ws", let host = c.host, !host.isEmpty
        else { throw RelayRouteError.unsupported }
        return "relay+" + url
    }
}
