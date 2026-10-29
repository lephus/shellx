import XCTest

@testable import ShellXAppCore

/// The analyzer reports finalized segments and a tentative (volatile) tail. The whole text is the
/// finalized segments plus the newest tail; a space goes between two pieces only when neither side
/// already has whitespace there, so segments that carry their own spaces are not doubled.
final class TranscriptAccumulatorTests: XCTestCase {
    func testVolatileTailIsReplacedAndFinalSegmentsKept() {
        var text = TranscriptAccumulator()
        XCTAssertEqual(text.take("chạy", isFinal: false), "chạy")
        XCTAssertEqual(text.take("chạy test", isFinal: false), "chạy test")
        XCTAssertEqual(text.take("chạy test", isFinal: true), "chạy test")
        XCTAssertEqual(text.take("cho", isFinal: false), "chạy test cho")
        XCTAssertEqual(text.take("cho shellx", isFinal: false), "chạy test cho shellx")
        XCTAssertEqual(text.take("cho shellx.", isFinal: true), "chạy test cho shellx.")
        XCTAssertEqual(text.text, "chạy test cho shellx.")
    }

    func testSegmentsWithTheirOwnSpacesAreNotDoubled() {
        var text = TranscriptAccumulator()
        _ = text.take("Merge main", isFinal: true)
        XCTAssertEqual(text.take(" vào develop", isFinal: false), "Merge main vào develop")
        XCTAssertEqual(text.take(" vào develop.", isFinal: true), "Merge main vào develop.")

        var trailing = TranscriptAccumulator()
        _ = trailing.take("Tạo PR ", isFinal: true)
        XCTAssertEqual(trailing.take("cho branch develop", isFinal: true), "Tạo PR cho branch develop")
    }

    func testEmptyPiecesAddNothing() {
        var text = TranscriptAccumulator()
        XCTAssertEqual(text.take("", isFinal: false), "")
        XCTAssertEqual(text.take("push", isFinal: true), "push")
        XCTAssertEqual(text.take("", isFinal: false), "push")
        XCTAssertEqual(text.take("", isFinal: true), "push")
    }
}
