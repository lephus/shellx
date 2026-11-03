import Foundation
import ShellXAutomations

/// A `shellx://automations` link, as an automation banner opens it.
///
/// Accepts exactly `<scheme>://automations` and `<scheme>://automations/<id>` for the app's own
/// scheme (`shellx`, or `shellx-dev` for dev builds; see ``ShellXAppURLScheme``), where the id
/// is one path segment of letters, digits, `-`, `_` or `:` (so `external:<name>` works).
/// Anything else, such as `shellx://auth/...`, a `..` segment, a query or another scheme,
/// is not an Automations link.
struct ShellXAutomationsURL: Equatable {
    static let host = "automations"

    /// The automation to show, or nil for the list.
    let focusId: String?

    /// - Parameter scheme: The app's own URL scheme.
    init?(_ url: URL, scheme: String = ShellXAppURLScheme.release) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme.lowercased(),
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
