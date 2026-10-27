import Foundation

/// Builds the whole text of a `SpeechAnalyzer` dictation from its results: finalized segments in
/// order, then the newest tentative (volatile) tail, which each new tentative result replaces.
///
/// Apple's documentation does not say whether a segment carries its leading space, so pieces are
/// joined with one space only when neither side already has whitespace there.
public struct TranscriptAccumulator: Equatable, Sendable {
    private var finalized = ""
    private var volatile = ""

    public init() {}

    /// The text so far.
    public var text: String { Self.join(finalized, volatile) }

    /// Takes one result and returns the whole text so far.
    public mutating func take(_ piece: String, isFinal: Bool) -> String {
        if isFinal {
            finalized = Self.join(finalized, piece)
            volatile = ""
        } else {
            volatile = piece
        }
        return text
    }

    private static func join(_ left: String, _ right: String) -> String {
        guard let last = left.last, let first = right.first else { return left + right }
        return last.isWhitespace || first.isWhitespace ? left + right : left + " " + right
    }
}
