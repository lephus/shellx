public import Foundation

/// The URL scheme an app bundle registered for its own links, such as `shellx://automations`.
///
/// Read from `CFBundleURLTypes`: the first registered scheme that starts with `shellx`, so the release app
/// answers `shellx` and dev builds `shellx-dev`. Without one, the release scheme.
///
/// ```swift
/// let scheme = ShellXAppURLScheme(infoDictionary: Bundle.main.infoDictionary).scheme
/// ```
public struct ShellXAppURLScheme: Sendable, Equatable {
    /// The release app's scheme.
    public static let release = "shellx"

    /// The scheme links to this app use.
    public let scheme: String

    /// Reads the scheme from a bundle's info dictionary.
    /// - Parameter infoDictionary: The bundle's `Info.plist` contents, or nil.
    public init(infoDictionary: [String: Any]?) {
        let types = infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        scheme = schemes.first { $0.lowercased().hasPrefix(Self.release) }?.lowercased() ?? Self.release
    }
}
