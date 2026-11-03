/// Lenient wire form of a `shellx-draft` block: a draft emitted early may lack fields.
struct ShellXCreatorDraftPayload: Decodable {
    struct Notify: Decodable {
        var on: [ShellXNotifyEvent]?
        var targets: [ShellXNotifyTarget]?
    }

    var kind: ShellXAutomationKind
    var name: String?
    var description: String?
    var schedule: ShellXSchedule?
    var workingDirectory: String?
    var notify: Notify?
    var allowedTools: [String]?
    var steps: [ShellXWorkflowStep]?
    var skillMarkdown: String?

    /// The draft with missing values defaulted to empty.
    var draft: ShellXAutomationDraft {
        ShellXAutomationDraft(
            kind: kind,
            name: name ?? "",
            description: description ?? "",
            schedule: schedule,
            workingDirectory: workingDirectory,
            notify: ShellXNotifySettings(on: notify?.on ?? [], targets: notify?.targets ?? []),
            allowedTools: allowedTools ?? [],
            steps: steps ?? [],
            skillMarkdown: skillMarkdown ?? ""
        )
    }
}
