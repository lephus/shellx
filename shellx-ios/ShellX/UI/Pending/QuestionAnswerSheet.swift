import ShellXAppCore
import SwiftUI

/// Answers an agent's questions: one page per question, its options as a checklist, and an
/// "Other…" row that opens a field for an answer in the user's own words. "Send" turns on once
/// every question has an answer that fits the wire (1024 bytes each): a field holding more, or
/// picks that join to more, is counted and said, never cut silently. When the item was decided
/// elsewhere meanwhile, the sheet says so and nothing can be sent.
///
/// With a `VoiceService` in the environment, "Answer by voice" (in the bottom bar, outside the list)
/// listens: words that pick exactly one option (`PendingQuestion.option(matching:)`) mark it;
/// anything else becomes the "Other…" answer, shown in its field with "That didn't match an option".
/// Nothing is sent until the user taps Send. Opening the "Other…" field cancels a dictation.
struct QuestionAnswerSheet: View {
    let item: MachinePendingItem
    let state: PendingSheetState
    let send: (LinkDecision) -> Void
    let close: () -> Void

    @State private var draft: QuestionDraft
    @State private var page: Int
    /// Questions whose "Other…" field is open.
    @State private var typing: Set<String>
    /// Each "Other…" field as typed. The draft keeps at most `QuestionDraft.maxAnswerBytes` of it;
    /// the field keeps all, so the counter can say it is too long.
    @State private var typed: [String: String]
    /// Questions whose last spoken answer matched no option (it is their "Other…" answer now).
    @State private var unmatched: Set<String>
    @State private var ownVoice: VoiceInputModel?
    @FocusState private var focused: String?
    @Environment(VoiceService.self) private var voiceService: VoiceService?
    private let injectedVoice: VoiceInputModel?

    /// `draft`, `page`, `typing` and `freeText` (typed answers by question id) start a render test
    /// somewhere other than the first page, empty; `voice` and `unmatched` show the mic's states.
    init(
        item: MachinePendingItem, state: PendingSheetState, send: @escaping (LinkDecision) -> Void,
        close: @escaping () -> Void, draft: QuestionDraft? = nil, page: Int = 0, typing: Set<String> = [],
        freeText: [String: String] = [:], voice: VoiceInputModel? = nil, unmatched: Set<String> = []
    ) {
        self.item = item
        self.state = state
        self.send = send
        self.close = close
        var start = draft ?? QuestionDraft(questions: item.item.questions ?? [])
        for (id, text) in freeText { start.setFreeText(questionID: id, text: text) }
        _draft = State(initialValue: start)
        _page = State(initialValue: page)
        _typing = State(initialValue: typing)
        _typed = State(initialValue: freeText)
        _unmatched = State(initialValue: unmatched)
        injectedVoice = voice
    }

    private var voice: VoiceInputModel? { injectedVoice ?? ownVoice }

    /// Some answer does not fit: a field holds more than `QuestionDraft.maxAnswerBytes` once
    /// trimmed, or a question's picks join to more. Send stays off and the sheet says why.
    static func tooLong(_ draft: QuestionDraft, typed: [String: String]) -> Bool {
        draft.questions.contains { question in
            draft.isTooLong(questionID: question.id)
                || QuestionDraft.freeTextBytes(typed[question.id] ?? "") > QuestionDraft.maxAnswerBytes
        }
    }

    private var tooLong: Bool { Self.tooLong(draft, typed: typed) }

    /// The field's text as typed (or as the draft has it, when it was never typed here).
    private func fieldText(_ question: PendingQuestion) -> String {
        typed[question.id] ?? draft.freeText(questionID: question.id)
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
        .onAppear {
            if injectedVoice == nil, ownVoice == nil {
                ownVoice = voiceService?.makeModel(maxBytes: QuestionDraft.maxAnswerBytes)
            }
        }
        // The sheet closed, or the answers can no longer change (the mic goes): the microphone stops.
        .onDisappear {
            let voice = self.voice
            Task { await voice?.cancel() }
        }
        .onChange(of: editable) { _, canEdit in
            guard !canEdit else { return }
            let voice = self.voice
            Task { await voice?.cancel() }
        }
        // A swipe up on the mic opens the "Other…" field.
        .onChange(of: voice?.wantsKeyboard ?? false, initial: true) { _, wants in
            guard wants, let question else { return }
            voice?.wantsKeyboard = false
            openOther(question)
        }
        // Typing in an "Other…" field cancels a dictation in progress.
        .onChange(of: focused) { _, field in
            guard field != nil else { return }
            let voice = self.voice
            Task { await voice?.typeInstead() }
        }
    }

