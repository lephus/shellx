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
    /// Kept only when present, well formed and usable; never fails the draft.
    var flow: ShellXAutomationFlow?

    private enum CodingKeys: String, CodingKey {
        case kind, name, description, schedule, workingDirectory, notify, allowedTools, steps, skillMarkdown, flow
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(ShellXAutomationKind.self, forKey: .kind)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        schedule = try c.decodeIfPresent(ShellXSchedule.self, forKey: .schedule)
        workingDirectory = try c.decodeIfPresent(String.self, forKey: .workingDirectory)
        notify = try c.decodeIfPresent(Notify.self, forKey: .notify)
        allowedTools = try c.decodeIfPresent([String].self, forKey: .allowedTools)
        steps = try c.decodeIfPresent([ShellXWorkflowStep].self, forKey: .steps)
        skillMarkdown = try c.decodeIfPresent(String.self, forKey: .skillMarkdown)
        let decoded = try? c.decodeIfPresent(ShellXAutomationFlow.self, forKey: .flow)
        flow = decoded.flatMap { $0 }.flatMap { $0.isUsable ? $0 : nil }
    }

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
            skillMarkdown: skillMarkdown ?? "",
            flow: flow
        )
    }
}
