import ShellXAppCore
import SwiftUI

/// One pending request as a card: who asks and what (`workspace · agent`, the Mac when there are
/// several, the kind of request), up to three lines of what it is about, then its buttons.
///
/// The buttons come from `PendingItem.actions`: a permission shows Deny and Allow (the primary
/// button), with "Always allow" and "All tools" in the "…" menu, as `PermissionLayout` (ShellXAppCore)
/// lays them out; a question opens the answer sheet, a
/// plan the review sheet; anything else says to open it on the Mac. The buttons are off while the
/// card cannot act (reconnecting, or its decision is out or taken). No hub here, so render tests
/// can show every kind and state.
struct PendingCardView: View {
    struct Actions {
        /// A button that decides at once (Allow, Deny, Always allow, All tools).
        var decide: (LinkDecision) -> Void = { _ in }
        /// "Answer" or "Review plan": the item's sheet.
        var openSheet: () -> Void = {}
        /// "Show more": everything the preview cut.
        var showMore: () -> Void = {}
        /// "Try again" after no answer.
        var retry: () -> Void = {}
    }

    let item: MachinePendingItem
    let status: DecisionStatus?
    /// Two or more Macs are paired: the header names this one.
    let showsMachineName: Bool
    var actions = Actions()

    @Environment(\.dynamicTypeSize) private var typeSize

    private var pending: PendingItem { item.item }

    /// The buttons act: the Mac is live and synced, and no decision is out or taken.
    private var enabled: Bool {
        guard item.actionable else { return false }
        switch status {
        case .sending, .done, .handledElsewhere: return false
        case .failed, nil: return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let preview = pending.previewText, !preview.isEmpty {
                switch pending.kind {
                case .permission:
                    CommandPreview(text: preview, style: .command, showMore: actions.showMore)
                case .exitPlan:
                    CommandPreview(
                        text: PlanMarkdownText.summary(preview), style: .markdown, showMore: actions.showMore)
                default:
                    CommandPreview(text: preview, style: .prose, showMore: actions.showMore)
                }
            }
            PendingCardStatusLine(
                status: status, actionable: item.actionable, machineName: item.machineName, retry: actions.retry)
            buttons
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
        .overlay { shape.strokeBorder(Color("AccentColor").opacity(0.55), lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pending.card")
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            StatusDot(color: Color("StatusNeedsYou"))
            Text(Self.headline(for: item, showsMachineName: showsMachineName))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: Self.spokenHeadline(for: item, showsMachineName: showsMachineName)))
        .accessibilityAddTraits(.isHeader)
    }

    /// "**shellx** · Claude Code · MacBook Pro · wants to run Bash".
    static func headline(for item: MachinePendingItem, showsMachineName: Bool) -> AttributedString {
        var workspace = AttributedString(item.item.workspaceTitle)
        workspace.font = .subheadline.weight(.semibold)
        let parts = details(for: item, showsMachineName: showsMachineName)
        var rest = AttributedString(" · " + parts.joined(separator: " · "))
        rest.foregroundColor = Color.secondary
        return workspace + rest
    }

    /// "shellx, Claude Code, MacBook Pro, wants to run Bash" for VoiceOver.
    static func spokenHeadline(for item: MachinePendingItem, showsMachineName: Bool) -> String {
        ([item.item.workspaceTitle] + details(for: item, showsMachineName: showsMachineName)).joined(separator: ", ")
    }

    private static func details(for item: MachinePendingItem, showsMachineName: Bool) -> [String] {
        var parts: [String] = []
        let agent = AgentLabel(agent: item.item.agent).text
        if !agent.isEmpty { parts.append(agent) }
        if showsMachineName { parts.append(item.machineName) }
        parts.append(kindText(item.item))
        return parts
    }

    /// "wants to run Bash", "asks", "proposes a plan".
    static func kindText(_ item: PendingItem) -> String {
        switch item.kind {
        case .permission:
            if let tool = item.toolName, !tool.isEmpty { return String(localized: "pending.kind.permission \(tool)") }
            return String(localized: "pending.kind.permission.noTool")
        case .question:
            return String(localized: "pending.kind.question")
        case .exitPlan:
            return String(localized: "pending.kind.plan")
        case .other:
            return String(localized: "pending.kind.other")
        }
    }

    // MARK: - Buttons

    @ViewBuilder private var buttons: some View {
        let offered = pending.actions
        if offered == [.openOnMac] {
            Label {
                Text(LocalizedStringResource("pending.openOnMac"))
            } icon: {
                Image(systemName: "macbook")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
        } else {
            switch pending.kind {
            case .permission:
                permissionButtons(PermissionLayout(offered))
            case .question:
                sheetButton(title: LocalizedStringResource("pending.answer"), systemImage: "text.bubble")
            default:
                sheetButton(title: LocalizedStringResource("pending.reviewPlan"), systemImage: "list.bullet.clipboard")
            }
        }
    }

    private func permissionButtons(_ layout: PermissionLayout) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let row = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return row {
            ForEach(Array(layout.buttons.enumerated()), id: \.offset) { _, action in
                decisionButton(action)
            }
            if !layout.menu.isEmpty {
                Menu {
                    ForEach(Array(layout.menu.enumerated()), id: \.offset) { _, action in
                        Button { decide(action) } label: { Text(action.title) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color("AccentText"))
                        .frame(minWidth: 50, minHeight: 50)
                        .frame(maxWidth: stacked || layout.buttons.isEmpty ? .infinity : nil)
                        .background(Color("AccentText").opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                        .opacity(enabled ? 1 : 0.4)
                }
                .accessibilityLabel(Text(LocalizedStringResource("pending.more")))
                .accessibilityIdentifier("pending.more")
            }
        }
        .disabled(!enabled)
    }

    @ViewBuilder private func decisionButton(_ action: PendingAction) -> some View {
        let title = Text(action.title)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
        if action == .deny {
            Button { decide(action) } label: { title }
                .buttonStyle(SecondaryButtonStyle(color: Color("StatusError")))
                .accessibilityIdentifier("pending.deny")
        } else {
            Button { decide(action) } label: { title }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("pending.allow")
        }
    }

    private func sheetButton(title: LocalizedStringResource, systemImage: String) -> some View {
        Button(action: actions.openSheet) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!enabled)
        .accessibilityIdentifier("pending.open")
    }

    private func decide(_ action: PendingAction) {
        guard let decision = action.decision else { return }
        actions.decide(decision)
    }
}

extension PendingAction {
    /// The title of a button that decides at once.
    fileprivate var title: LocalizedStringResource {
        switch self {
        case .allowOnce: return LocalizedStringResource("pending.allow")
        case .deny, .rejectPlan: return LocalizedStringResource("pending.deny")
        case .allowAlways: return LocalizedStringResource("pending.allowAlways")
        case .allowAllTools: return LocalizedStringResource("pending.allowAllTools")
        case .answer: return LocalizedStringResource("pending.answer")
        case .approvePlan: return LocalizedStringResource("pending.plan.approve")
        case .revisePlan: return LocalizedStringResource("pending.plan.revise")
        case .openOnMac: return LocalizedStringResource("pending.openOnMac")
        }
    }
}
