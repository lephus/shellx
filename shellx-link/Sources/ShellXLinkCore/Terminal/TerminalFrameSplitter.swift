import Foundation

/// Cuts one frame into the messages that carry it (PROTOCOL.md 11.4).
public enum TerminalFrameSplitter {
    /// The parts of `frame` at `revision`, in order. Part 0 carries `frame.head`; the styles come first, then the lines,
    /// in order. Each part, encoded as `.terminalViewFrame(terminalId:frame:)`, fits `LinkCodec.maxFrameBytes`. A line too
    /// large for one part becomes several lines with the same `y`, each later one starting with a run whose `x` is
    /// explicit. Throws `LinkCodecError.frameTooLarge` past `ShellXLink.terminalMaxFrameParts` parts, or when one run
    /// alone does not fit an empty part.
    public static func parts(of frame: TerminalGridFrame, revision: Int, terminalId: String) throws -> [TerminalFramePart] {
        try parts(
            of: frame, revision: revision, terminalId: terminalId, maxBytes: LinkCodec.maxFrameBytes,
            maxParts: ShellXLink.terminalMaxFrameParts)
    }

    /// Bytes kept free in every part for the `"styles":[` and `"lines":[` keys, their brackets and commas.
    private static let slack = 64

    static func parts(
        of frame: TerminalGridFrame, revision: Int, terminalId: String, maxBytes: Int, maxParts: Int
    ) throws -> [TerminalFramePart] {
        // An empty part with the widest numbers it can have: every real part is at most this much larger per item.
        func emptySize(first: Bool) throws -> Int {
            let part = TerminalFramePart(
                revision: revision, part: first ? 0 : ShellXLink.terminalMaxFrameParts - 1,
                parts: ShellXLink.terminalMaxFrameParts, head: first ? frame.head : nil)
            return try LinkCodec.encode(.terminalViewFrame(terminalId: terminalId, frame: part)).count
        }
        let firstRoom = maxBytes - (try emptySize(first: true)) - slack
        let laterRoom = maxBytes - (try emptySize(first: false)) - slack

        struct Draft {
            var styles: [TerminalStyle] = []
            var lines: [TerminalLine] = []
            var used = 0
            var isEmpty: Bool { styles.isEmpty && lines.isEmpty }
        }
        var drafts = [Draft()]
        func room() -> Int { drafts.count == 1 ? firstRoom : laterRoom }
        func startNewPart() throws {
            guard drafts.count < maxParts else { throw LinkCodecError.frameTooLarge }
            drafts.append(Draft())
        }

        for style in frame.styles {
            let size = try LinkCodec.encodedByteCount(style) + 1
            if drafts[drafts.count - 1].used + size > room() {
                if drafts[drafts.count - 1].isEmpty { throw LinkCodecError.frameTooLarge }
                try startNewPart()
                if size > room() { throw LinkCodecError.frameTooLarge }
            }
            drafts[drafts.count - 1].styles.append(style)
            drafts[drafts.count - 1].used += size
        }

        for line in frame.lines {
            let size = try LinkCodec.encodedByteCount(line) + 1
            if drafts[drafts.count - 1].used + size <= room() {
                drafts[drafts.count - 1].lines.append(line)
                drafts[drafts.count - 1].used += size
                continue
            }
            if !drafts[drafts.count - 1].isEmpty { try startNewPart() }
            if size <= room() {
                drafts[drafts.count - 1].lines.append(line)
                drafts[drafts.count - 1].used += size
                continue
            }
            // Too large for an empty part: cut the line between runs.
            var columns: [Int] = []
            var next = 0
            for run in line.runs {
                let x = run.x ?? next
                columns.append(x)
                next = x + (run.width ?? run.text.unicodeScalars.count)
            }
            let lineBase = try LinkCodec.encodedByteCount(TerminalLine(y: line.y)) + 16
            var start = 0
            while start < line.runs.count {
                if !drafts[drafts.count - 1].isEmpty { try startNewPart() }
                var piece: [TerminalRun] = []
                var pieceSize = lineBase
                var index = start
                while index < line.runs.count {
                    var run = line.runs[index]
                    // A piece after the first starts with an explicit column, because the run before it is elsewhere.
                    if index == start && start > 0 { run.x = columns[index] }
                    let runSize = try LinkCodec.encodedByteCount(run) + 1
                    if pieceSize + runSize > room() { break }
                    piece.append(run)
                    pieceSize += runSize
                    index += 1
                }
                if piece.isEmpty { throw LinkCodecError.frameTooLarge }
                drafts[drafts.count - 1].lines.append(TerminalLine(y: line.y, runs: piece))
                drafts[drafts.count - 1].used += pieceSize
                start = index
            }
        }

        let total = drafts.count
        var result: [TerminalFramePart] = []
        for (index, draft) in drafts.enumerated() {
            let part = TerminalFramePart(
                revision: revision, part: index, parts: total, head: index == 0 ? frame.head : nil,
                styles: draft.styles, lines: draft.lines)
            if try LinkCodec.encode(.terminalViewFrame(terminalId: terminalId, frame: part)).count > maxBytes {
                throw LinkCodecError.frameTooLarge
            }
            result.append(part)
        }
        return result
    }
}
