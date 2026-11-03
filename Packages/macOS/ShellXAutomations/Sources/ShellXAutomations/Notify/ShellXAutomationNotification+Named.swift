public import Foundation

extension ShellXAutomationNotification {
    private static let bodyLimit = 180
    /// A banner titled `name` whose body is cut to 180 characters plus "…", linking automation `automationId` when known, else the Automations panel. Used for run outcomes and `shellx routine notify`.
    ///
    /// - Parameter urlScheme: The app's own URL scheme (``ShellXAppURLScheme``): `shellx` for the release app, `shellx-dev` for dev builds.
    public init(name: String, body: String, automationId: String?, urlScheme: String = ShellXAppURLScheme.release) {
        let panelLink = "\(urlScheme)://automations"
        let truncated = body.count > Self.bodyLimit ? String(body.prefix(Self.bodyLimit)) + "…" : body
        var segment = CharacterSet.urlPathAllowed
        segment.remove("/")
        let link = automationId
            .flatMap { $0.addingPercentEncoding(withAllowedCharacters: segment) }
            .flatMap { URL(string: "\(panelLink)/\($0)") }
        self.init(
            title: name,
            body: truncated,
            url: link ?? URL(string: panelLink) ?? URL(string: "\(ShellXAppURLScheme.release)://automations")!,
            group: automationId ?? name
        )
    }
}
