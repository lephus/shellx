public import Foundation

extension ShellXAutomationNotification {
    private static let bodyLimit = 180
    private static let panelLink = "shellx://automations"

    /// A banner titled `name` whose body is cut to 180 characters plus "…", linking automation `automationId` when known, else the Automations panel. Used for run outcomes and `shellx routine notify`.
    public init(name: String, body: String, automationId: String?) {
        let truncated = body.count > Self.bodyLimit ? String(body.prefix(Self.bodyLimit)) + "…" : body
        var segment = CharacterSet.urlPathAllowed
        segment.remove("/")
        let link = automationId
            .flatMap { $0.addingPercentEncoding(withAllowedCharacters: segment) }
            .flatMap { URL(string: "\(Self.panelLink)/\($0)") }
        self.init(
            title: name,
            body: truncated,
            url: link ?? URL(string: Self.panelLink)!,
            group: automationId ?? name
        )
    }
}
