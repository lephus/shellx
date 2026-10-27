import ShellXAppCore
import SwiftUI

/// Reviews an agent's plan: the plan as Markdown, scrollable; "Approve" (mode `manual`), the other
/// approval modes in "Other modes", "Revise…" (sends `deny` with the user's feedback: required, at
/// most 4096 bytes, counted as it is typed) and "Deny". Only the modes the Mac offers show. When the
/// item was decided elsewhere meanwhile, the sheet says so and nothing can be sent.
struct PlanReviewSheet: View {
    let item: MachinePendingItem
    let state: PendingSheetState
    let send: (LinkDecision) -> Void
    let close: () -> Void

    @State private var revising: Bool
    @State private var feedback: String
    /// The decision last sent from here, for "Try again".
    @State private var last: LinkDecision?
    @FocusState private var feedbackFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    /// `revising` and `feedback` start a render test in the feedback step.
    init(
        item: MachinePendingItem, state: PendingSheetState, send: @escaping (LinkDecision) -> Void,
        close: @escaping () -> Void, revising: Bool = false, feedback: String = ""
    ) {
        self.item = item
        self.state = state
        self.send = send
        self.close = close
        _revising = State(initialValue: revising)
        _feedback = State(initialValue: feedback)
    }

    private var actions: [PendingAction] { item.item.actions }
    private var approvals: [ExitPlanMode] {
        actions.compactMap {
            guard case let .approvePlan(mode) = $0 else { return nil }
            return mode
        }
    }
    private var trimmedFeedback: String { feedback.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var feedbackBytes: Int { trimmedFeedback.utf8.count }
    private var canSendFeedback: Bool {
        state.canSend && !trimmedFeedback.isEmpty && feedbackBytes <= DecisionCenter.maxFeedbackBytes
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(PendingCardView.headline(for: item, showsMachineName: false))
                        .font(.subheadline)
                    if let plan = item.item.planPreview, !plan.isEmpty {
                        PlanMarkdownText(markdown: plan)
                        if PendingItem.previewMayBeCut(plan) { CutNotice() }
                    } else {
                        Label {
                            Text(LocalizedStringResource("pending.plan.missing"))
                        } icon: {
                            Image(systemName: "macbook")
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemBackground))
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle(String(localized: "pending.plan.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close"), action: close)
                        .accessibilityIdentifier("pending.close")
                }
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            PendingCardStatusLine(
                status: state.shownStatus, actionable: state.actionable, machineName: item.machineName,
                retry: resend)
            if state.handledElsewhere {
                wideButton(LocalizedStringResource("common.close"), primary: true, action: close)
            } else if revising {
                feedbackStep
            } else {
                decisionButtons
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// "Approve" with the other modes in a "…" menu beside it (as on a permission card), then
    /// "Revise…" and "Deny"; stacked at the accessibility text sizes.
    @ViewBuilder private var decisionButtons: some View {
        let stacked = typeSize.isAccessibilitySize
        let rows = stacked ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        if let first = approvals.first {
            rows {
                wideButton(Self.title(first), primary: true) { decide(.exitPlan(first, feedback: nil)) }
                    .accessibilityIdentifier("pending.approve")
                if approvals.count > 1 { otherModes(stacked: stacked) }
            }
            .disabled(!state.canSend)
        }
        rows {
            if actions.contains(.revisePlan) {
                wideButton(LocalizedStringResource("pending.plan.revise"), primary: false) {
                    revising = true
                    feedbackFocused = true
                }
                .accessibilityIdentifier("pending.revise")
            }
            if actions.contains(.rejectPlan) {
                Button { decide(.exitPlan(.deny, feedback: nil)) } label: {
                    Text(LocalizedStringResource("pending.deny"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(SecondaryButtonStyle(color: Color("StatusError")))
                .accessibilityIdentifier("pending.reject")
            }
        }
        .disabled(!state.canSend)
    }

    private func otherModes(stacked: Bool) -> some View {
        Menu {
            Section(String(localized: "pending.plan.otherModes")) {
                ForEach(Array(approvals.dropFirst().enumerated()), id: \.offset) { _, mode in
                    Button { decide(.exitPlan(mode, feedback: nil)) } label: { Text(Self.title(mode)) }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color("AccentText"))
                .frame(minWidth: 50, minHeight: 50)
                .frame(maxWidth: stacked ? .infinity : nil)
                .background(Color("AccentText").opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                .opacity(state.canSend ? 1 : 0.4)
        }
        .accessibilityLabel(Text(LocalizedStringResource("pending.plan.otherModes")))
        .accessibilityIdentifier("pending.otherModes")
    }

    private var feedbackStep: some View {
        VStack(spacing: 8) {
            TextField(String(localized: "pending.plan.feedback"), text: $feedback, axis: .vertical)
                .lineLimit(2...6)
                .focused($feedbackFocused)
                .padding(10)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("pending.feedback")
            ByteCounter(used: feedbackBytes, limit: DecisionCenter.maxFeedbackBytes)
            HStack(spacing: 8) {
                wideButton(LocalizedStringResource("common.cancel"), primary: false) {
                    revising = false
                    feedbackFocused = false
                }
                wideButton(LocalizedStringResource("pending.plan.sendFeedback"), primary: true) {
                    guard canSendFeedback else { return }
                    feedbackFocused = false
                    decide(.exitPlan(.deny, feedback: trimmedFeedback))
                }
                .disabled(!canSendFeedback)
                .accessibilityIdentifier("pending.sendFeedback")
            }
        }
    }

    @ViewBuilder private func wideButton(
        _ title: LocalizedStringResource, primary: Bool, action: @escaping () -> Void
    ) -> some View {
        let label = Text(title)
            .font(primary ? .headline : .body)
            .frame(maxWidth: .infinity, minHeight: 44)
        if primary {
            Button(action: action) { label }
                .buttonStyle(PrimaryButtonStyle())
        } else {
            Button(action: action) { label }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func decide(_ decision: LinkDecision) {
        last = decision
        send(decision)
    }

    private func resend() {
        if let last { send(last) }
    }

    static func title(_ mode: ExitPlanMode) -> LocalizedStringResource {
        switch mode {
        case .autoAccept: return LocalizedStringResource("pending.plan.autoAccept")
        case .ultraplan: return LocalizedStringResource("pending.plan.ultraplan")
        default: return LocalizedStringResource("pending.plan.approve")
        }
    }
}
