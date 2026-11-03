import Foundation

/// A `shellx://automations` link, as an automation banner opens it.
///
/// Accepts exactly `shellx://automations` and `shellx://automations/<id>`, where the id
/// is one path segment of letters, digits, `-`, `_` or `:` (so `external:<name>` works).
/// Anything else, such as `shellx://auth/...`, a `..` segment, a query or another scheme,
/// is not an Automations link.
struct ShellXAutomationsURL: Equatable {
    static let scheme = "shellx"
    static let host = "automations"

    /// The automation to show, or nil for the list.
    let focusId: String?

    init?(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.scheme,
              components.host?.lowercased() == Self.host,
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil else {
            return nil
        }
        let path = components.percentEncodedPath
        if path.isEmpty || path == "/" {
            focusId = nil
            return
        }
        guard path.hasPrefix("/") else { return nil }
        var segment = path.dropFirst()
        if segment.hasSuffix("/") { segment = segment.dropLast() }
        guard !segment.isEmpty, segment.count <= 200,
              segment.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ":") }) else {
            return nil
        }
        focusId = String(segment)
    }
}
