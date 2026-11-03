public import Foundation

extension ShellXAutomationNotification {
    private static let manualBodyLimit = 180

    /// A banner asked for by `shellx routine notify`: titled `name`, linking automation `automationId` when known, else the Automations panel.
    public init(name: String, body: String, automationId: String?) {
        let truncated = body.count > Self.manualBodyLimit ? String(body.prefix(Self.manualBodyLimit)) + "…" : body
        let link = automationId.map { "shellx://automations/\($0)" } ?? "shellx://automations"
        self.init(
            title: name,
            body: truncated,
            url: URL(string: link) ?? URL(filePath: "/"),
            group: automationId ?? name
        )
    }
}