    /// Opens the question's "Other…" field and its keyboard. A dictation in progress is cancelled
    /// first (`VoiceInputModel.typeInstead()`).
    private func openOther(_ question: PendingQuestion) {
        let voice = self.voice
        typing.insert(question.id)
        Task { @MainActor in
            await voice?.typeInstead()
            // The field appeared in the update before; focus it now.
            focused = question.id
        }
    }

    // MARK: - Voice

    /// "Answer by voice", in the bottom bar (outside the list, so holding the mic never scrolls it):
    /// the words as they come, then the mic and its label. ("That didn't match an option" shows under
    /// the options, by the "Other…" field the words went into.)
    private func voiceRow(_ question: PendingQuestion, voice: VoiceInputModel) -> some View {
        VStack(spacing: 6) {
            VoiceStatusView(model: voice, level: voiceService?.meter.level ?? 0)
            HStack(spacing: 12) {
                MicButton(
                    model: voice, label: LocalizedStringResource("pending.question.voice"),
                    onOutcome: { answer(question, bySaying: $0.words) },
                    onKeyboard: { openOther(question) })
                Text(LocalizedStringResource("pending.question.voice"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            }
        }
    }

    /// A spoken answer marks the one option it picks; otherwise it is the "Other…" answer, in its
    /// field to be read. Never sends.
    private func answer(_ question: PendingQuestion, bySaying words: String) {
        focused = nil
        if let option = question.option(matching: words) {
            if !draft.isSelected(questionID: question.id, label: option.label) {
                draft.toggle(questionID: question.id, label: option.label)
            }
            typed[question.id] = nil
            unmatched.remove(question.id)
            AccessibilityNotification.Announcement(option.label).post()
        } else {
            typed[question.id] = words
            draft.setFreeText(questionID: question.id, text: words)
            typing.insert(question.id)
            unmatched.insert(question.id)
            AccessibilityNotification.Announcement(String(localized: "pending.question.voice.noMatch")).post()
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
                    // A pick replaces the typed answer, in the field too.
                    typed[question.id] = nil
                    unmatched.remove(question.id)
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
        } footer: {
            if draft.isTooLong(questionID: question.id) {
                let used = draft.answerBytes(questionID: question.id)
                Text(verbatim: String(localized: "pending.question.choicesTooLong \(used) \(QuestionDraft.maxAnswerBytes)"))
                    .foregroundStyle(Color("StatusError"))
            } else if unmatched.contains(question.id) {
                // Under the "Other…" field the spoken words went into.
                Label {
                    Text(LocalizedStringResource("pending.question.voice.noMatch"))
                } icon: {
                    Image(systemName: "questionmark.circle")
                }
                .foregroundStyle(Color("AccentText"))
                .accessibilityIdentifier("pending.voice.noMatch")
            }
        }
    }

    @ViewBuilder private func otherRows(_ question: PendingQuestion) -> some View {
        let text = fieldText(question)
        let answeredByText = QuestionDraft.freeTextBytes(text) > 0
        Button {
            openOther(question)
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
                        get: { fieldText(question) },
                        set: {
                            typed[question.id] = $0
                            draft.setFreeText(questionID: question.id, text: $0)
                        }),
                    axis: .vertical
                )
                .lineLimit(1...5)
                .focused($focused, equals: question.id)
                .frame(minHeight: 44)
                .accessibilityIdentifier("pending.otherField")
                ByteCounter(used: QuestionDraft.freeTextBytes(text), limit: QuestionDraft.maxAnswerBytes)
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let voice, editable, let question {
                voiceRow(question, voice: voice)
            }
            PendingCardStatusLine(
                status: state.shownStatus, actionable: state.actionable, machineName: item.machineName,
                retry: sendDraft)
            if tooLong, !state.handledElsewhere {
                Label {
                    Text(LocalizedStringResource("pending.question.tooLong"))
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                }
                .font(.footnote)
                .foregroundStyle(Color("StatusError"))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
            .disabled(!(state.canSend && draft.isComplete && !tooLong))
            .accessibilityIdentifier("pending.send")
        }
    }

    private func sendDraft() {
        guard !tooLong, let decision = draft.decision else { return }
        focused = nil
        send(decision)
    }
}
