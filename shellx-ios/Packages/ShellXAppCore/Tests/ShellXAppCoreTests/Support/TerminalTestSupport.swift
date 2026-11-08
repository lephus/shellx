import Foundation
import ShellXLinkCore
import ShellXLinkSession

/// Reads `pushes` as they come: every push, and the screen of the newest view of `terminalId` (a fresh 2A
/// `TerminalFrameAssembler` and `TerminalScreen` at each `.opened(terminalId)`; frames of other terminals ignored).
final class TerminalPushReader: @unchecked Sendable {
    private let lock = NSLock()
    private let terminalId: String
    private var received: [TerminalViewPush] = []
    private var assembler = TerminalFrameAssembler()
    private var current = TerminalScreen()
    private var task: Task<Void, Never>?

    init(_ pushes: AsyncStream<TerminalViewPush>, terminalId: String) {
        self.terminalId = terminalId
        task = Task { [weak self] in
            for await push in pushes {
                guard let self else { return }
                self.take(push)
            }
        }
    }

    deinit {
        task?.cancel()
    }

    var pushes: [TerminalViewPush] { lock.withLock { received } }
    var screen: TerminalScreen { lock.withLock { current } }

    private func take(_ push: TerminalViewPush) {
        lock.withLock {
            received.append(push)
            switch push {
            case let .opened(id) where id == terminalId:
                assembler = TerminalFrameAssembler()
                current = TerminalScreen()
            case let .frame(id, part) where id == terminalId:
                if let frame = assembler.receive(part).frame { current.apply(frame) }
            default:
                break
            }
        }
    }
}

/// Keeps every element of `stream` as it arrives.
final class Collector<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [Element] = []
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<Element>) {
        task = Task { [weak self] in
            for await element in stream {
                guard let self else { return }
                self.lock.withLock { self.kept.append(element) }
            }
        }
    }

    deinit {
        task?.cancel()
    }

    var items: [Element] { lock.withLock { kept } }
}
