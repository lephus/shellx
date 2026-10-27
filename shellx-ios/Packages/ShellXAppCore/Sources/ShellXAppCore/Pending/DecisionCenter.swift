import Foundation
import Observation
import ShellXLinkCore
import ShellXLinkSession

/// Sends the user's decisions on pending items and keeps, per item, what its card says about it.
///
/// Rules (A1, spec section 7.5):
/// - A tap on an item that is `sending` (or already `done` or handled elsewhere) does nothing.
/// - `delivered`: `done`, and the card goes at once, without waiting for the Mac's `agent.changed`.
///   The time from the tap to that answer is recorded as `replyRoundTrip` (A2).
/// - `already_handled`: `handledElsewhere`; the card says so, then goes after
///   `handledElsewhereLinger`, also when the item left the pending set meanwhile.
/// - `unknown`, an outcome this app does not know, or an error the Mac answered: `failed(.rejected)`.
/// - No answer in time: sent once more (safe: replies are idempotent); still none, `failed(.noAnswer)`.
/// - No live, synced session (`LinkCallError.offline`, `LinkClientError.sessionClosed`, or a card
///   shown not actionable): `failed(.offline)`. Nothing is queued: once the Mac is back, nothing
///   goes out unless the user taps again, and the note goes as soon as the card can act again.
/// - Feedback over `maxFeedbackBytes` is not sent at all (the sheet counts bytes and stops it first).
/// - An item that left the pending set loses its status.
///
/// The screen calls `sync(_:)` with the hub's whole `pendingItems` when it appears and whenever
/// they change (`onChange`); its body only reads `visibleItems(_:)`.
@MainActor @Observable
public final class DecisionCenter {
    /// The most UTF-8 bytes of a plan's feedback.
    public static let maxFeedbackBytes = 4096
    /// How long a card says "handled elsewhere" before it goes.
    public static let handledElsewhereLinger: Duration = .seconds(2)

    /// Each item's decision, by item. No entry: nothing sent (or the item is gone).
    public private(set) var status: [PendingKey: DecisionStatus] = [:]
    /// Items whose "handled elsewhere" was shown long enough.
    private var dismissed: Set<PendingKey> = []
    /// Items handled elsewhere, as last shown, kept on screen through the linger even when they
    /// left the pending set.
    private var lingering: [PendingKey: MachinePendingItem] = [:]

    @ObservationIgnored private let sender: any DecisionSending
    @ObservationIgnored private let latency: LatencyLog
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    /// The hub's items at the last `sync(_:)`: what the cards show (read by `send`).
    @ObservationIgnored private var shown: [PendingKey: MachinePendingItem] = [:]
    /// The last decision sent per item, for `retry(_:)`.
    @ObservationIgnored private var lastDecision: [PendingKey: LinkDecision] = [:]
    /// Items whose reply is still out: their status survives the item leaving the set.
    @ObservationIgnored private var inFlight: Set<PendingKey> = []

    public init(
        sender: any DecisionSending, latency: LatencyLog, sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.sender = sender
        self.latency = latency
        self.sleep = sleep
    }

    /// Sends `decision` for the item and updates its status as the rules say. Returns when the
    /// status is final for this tap.
    public func send(_ decision: LinkDecision, for key: PendingKey) async {
        switch status[key] {
        case .sending, .done, .handledElsewhere: return
        case .failed, nil: break
        }
        if case let .exitPlan(_, feedback?) = decision, feedback.utf8.count > Self.maxFeedbackBytes { return }
        let item = shown[key]
        lastDecision[key] = decision
        // The card showed no live data: the tap raced the redraw that turned its buttons off.
        if item?.actionable == false {
            status[key] = .failed(.offline)
            return
        }
        status[key] = .sending
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        let start = ContinuousClock.now
        var resent = false
        while true {
            do {
                let outcome = try await sender.reply(key, decision: decision)
                switch outcome {
                case .delivered:
                    latency.record(.replyRoundTrip, ContinuousClock.now - start)
                    status[key] = .done
                case .alreadyHandled:
                    status[key] = .handledElsewhere
                    linger(key, item: item)
                case .unknown, .other:
                    status[key] = .failed(.rejected)
                }
                return
            } catch LinkClientError.timedOut where !resent {
                resent = true
            } catch {
                status[key] = .failed(Self.failure(error))
                return
            }
        }
    }

