import Foundation
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

/// One session's chat copy on the phone: entries merged by `id` (the higher `rev` wins), ordered by
/// `seq`, history pages joined or replacing a stale copy, and the newest 500 kept (PROTOCOL.md
/// sections 4 and 6).
final class ChatThreadTests: XCTestCase {
    private func entry(_ seq: Int, id: String? = nil, rev: Int = 1, text: String? = nil) -> ChatEntry {
        ChatEntry(
            id: id ?? "e-\(seq)", rev: rev, seq: seq, role: .agent, kind: .prose, text: text ?? "entry \(seq)",
            tsMs: 1_700_000_000_000 + Int64(seq))
    }

    private func entries(_ seqs: ClosedRange<Int>, text: String? = nil) -> [ChatEntry] {
        seqs.map { entry($0, text: text) }
    }

    func testUpsertKeepsHigherRevAndSortsBySeq() {
        var thread = ChatThread()
        thread.upsert([entry(3), entry(1), entry(2)])
        XCTAssertEqual(thread.entries.map(\.seq), [1, 2, 3])

        thread.upsert([entry(2, rev: 2, text: "edited"), entry(5), entry(4)])

        XCTAssertEqual(thread.entries.map(\.seq), [1, 2, 3, 4, 5])
        XCTAssertEqual(thread.entries.map(\.id), ["e-1", "e-2", "e-3", "e-4", "e-5"], "one entry per id")
        XCTAssertEqual(thread.entries.first { $0.seq == 2 }?.text, "edited")
        XCTAssertEqual(thread.entries.first { $0.seq == 2 }?.rev, 2)

        // Entries of one transcript line share a `seq` and keep the order they came in, also when
        // one of them is edited later.
        thread.upsert([entry(6, id: "6a"), entry(6, id: "6b")])
        thread.upsert([entry(6, id: "6a", rev: 2, text: "6a edited")])
        XCTAssertEqual(thread.entries.suffix(2).map(\.id), ["6a", "6b"])
        XCTAssertEqual(thread.entries.suffix(2).first?.text, "6a edited")
        XCTAssertFalse(thread.hasMore, "a live update says nothing about older entries")
    }

    func testLowerRevNeverOverwrites() {
        var thread = ChatThread()
        thread.applyLatestPage([entry(1), entry(2, rev: 1, text: "draft")], hasMore: false)
        // A live update edits entry 2 ...
        thread.upsert([entry(2, rev: 3, text: "final")])
        // ... then a history page the Mac sent before that edit arrives late.
        thread.applyLatestPage([entry(1), entry(2, rev: 2, text: "stale")], hasMore: false)
        XCTAssertEqual(thread.entries.map(\.text), ["entry 1", "final"])

        // An older page and a live push that repeat it change nothing either.
        thread.applyOlderPage([entry(2, rev: 1, text: "older page")], hasMore: false)
        thread.upsert([entry(2, rev: 3, text: "same rev, other text")])
        XCTAssertEqual(thread.entries.map(\.text), ["entry 1", "final"], "equal rev keeps what is there")
        XCTAssertEqual(thread.entries.map(\.rev), [1, 3])
    }

    func testLatestPageWithGapReplacesStaleCache() {
        // Last week's copy holds the first ten entries; the Mac's newest page starts at 100.
        var stale = ChatThread()
        stale.applyLatestPage(entries(1...10, text: "old"), hasMore: false)
        stale.applyLatestPage(entries(100...149), hasMore: true)
        XCTAssertEqual(stale.entries.map(\.seq), Array(100...149), "no hole between 10 and 100 is kept")
        XCTAssertTrue(stale.hasMore)

        // An entry pushed live while the page was on its way is newer than the page: it stays.
        var live = ChatThread()
        live.applyLatestPage(entries(1...10), hasMore: false)
        live.upsert([entry(150)])
        live.applyLatestPage(entries(100...149), hasMore: true)
        XCTAssertEqual(live.entries.map(\.seq), Array(100...150))
        XCTAssertTrue(live.hasMore)

        // A page that joins the copy (it starts right after it) is merged, and the copy still starts
        // at the first entry.
        var joined = ChatThread()
        joined.applyLatestPage(entries(1...60), hasMore: false)
        joined.applyLatestPage(entries(61...110), hasMore: true)
        XCTAssertEqual(joined.entries.map(\.seq), Array(1...110))
        XCTAssertFalse(joined.hasMore)

        // An overlapping page is merged too.
        var overlap = ChatThread()
        overlap.applyLatestPage(entries(1...60), hasMore: true)
        overlap.applyLatestPage(entries(41...90), hasMore: true)
        XCTAssertEqual(overlap.entries.map(\.seq), Array(1...90))
        XCTAssertTrue(overlap.hasMore)
    }

    func testOlderPagePrepends() {
        var thread = ChatThread()
        thread.applyLatestPage(entries(51...100), hasMore: true)
        XCTAssertTrue(thread.hasMore)

        thread.applyOlderPage(entries(21...50), hasMore: true)
        XCTAssertEqual(thread.entries.map(\.seq), Array(21...100))
        XCTAssertTrue(thread.hasMore)

        // The first page of the transcript: a line of two entries, then the rest.
        thread.applyOlderPage([entry(1, id: "1a"), entry(1, id: "1b")] + entries(2...20), hasMore: false)
        XCTAssertEqual(thread.entries.prefix(3).map(\.id), ["1a", "1b", "e-2"])
        XCTAssertEqual(thread.entries.count, 101)
        XCTAssertFalse(thread.hasMore)
    }

    func testThreadCapKeepsNewest() throws {
        // 600 entries of 4 KB each (the host's cap per entry).
        let text = String(repeating: "ệ", count: 1_365) + "a"
        XCTAssertEqual(text.utf8.count, ChatEntry.maxTextBytes)
        var thread = ChatThread()
        thread.applyLatestPage(entries(1...600, text: text), hasMore: false)

        XCTAssertEqual(ChatThread.maxEntries, 500)
        XCTAssertEqual(thread.entries.count, 500)
        XCTAssertEqual(thread.entries.first?.seq, 101)
        XCTAssertEqual(thread.entries.last?.seq, 600)
        XCTAssertTrue(thread.hasMore, "the dropped entries are still on the Mac")
        XCTAssertEqual(thread.entries.first?.text, text, "the phone never cuts text itself")

        // A live entry past the cap pushes the oldest out.
        thread.upsert([entry(601, text: text)])
        XCTAssertEqual(thread.entries.count, 500)
        XCTAssertEqual(thread.entries.first?.seq, 102)
        XCTAssertEqual(thread.entries.last?.seq, 601)

        // The copy survives a round trip through the store's JSON.
        let decoded = try JSONDecoder().decode(ChatThread.self, from: JSONEncoder().encode(thread))
        XCTAssertEqual(decoded, thread)

        // A cut never splits a transcript line: paging back from its `seq` would skip its rest.
        var grouped = ChatThread()
        grouped.upsert([entry(1, id: "1a"), entry(1, id: "1b")] + entries(2...500))
        XCTAssertEqual(grouped.entries.count, 499)
        XCTAssertEqual(grouped.entries.first?.seq, 2)
        XCTAssertTrue(grouped.hasMore)
    }
}
