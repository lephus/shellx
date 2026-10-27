import Foundation
import ShellXLinkCore

extension PendingQuestion {
    /// The option a spoken answer picks, or nil when it picks none or more than one. Nil leaves the
    /// words to the question's typed answer (`QuestionDraft.setFreeText`), shown for review; a spoken
    /// answer is never sent by itself.
    ///
    /// Both sides are compared without Vietnamese diacritics (đ is d), case or punctuation:
    /// 1. an option whose words are exactly the words said wins when it is the only one;
    /// 2. otherwise an option matches when its label (two characters or more) is said as whole words
    ///    within the sentence, or when the sentence names its position: "1", "một", "thứ nhất",
    ///    "đầu tiên", "first", "số hai", "cái thứ hai", "number two"…; exactly one must match.
    public func option(matching transcript: String) -> PendingQuestionOption? {
        let said = SpokenWords(transcript)
        guard !said.words.isEmpty, !options.isEmpty else { return nil }
        let labels = options.map { SpokenWords($0.label) }

        let exact = labels.indices.filter { labels[$0].words == said.words }
        if exact.count == 1 { return options[exact[0]] }

        var matched = Set<Int>()
        for index in labels.indices where labels[index].letterCount >= 2 && said.contains(labels[index]) {
            matched.insert(index)
        }
        for position in said.positions() where options.indices.contains(position - 1) {
            matched.insert(position - 1)
        }
        guard matched.count == 1, let index = matched.first else { return nil }
        return options[index]
    }
}

/// Text reduced to lowercase words without diacritics or punctuation, for comparing what was said
/// with an option.
private struct SpokenWords {
    let words: [String]

    init(_ text: String) {
        let folded = text
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
        let spaced = String(folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " })
        words = spaced.split(separator: " ").map(String.init)
    }

    var letterCount: Int { words.reduce(0) { $0 + $1.count } }

    /// Whether `other`'s words appear here in a row.
    func contains(_ other: SpokenWords) -> Bool {
        let needle = other.words
        guard !needle.isEmpty, needle.count <= words.count else { return false }
        return (0...(words.count - needle.count)).contains { start in
            Array(words[start..<(start + needle.count)]) == needle
        }
    }

    // MARK: - Positions

    /// The 1-based positions named: an ordinal phrase anywhere ("thứ hai", "số 2", "đầu tiên",
    /// "second", "number two"), or a bare number when it is all that was said besides filler words
    /// ("2", "một", "đáp án hai"). A number inside other words ("chạy hai lần") is not a position.
    func positions() -> Set<Int> {
        var found = Set<Int>()
        for (index, word) in words.enumerated() {
            let next = index + 1 < words.count ? words[index + 1] : nil
            if let ordinal = Self.englishOrdinals[word] {
                found.insert(ordinal)
            } else if word == "dau", next == "tien" {
                found.insert(1)
            } else if word == "thu", let next, let value = Self.afterThu[next] ?? Self.number(next) {
                found.insert(value)
            } else if Self.numberMarkers.contains(word), let next, let value = Self.number(next) {
                found.insert(value)
            } else if index + 2 < words.count, Self.numberMarkerPairs.contains([word, words[index + 1]]),
                let value = Self.number(words[index + 2])
            {
                found.insert(value)
            }
        }
        let rest = words.filter { !Self.fillers.contains($0) }
        if rest.count == 1, let value = Self.number(rest[0]) { found.insert(value) }
        return found
    }

    private static func number(_ word: String) -> Int? {
        if let value = Int(word), (1...99).contains(value) { return value }
        return cardinals[word]
    }

    /// Cardinal numbers, folded: Vietnamese, then English.
    private static let cardinals: [String: Int] = [
        "mot": 1, "hai": 2, "ba": 3, "bon": 4, "nam": 5, "sau": 6, "bay": 7, "tam": 8, "chin": 9, "muoi": 10,
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10,
    ]

    /// Words that only follow "thứ": "thứ nhất", "thứ tư".
    private static let afterThu: [String: Int] = ["nhat": 1, "tu": 4]

    private static let englishOrdinals: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8,
        "ninth": 9, "tenth": 10, "1st": 1, "2nd": 2, "3rd": 3, "4th": 4, "5th": 5, "6th": 6, "7th": 7, "8th": 8,
        "9th": 9, "10th": 10,
    ]

    /// A word that makes the number after it a position: "số 2", "number two", "option 3".
    private static let numberMarkers: Set<String> = ["so", "number", "option", "choice", "answer"]
    /// Two words that do the same: "đáp án hai", "phương án 2", "lựa chọn ba".
    private static let numberMarkerPairs: Set<[String]> = [["dap", "an"], ["phuong", "an"], ["lua", "chon"]]

    /// Words said around a bare position: "cái", "số", "chọn", "nhé", "the", "pick"…
    private static let fillers: Set<String> = [
        "cai", "so", "thu", "dap", "an", "phuong", "lua", "chon", "nhe", "nha", "di", "a", "ah", "oi", "la",
        "the", "number", "option", "choice", "answer", "pick", "select", "please",
    ]
}
