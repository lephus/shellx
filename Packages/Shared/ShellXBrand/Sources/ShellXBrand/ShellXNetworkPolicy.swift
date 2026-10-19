import Foundation

/// Hosts ShellX never contacts: Manaflow's services (cmux.com/dev, the cmux
/// relays and workers, Stack Auth, CodeRouter) and the telemetry vendors cmux
/// ships with (Sentry, PostHog, Axiom). `tests/test_shellx_no_phone_home.py`
/// parses this list for its static scan, and the Wave 1 network audit checks
/// live traffic against it.
public enum ShellXNetworkPolicy {
    /// A dotted entry matches that host and its subdomains. A bare name
    /// (`manaflow`) matches any host label that starts with it, and an
    /// organization path on a code host (`github.com/manaflow-ai/...`).
    public static let forbiddenHosts: [String] = [
        "cmux.com",
        "cmux.dev",
        "manaflow",
        "stack-auth.com",
        "sentry.io",
        "posthog.com",
        "axiom.co",
        "coderouter.dev",
        "workers.dev",
        "relay.cmux.dev",
    ]

    /// Whether `host` is one of ``forbiddenHosts`` or below one.
    public static func isForbidden(host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty else { return false }
        return forbiddenHosts.contains { entry in
            if entry.contains(".") {
                return host == entry || host.hasSuffix("." + entry)
            }
            return host.split(separator: ".").contains { $0.hasPrefix(entry) }
        }
    }

    /// Whether `url` reaches a forbidden host, or a forbidden organization's
    /// path on a code host.
    public static func isForbidden(url: URL) -> Bool {
        if let host = url.host, isForbidden(host: host) {
            return true
        }
        let owner = url.pathComponents.dropFirst().first?.lowercased() ?? ""
        return forbiddenHosts.contains { !$0.contains(".") && owner.hasPrefix($0) }
    }
}
