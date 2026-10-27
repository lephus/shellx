import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// A spoken answer picks a question's option when exactly one option matches it: the same words
/// (ignoring Vietnamese diacritics, case and punctuation), the label said within the sentence, or
/// the option's position ("cái thứ hai", "first"). Anything else is the question's free text.
final class OptionMatchingTests: XCTestCase {
    private func question(_ labels: [String], multiSelect: Bool = false) -> PendingQuestion {
        PendingQuestion(
            id: "q", prompt: "Pick one", multiSelect: multiSelect,
            options: labels.enumerated().map { PendingQuestionOption(id: "o\($0.offset)", label: $0.element) })
    }

    private func picked(_ labels: [String], _ transcript: String) -> String? {
        question(labels).option(matching: transcript)?.label
    }

    func testMatchesIgnoringDiacriticsAndCase() {
        XCTAssertEqual(picked(["Postgres", "SQLite"], "postgres"), "Postgres")
        XCTAssertEqual(picked(["Giữ route v1", "Xoá route v1"], "giu route v1"), "Giữ route v1")
        XCTAssertEqual(picked(["Giữ route v1", "Xoá route v1"], "Xoá route V1."), "Xoá route v1")
        // đ has no combining mark; it still folds to d.
        XCTAssertEqual(picked(["Đừng xoá", "Xoá luôn"], "dung xoa"), "Đừng xoá")
        // The label said inside a sentence.
        XCTAssertEqual(picked(["Postgres", "SQLite"], "Mình chọn SQLite nhé!"), "SQLite")
        // Whole words only: "postgresql" is not "postgres".
        XCTAssertNil(picked(["Postgres", "SQLite"], "postgresql"))
        // A one-letter label is matched only when said alone.
        XCTAssertEqual(picked(["A", "B"], "b."), "B")
        XCTAssertNil(picked(["A", "B"], "a bit of both"))
    }

    func testOrdinalPicksOption() {
        let labels = ["Postgres", "SQLite", "MySQL"]
        XCTAssertEqual(picked(labels, "cái thứ hai"), "SQLite")
        for first in ["1", "một", "thứ nhất", "đầu tiên", "first", "số một", "the first one", "Cái đầu tiên nhé."] {
            XCTAssertEqual(picked(labels, first), "Postgres", first)
        }
        for second in ["2", "số hai", "Thứ hai.", "second", "number two", "đáp án hai"] {
            XCTAssertEqual(picked(labels, second), "SQLite", second)
        }
        XCTAssertEqual(picked(labels, "thứ ba"), "MySQL")
        XCTAssertEqual(picked(labels, "the third one"), "MySQL")
        // Past the last option: nothing.
        XCTAssertNil(picked(labels, "thứ năm"))
        XCTAssertNil(picked(labels, "0"))
        // A number inside other words is not a position.
        XCTAssertNil(picked(labels, "chạy hai lần"))
    }

    func testAmbiguousReturnsNil() {
        // Both labels said.
        XCTAssertNil(picked(["Chạy lint", "Chạy test"], "chạy lint rồi chạy test"))
        // A position and another option's label.
        XCTAssertNil(picked(["Postgres", "SQLite"], "Postgres, cái thứ hai"))
        // Two options with the same words.
        XCTAssertNil(picked(["Giữ", "giữ"], "giữ"))
        // The words of exactly one option win over options that are only contained in them.
        XCTAssertEqual(picked(["Yes", "Yes, and add tests"], "yes and add tests"), "Yes, and add tests")
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(picked(["Postgres", "SQLite"], "dùng MongoDB đi"))
        XCTAssertNil(picked(["Postgres", "SQLite"], ""))
        XCTAssertNil(picked(["Postgres", "SQLite"], "  ...  "))
        XCTAssertNil(question([]).option(matching: "postgres"))
    }

    func testNoMatchBecomesTheQuestionsFreeText() throws {
        // What the question sheet does with a spoken answer: a match picks the option, anything else
        // is the typed ("Other…") answer, shown for review; neither sends.
        let question = question(["Postgres", "SQLite"])
        var draft = QuestionDraft(questions: [question])
        let spoken = "Dùng MongoDB đi"
        XCTAssertNil(question.option(matching: spoken))
        draft.setFreeText(questionID: "q", text: spoken)
        XCTAssertEqual(draft.freeText(questionID: "q"), spoken)
        XCTAssertEqual(draft.decision, .question(selections: [spoken]))

        let match = try XCTUnwrap(question.option(matching: "cái thứ hai"))
        draft.toggle(questionID: "q", label: match.label)
        XCTAssertEqual(draft.decision, .question(selections: ["SQLite"]))
    }
}