    /// Takes the hub's whole pending list (never a subset: what is missing counts as resolved):
    /// - forgets the status of every item that left it (unless its reply is still out, or its
    ///   "handled elsewhere" is still showing);
    /// - clears `failed(.offline)` of an item that can act again (it was not actionable, or not
    ///   there, at the last sync): the note no longer holds once the buttons are back.
    ///
    /// Writes only what changes. Call it outside a view's body (`onAppear`, `onChange`).
    public func sync(_ pendingItems: [MachinePendingItem]) {
        let before = shown
        shown = Dictionary(pendingItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        forgetGone(present: shown)
        for (key, item) in shown where item.actionable && before[key]?.actionable != true {
            if status[key] == .failed(.offline) { status[key] = nil }
        }
    }

    /// "Try again" on a failed item: sends its last decision once more.
    public func retry(_ key: PendingKey) async {
        guard case .failed = status[key], let decision = lastDecision[key] else { return }
        await send(decision, for: key)
    }

    /// The items to show as cards, out of `items` (the hub's `pendingItems`, or any part of it):
    /// - without the `done` ones (the Mac's `agent.changed` may still be on its way);
    /// - with the ones handled elsewhere until their linger is over, kept even when they left the
    ///   set meanwhile (then not actionable).
    ///
    /// Only reads, so a view's body may call it.
    public func visibleItems(_ items: [MachinePendingItem]) -> [MachinePendingItem] {
        let present = Set(items.map(\.id))
        var visible = items.filter { status[$0.id] != .done && !dismissed.contains($0.id) }
        let kept = lingering.filter { !present.contains($0.key) && !dismissed.contains($0.key) }.map(\.value)
        if !kept.isEmpty {
            // The hub's order: oldest first.
            visible = (visible + kept).sorted {
                ($0.item.createdAtMs, $0.machineID, $0.item.requestId)
                    < ($1.item.createdAtMs, $1.machineID, $1.item.requestId)
            }
        }
        return visible
    }

    // MARK: - Private

    private func linger(_ key: PendingKey, item: MachinePendingItem?) {
        if var item {
            item.actionable = false
            lingering[key] = item
        }
        let sleep = self.sleep
        Task { [weak self] in
            // A cancelled wait still ends the linger: the card must not stay forever.
            try? await sleep(Self.handledElsewhereLinger)
            self?.endLinger(key)
        }
    }

    private func endLinger(_ key: PendingKey) {
        lingering[key] = nil
        if shown[key] != nil {
            dismissed.insert(key)
        } else {
            // Gone from the set already: nothing left to hide.
            forget(key)
        }
    }

    /// Drops what is kept about items that are neither pending, nor on their way, nor lingering.
    /// Writes only when something changes.
    private func forgetGone(present: [PendingKey: MachinePendingItem]) {
        let known = Set(status.keys).union(dismissed).union(lastDecision.keys)
        let gone = known.filter { present[$0] == nil && !inFlight.contains($0) && lingering[$0] == nil }
        for key in gone { forget(key) }
    }

    private func forget(_ key: PendingKey) {
        if status[key] != nil { status[key] = nil }
        if dismissed.contains(key) { dismissed.remove(key) }
        lastDecision[key] = nil
    }

    private static func failure(_ error: any Error) -> DecisionFailure {
        switch error {
        // Nothing was sent. A Mac to be paired again has dropped its items, so its cards are gone
        // before this line could show.
        case LinkCallError.offline, LinkCallError.needsPairing, LinkClientError.sessionClosed:
            return .offline
        case LinkClientError.remote, LinkCallError.unknownMachine:
            return .rejected
        default:
            // Timed out twice, or failed in a way that says nothing about the item: trying again is
            // safe, since a reply is idempotent.
            return .noAnswer
        }
    }
}
