import ShellXAppCore
import ShellXLinkCore
import SwiftUI

/// Answers an agent's questions: one page per question, its options as a checklist, and an
/// "Other…" row that opens a field for an answer in the user's own words. "Send" turns on once
/// every question has an answer (`QuestionDraft.isComplete`). When the item was decided elsewhere
/// meanwhile, the sheet says so and nothing can be sent.
struct QuestionAnswerSheet: View {
    let item: MachinePendingItem
    let state: PendingSheetState
    let send: (LinkDecision) -> Void
    let close: () -> Void

    @State private var draft: QuestionDraft
    @State private var page: Int
    /// Questions whose "Other…" field is open.
    @State private var typing: Set<String>
    @FocusState private var focused: String?

    /// `draft`, `page` and `typing` start a render test somewhere other than the first page, empty.
    init(
        item: MachinePendingItem, state: PendingSheetState, send: @escaping (LinkDecision) -> Void,
        close: @escaping () -> Void, draft: QuestionDraft? = nil, page: Int = 0, typing: Set<String> = []
    ) {
        self.item = item
        self.state = state
        self.send = send
        self.close = close
        _draft = State(initialValue: draft ?? QuestionDraft(questions: item.item.questions ?? []))
        _page = State(initialValue: page)
        _typing = State(initialValue: typing)
    }

    private var questions: [PendingQuestion] { draft.questions }
    private var question: PendingQuestion? { questions.indices.contains(page) ? questions[page] : nil }
    private var isLastPage: Bool { page >= questions.count - 1 }
    /// Answers can change until the decision is out or the item is gone.
    private var editable: Bool {
        !state.handledElsewhere && state.status != .sending && state.status != .done
    }

    private var title: String {
        questions.count > 1
            ? String(localized: "pending.question.page \(page + 1) \(questions.count)")
            : String(localized: "pending.question.title")
    }

    var body: some View {
        NavigationStack {
            List {
                if let question {
                    promptSection(question)
                    optionsSection(question)
                }
            }
            .disabled(!editable)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close"), action: close)
                        .accessibilityIdentifier("pending.close")
                }
            }
        }
    }

    // MARK: - Question

    private func promptSection(_ question: PendingQuestion) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                if let header = question.header, !header.isEmpty {
                    Text(verbatim: header)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color("AccentText"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color("AccentText").opacity(0.14), in: Capsule())
                }
                Text(verbatim: question.prompt)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(
                    question.multiSelect
                        ? LocalizedStringResource("pending.question.pickMany")
                        : LocalizedStringResource("pending.question.pickOne")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text(PendingCardView.headline(for: item, showsMachineName: false))
                .font(.subheadline)
                .textCase(nil)
        }
    }

    private func optionsSection(_ question: PendingQuestion) -> some View {
        Section {
            ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
                let selected = draft.isSelected(questionID: question.id, label: option.label)
                Button {
                    draft.toggle(questionID: question.id, label: option.label)
                    focused = nil
                } label: {
                    ChoiceRow(selected: selected) {
                        Text(verbatim: option.label)
                            .foregroundStyle(Color.primary)
                        if let detail = option.description, !detail.isEmpty {
                            Text(verbatim: detail)
                                .font(.footnote)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("pending.option")
            }
            otherRows(question)
        }
    }

    @ViewBuilder private func otherRows(_ question: PendingQuestion) -> some View {
        let text = draft.freeText(questionID: question.id)
        let answeredByText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        Button {
            typing.insert(question.id)
            focused = question.id
        } label: {
            ChoiceRow(selected: answeredByText) {
                Text(LocalizedStringResource("pending.question.other"))
                    .foregroundStyle(Color.primary)
            }
        }
        .accessibilityAddTraits(answeredByText ? .isSelected : [])
        .accessibilityIdentifier("pending.other")
        if typing.contains(question.id) || !text.isEmpty {
            VStack(alignment: .trailing, spacing: 4) {
                TextField(
                    String(localized: "pending.question.otherPlaceholder"),
                    text: Binding(
                        get: { draft.freeText(questionID: question.id) },
                        set: { draft.setFreeText(questionID: question.id, text: $0) }),
                    axis: .vertical
                )
                .lineLimit(1...5)
                .focused($focused, equals: question.id)
                .frame(minHeight: 44)
                .accessibilityIdentifier("pending.otherField")
                ByteCounter(used: text.utf8.count, limit: QuestionDraft.maxAnswerBytes)
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            PendingCardStatusLine(
                status: state.shownStatus, actionable: state.actionable, machineName: item.machineName,
                retry: sendDraft)
            HStack(spacing: 8) {
                if page > 0, !state.handledElsewhere {
                    Button {
                        page -= 1
                    } label: {
                        Text(LocalizedStringResource("pending.question.back"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                mainButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder private var mainButton: some View {
        if state.handledElsewhere {
            Button(action: close) {
                Text(LocalizedStringResource("common.close"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(PrimaryButtonStyle())
        } else if !isLastPage {
            Button {
                focused = nil
                page += 1
            } label: {
                Text(LocalizedStringResource("pending.question.next"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!(question.map { draft.isAnswered(questionID: $0.id) } ?? false))
            .accessibilityIdentifier("pending.next")
        } else {
            Button(action: sendDraft) {
                Text(LocalizedStringResource("pending.send"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!(state.canSend && draft.isComplete))
            .accessibilityIdentifier("pending.send")
        }
    }

    private func sendDraft() {
        guard let decision = draft.decision else { return }
        focused = nil
        send(decision)
    }
}
