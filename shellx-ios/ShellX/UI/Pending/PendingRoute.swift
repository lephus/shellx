import ShellXAppCore

/// The sheet open over the pending cards, and the model that follows its item.
struct PendingRoute: Identifiable {
    enum Kind: Equatable {
        /// `QuestionAnswerSheet`.
        case question
        /// `PlanReviewSheet`.
        case plan
        /// `FullTextSheet`: everything a permission's preview holds.
        case fullText
    }

    let kind: Kind
    let model: PendingSheetModel
    let id: PendingKey

    @MainActor
    init(kind: Kind, model: PendingSheetModel) {
        self.kind = kind
        self.model = model
        id = model.key
    }

    /// The sheet that shows all of `item`: its answer or review sheet, or the full text.
    static func kind(for item: PendingItem) -> Kind {
        switch item.kind {
        case .question where item.actions == [.answer]: return .question
        case .exitPlan where item.actions != [.openOnMac]: return .plan
        default: return .fullText
        }
    }
}
