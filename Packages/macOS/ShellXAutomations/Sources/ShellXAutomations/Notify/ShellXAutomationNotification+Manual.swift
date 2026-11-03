public import Foundation

extension ShellXAutomationNotification {
    private static let manualBodyLimit = 180
    private static let panelLink = "shellx://automations"

    /// A banner asked for by `shellx routine notify`: titled `name`, linking automation `automationId` when known, else the Automations panel.
    public init(name: String, body: String, automationId: String?) {
        let truncated = body.count > Self.manualBodyLimit ? String(body.prefix(Self.manualBodyLimit)) + "…" : body
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
