import Foundation
import ShellXLinkCore

/// One session's chat as the phone keeps it: the entries it has, ordered by `seq`, and whether the
/// Mac has older ones (PROTOCOL.md sections 4 and 6).
///
/// - Entries merge by `id`: of two emissions, the one with the higher `rev` stays (`ChatEntry.newer`),
///   so an equal or lower `rev` arriving later, from a history page or a live push, is dropped.
/// - Entries sharing a `seq` form one transcript line and keep the order they arrived in.
/// - Only the newest `maxEntries` are kept, cut between transcript lines (paging back with
///   `before_seq` would skip the rest of a split line); a cut sets `hasMore`.
/// - Text is kept as the Mac sent it: the host already cut each entry to 4096 bytes.
public struct ChatThread: Codable, Equatable, Sendable {
    /// The most entries kept on the phone; the oldest go first.
    public static let maxEntries = 500

    /// Oldest first.
    public private(set) var entries: [ChatEntry]
    /// The Mac has entries older than the first one here.
    public private(set) var hasMore: Bool

    public init(entries: [ChatEntry] = [], hasMore: Bool = false) {
        self.entries = []
        self.hasMore = hasMore
        upsert(entries)
    }

    /// A stored copy, normalized the same way (sorted, one entry per `id`, capped).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            entries: try container.decode([ChatEntry].self, forKey: .entries),
            hasMore: try container.decode(Bool.self, forKey: .hasMore))
    }

    /// Adds new entries and keeps the newer emission of known ones. Says nothing about older
    /// entries, so `hasMore` only changes when the cap drops some.
    public mutating func upsert(_ incoming: [ChatEntry]) {
        guard !incoming.isEmpty else { return }
        var index = Dictionary(entries.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var merged = entries
        for entry in incoming {
            if let at = index[entry.id] {
                merged[at] = ChatEntry.newer(merged[at], entry)
            } else {
                index[entry.id] = merged.count
                merged.append(entry)
            }
        }
        // Sorted by `seq`; within one `seq`, by arrival (an edited entry keeps its place).
        entries = merged.enumerated()
            .sorted { ($0.element.seq, $0.offset) < ($1.element.seq, $1.offset) }
            .map(\.element)
        cap()
    }

    /// The Mac's newest page (`chat.history` without `before_seq`). It replaces the copy when it does
    /// not reach it: the Mac has older entries (`hasMore`) and no entry here lies within the page or
    /// right before it, so what came between is unknown. Entries newer than the page (pushed live
    /// while it travelled) stay. Otherwise the page merges into the copy.
    public mutating func applyLatestPage(_ page: [ChatEntry], hasMore pageHasMore: Bool) {
        guard let pageFirst = page.map(\.seq).min(), let pageLast = page.map(\.seq).max() else {
            // An empty page: the Mac has no entries (yet). What is here stays.
            if entries.isEmpty { hasMore = pageHasMore }
            return
        }
        let reaches = entries.contains { (pageFirst - 1)...pageLast ~= $0.seq }
        let olderHere = entries.contains { $0.seq < pageFirst }
        if pageHasMore, olderHere, !reaches {
            entries.removeAll { $0.seq <= pageLast }
            hasMore = true
        } else if !olderHere {
            // The page holds the oldest entry known: it says whether older ones exist.
            hasMore = pageHasMore
        }
        upsert(page)
    }

    /// A page older than the first entry here (`before_seq` = its `seq`).
    public mutating func applyOlderPage(_ page: [ChatEntry], hasMore pageHasMore: Bool) {
        hasMore = pageHasMore
        upsert(page)
    }

    /// Keeps the newest `maxEntries`, dropping whole transcript lines; only a single line longer
    /// than the cap is cut inside.
    private mutating func cap() {
        guard entries.count > Self.maxEntries else { return }
        var start = entries.count - Self.maxEntries
        let splitSeq = entries[start - 1].seq
        while start < entries.count, entries[start].seq == splitSeq { start += 1 }
        if start == entries.count { start = entries.count - Self.maxEntries }
        entries.removeFirst(start)
        hasMore = true
    }
}
