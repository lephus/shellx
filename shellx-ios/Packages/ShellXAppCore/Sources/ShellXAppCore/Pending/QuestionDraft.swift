import Foundation
import ShellXLinkCore

/// The user's answers to a `question` item while its sheet is open: options picked per question,
/// or a typed answer ("Other…") instead.
///
/// `decision` follows PROTOCOL.md section 4 (Decision): one element per question, in the
/// questions' order; a typed answer as typed (trimmed), otherwise the picked option's label, or for
/// a multi-select question the picked labels in the options' order joined with ", ".
public struct QuestionDraft: Equatable, Sendable {
    /// The most UTF-8 bytes one answer may take on the wire.
    public static let maxAnswerBytes = 1024

    public let questions: [PendingQuestion]
    /// Picked labels, by question id.
    private var picked: [String: Set<String>] = [:]
    /// Typed answers, by question id, as typed (already cut to `maxAnswerBytes`).
    private var typed: [String: String] = [:]

    public init(questions: [PendingQuestion]) {
        self.questions = questions
    }

    /// Picks `label`, or for a multi-select question picks or unpicks it. A single-select question
    /// keeps one pick: the new one replaces the old, and picking it again keeps it. Any pick clears
    /// the question's typed answer. Unknown questions and labels are ignored.
    public mutating func toggle(questionID: String, label: String) {
        guard let question = questions.first(where: { $0.id == questionID }),
            question.options.contains(where: { $0.label == label })
        else { return }
        typed[questionID] = nil
        guard question.multiSelect else {
            picked[questionID] = [label]
            return
        }
        var labels = picked[questionID] ?? []
        if labels.remove(label) == nil { labels.insert(label) }
        picked[questionID] = labels.isEmpty ? nil : labels
    }

    /// The "Other…" answer of a question. Text that is not blank replaces the question's picks.
    /// Text over `maxAnswerBytes` UTF-8 bytes is cut on a character boundary.
    public mutating func setFreeText(questionID: String, text: String) {
        guard questions.contains(where: { $0.id == questionID }) else { return }
        let kept = Self.cut(text)
        typed[questionID] = kept.isEmpty ? nil : kept
        if !Self.trimmed(kept).isEmpty { picked[questionID] = nil }
    }

    public func isSelected(questionID: String, label: String) -> Bool {
        picked[questionID]?.contains(label) ?? false
    }

    /// The typed answer as the field shows it ("" when none).
    public func freeText(questionID: String) -> String {
        typed[questionID] ?? ""
    }

    public func isAnswered(questionID: String) -> Bool {
        questions.first { $0.id == questionID }.flatMap(answer) != nil
    }

    /// UTF-8 bytes of the answer the decision would carry for the question (0 when none).
    public func answerBytes(questionID: String) -> Int {
        questions.first { $0.id == questionID }.flatMap(answer)?.utf8.count ?? 0
    }

    /// The question has an answer, but too long for the wire: its picked labels joined pass
    /// `maxAnswerBytes`. `decision` is nil until fewer are picked; the sheet says why.
    public func isTooLong(questionID: String) -> Bool {
        answerBytes(questionID: questionID) > Self.maxAnswerBytes
    }

    /// UTF-8 bytes a typed answer takes once trimmed, as the decision would send it; never cut.
    /// The sheet counts with it while the field still holds more than `setFreeText` keeps.
    public static func freeTextBytes(_ text: String) -> Int {
        trimmed(text).utf8.count
    }

    /// Every question has an answer that fits the wire: `decision` is not nil.
    public var isComplete: Bool { decision != nil }

    /// The decision to send; nil until every question has an answer of 1 to `maxAnswerBytes` bytes.
    public var decision: LinkDecision? {
        guard !questions.isEmpty else { return nil }
        var selections: [String] = []
        for question in questions {
            guard let answer = answer(question), answer.utf8.count <= Self.maxAnswerBytes else { return nil }
            selections.append(answer)
        }
        return .question(selections: selections)
    }

    private func answer(_ question: PendingQuestion) -> String? {
        let text = Self.trimmed(typed[question.id] ?? "")
        if !text.isEmpty { return text }
        let chosen = picked[question.id] ?? []
        var labels: [String] = []
        for option in question.options where chosen.contains(option.label) && !labels.contains(option.label) {
            labels.append(option.label)
        }
        let joined = labels.joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `text` cut to at most `maxAnswerBytes` UTF-8 bytes, never inside a character.
    private static func cut(_ text: String) -> String {
        guard text.utf8.count > maxAnswerBytes else { return text }
        var kept = ""
        var used = 0
        for character in text {
            let size = character.utf8.count
            guard used + size <= maxAnswerBytes else { break }
            used += size
            kept.append(character)
        }
        return kept
    }
}
