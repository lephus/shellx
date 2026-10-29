import ShellXAppCore
import SwiftUI

/// One agent session as a card, on the home and in the session lists (mockup A): a dot coloured by the
/// group the session is in, its name (`SessionName`) and, to the right, a tag ("Needs you", how long
/// it has run, "Done", none once it ended or went idle); under them `workspace · agent`, the Mac when
/// several are paired and how long: since it began to wait ("2 minutes"), or ago for a session that
/// just finished, ended or went idle (a running one has its time in the tag); and, while it waits for
/// the user, its question in quotes. A needs-you card has the accent colour as its outline, and a card from a Mac
/// that is not online fades. The card is not a button itself: the list wraps it in a link.
struct FocusRowView: View {
    /// The group the session is in: it sets the dot, the tag and the outline.
    enum Kind: Equatable {
        case needsYou, running, justDone, ended
        /// A live session that finished its turn more than an hour ago (`OtherSessionsView`).
        case idle
    }

    let item: FocusItem
    let kind: Kind
    /// The clock the tag and "… ago" count from.
    let now: Date
    /// Two or more Macs are paired: the sub line names the Mac.
    let showsMachineName: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }
    private var color: Color { Color(Self.colorName(kind)) }

    /// The asset colour of the dot and the tag.
    static func colorName(_ kind: Kind) -> String {
        switch kind {
        case .needsYou: "StatusNeedsYou"
        case .running: "StatusRunning"
        case .justDone: "StatusDone"
        case .ended, .idle: "StatusIdle"
        }
    }

    /// "Needs you", how long the session has been running ("8 minutes"; "Running" when the Mac did not
    /// say since when), "Done", and nothing for an ended session.
    static func tag(for item: FocusItem, kind: Kind, now: Date) -> String? {
        switch kind {
        case .needsYou:
            return String(localized: "agent.state.needsYou")
        case .running:
            return AgentStatusRow(session: item.session, now: now).elapsed.map { ageText($0) }
                ?? String(localized: "agent.state.running")
        case .justDone:
            return String(localized: "agent.state.done")
        case .ended, .idle:
            return nil
        }
    }

    /// A duration in whole minutes, at least one: the rows redraw every 30 seconds, so a seconds count
    /// would freeze between redraws, and a `now` older than the start would show a negative age.
    static func ageText(_ elapsed: Duration) -> String {
        let seconds = max(0, elapsed.components.seconds)
        return AgentStateStyle.elapsedText(.seconds(max(1, seconds / 60) * 60))
    }

    /// The time at the end of the sub line, nil when the Mac gave none: needs you counts from when the
    /// agent began to wait ("2 minutes"); just done, ended and idle say "12 minutes ago"; running has
    /// its time in the tag.
    static func timeText(for item: FocusItem, kind: Kind, now: Date) -> String? {
        let session = item.session.session
        func since(_ ms: Int64?) -> Duration? {
            ms.map { .seconds(max(0, now.timeIntervalSince(Date(timeIntervalSince1970: Double($0) / 1000)))) }
        }
        switch kind {
        case .running:
            return nil
        case .needsYou:
            return (since(session.stateSinceMs) ?? since(session.lastActivityMs)).map { ageText($0) }
        case .justDone:
            return item.finishedAt.map { ago(.seconds(max(0, now.timeIntervalSince($0)))) }
        case .ended:
            return (since(session.stateSinceMs) ?? since(session.lastActivityMs)).map { ago($0) }
        case .idle:
            return since(session.lastActivityMs).map { ago($0) }
        }
    }

    private static func ago(_ elapsed: Duration) -> String {
        String(localized: "home.ago \(ageText(elapsed))")
    }

    /// "shellx · Claude Code", then the Mac's name when `showsMachineName`, then the time
    /// (`timeText(for:kind:now:)`). A session outside any workspace starts at the agent.
    static func subLine(for item: FocusItem, kind: Kind, now: Date, showsMachineName: Bool) -> String {
        let session = item.session
        var parts = [session.session.workspaceTitle, AgentLabel(agent: session.session.agent).text]
        if showsMachineName { parts.append(session.machineName) }
        if let time = timeText(for: item, kind: kind, now: now) { parts.append(time) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// What the agent asks, in quotes, on a needs-you card; nil otherwise.
    static func quotedQuestion(for item: FocusItem, kind: Kind) -> String? {
        guard kind == .needsYou, let question = item.question, !question.isEmpty else { return nil }
        return "\u{201C}\(question)\u{201D}"
    }

    var body: some View {
        let large = typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 3) {
            titleLine
            Text(verbatim: Self.subLine(for: item, kind: kind, now: now, showsMachineName: showsMachineName))
                .font(.footnote)
                .foregroundStyle(.secondary)
                // Two lines: the time at the end ("8 hours, 20 minutes ago") wraps by words, never cut.
                .lineLimit(large ? 4 : 2)
                .truncationMode(.tail)
            if let question = Self.quotedQuestion(for: item, kind: kind) {
                Text(verbatim: question)
                    .font(.footnote)
                    .foregroundStyle(Color("AccentText"))
                    .lineLimit(large ? 4 : 2)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color.appSurface, in: shape)
        .overlay { shape.strokeBorder(border, lineWidth: 1) }
        .contentShape(shape)
        .opacity(item.session.online ? 1 : 0.55)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.agent.\(item.session.machineID).\(item.session.session.sessionId)")
    }

    private var border: Color {
        kind == .needsYou ? Color("AccentColor").opacity(0.45) : Color.primary.opacity(0.1)
    }

    /// The dot and the name, with the tag beside them; under them at the accessibility text sizes, so
    /// neither breaks inside a word.
    private var titleLine: some View {
        let large = typeSize.isAccessibilitySize
        let layout = large
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                StatusDot(color: color)
                Text(verbatim: item.name)
                    .font(.headline)
                    .lineLimit(large ? 3 : 1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let tag = Self.tag(for: item, kind: kind, now: now) {
                Text(verbatim: tag)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .fixedSize()
            }
        }
    }
}
