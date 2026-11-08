import Foundation

/// What `TerminalFrameAssembler.receive` decided about one message.
public struct TerminalAssemblyResult: Equatable, Sendable {
    /// A complete frame to apply now (PROTOCOL.md 11.7), or nil.
    public var frame: TerminalGridFrame?
    /// Send `terminal.view.resync` now (at most once per gap).
    public var resync: Bool

    public init(frame: TerminalGridFrame? = nil, resync: Bool = false) {
        self.frame = frame
        self.resync = resync
    }
}

/// Puts the parts of `terminal.view.frame` messages together and applies the revision rules of PROTOCOL.md 11.7.
/// One per view; start a fresh one when an `ok` arrives.
public struct TerminalFrameAssembler: Equatable, Sendable {
    /// The revision of the last frame applied: 0 before the first snapshot.
    public private(set) var revision = 0
    /// True from a gap until the next snapshot: deltas and history frames are ignored meanwhile.
    public private(set) var awaitingSnapshot = false

    private struct Partial: Equatable, Sendable {
        var revision: Int
        var parts: Int
        var nextPart: Int
        var head: TerminalFrameHead?
        var styles: [TerminalStyle]
        var lines: [TerminalLine]
    }

    private var partial: Partial?
    private var cols = 0
    private var rows = 0
    private var alt = false

    public init() {}

    public mutating func receive(_ part: TerminalFramePart) -> TerminalAssemblyResult {
        var result = TerminalAssemblyResult()
        if part.part == 0 {
            if partial != nil { markGap(&result) }
            partial = Partial(
                revision: part.revision, parts: part.parts, nextPart: 1, head: part.head, styles: part.styles, lines: part.lines)
        } else {
            guard var current = partial, current.revision == part.revision, current.parts == part.parts,
                  part.part == current.nextPart
            else {
                partial = nil
                markGap(&result)
                return result
            }
            current.nextPart += 1
            current.styles += part.styles
            current.lines += part.lines
            partial = current
        }
        guard let current = partial, current.nextPart == current.parts else { return result }
        partial = nil
        guard let head = current.head else {
            markGap(&result)
            return result
        }
        let frame = TerminalGridFrame(head: head, styles: current.styles, lines: current.lines)
        complete(frame, revision: current.revision, into: &result)
        return result
    }

    private mutating func complete(_ frame: TerminalGridFrame, revision number: Int, into result: inout TerminalAssemblyResult) {
        let head = frame.head
        switch head.kind {
        case .snapshot:
            if number <= revision { return }
            guard head.cursor != nil, head.palette != nil, Self.sizeIsValid(head) else {
                markGap(&result)
                return
            }
            revision = number
            awaitingSnapshot = false
            cols = head.cols
            rows = head.rows
            alt = head.alt
            result.frame = frame
        case .delta, .history:
            if awaitingSnapshot || number <= revision { return }
            guard revision > 0, number == revision + 1, Self.sizeIsValid(head),
                  head.cols == cols, head.rows == rows, head.alt == alt,
                  head.kind != .delta || head.cursor != nil
            else {
                markGap(&result)
                return
            }
            revision = number
            result.frame = frame
        case .other:
            if awaitingSnapshot || number <= revision { return }
            markGap(&result)
        }
    }

    private mutating func markGap(_ result: inout TerminalAssemblyResult) {
        guard !awaitingSnapshot else { return }
        awaitingSnapshot = true
        result.resync = true
    }

    private static func sizeIsValid(_ head: TerminalFrameHead) -> Bool {
        (1...ShellXLink.terminalMaxGridSize).contains(head.cols) && (1...ShellXLink.terminalMaxGridSize).contains(head.rows)
    }
}
