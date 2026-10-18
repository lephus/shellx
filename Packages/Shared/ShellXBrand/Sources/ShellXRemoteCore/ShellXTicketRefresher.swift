import Foundation

public protocol RemoteClock: Sendable {
    var now: Date { get }
    /// Suspends until `until`; throws `CancellationError` when the task is cancelled.
    func sleep(until: Date) async throws
}

public struct SystemRemoteClock: RemoteClock {
    public init() {}
    public var now: Date { Date() }
    public func sleep(until deadline: Date) async throws {
        let seconds = deadline.timeIntervalSinceNow
        if seconds > 0 { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        try Task.checkCancellation()
    }
}

/// Keeps relay ticket files fresh through shellx-core `tickets.mint {permission, target_machine_id?, write_to}`.
/// The core writes the ticket owner-only to `<coreStateDir>/tickets/<name>` and returns only its path;
/// this type never sees a ticket value. A refresh is due at half the remaining life
/// (`TicketSchedule.nextRefresh`); a failed refresh is retried on `ReconnectBackoff` until it works,
/// a fatal code (`LinkFailure.isFatal`) ends the loop, or `stop(name:)`.
public actor ShellXTicketRefresher {
    private struct Entry {
        let permission: String
        let target: RemoteMachine.ID?
        var generation: Int
        var task: Task<Void, Never>?
    }

    private struct MintReply: Decodable, Sendable {
        let path: String
        let expires_at_unix: Double
        let relay_url: String
    }

    private let core: ShellXCoreClient
    private let clock: any RemoteClock
    private var entries: [String: Entry] = [:]
    private var relayURLs: [String: String] = [:]
    private var generations = 0

    public init(core: ShellXCoreClient, clock: any RemoteClock) {
        self.core = core
        self.clock = clock
    }

    /// Registers `name`, mints it now and keeps it fresh. Returns the ticket file of the first mint;
    /// throws the core error when that mint fails (the name stays registered, so `mintNow` can retry).
    @discardableResult
    public func keepFresh(name: String, permission: String, target: RemoteMachine.ID?) async throws -> URL {
        entries[name]?.task?.cancel()
        entries[name] = Entry(permission: permission, target: target, generation: nextGeneration(), task: nil)
        return try await mintNow(name: name)
    }

    /// Mints `name` immediately (used before every spawn) and restarts its refresh schedule.
    @discardableResult
    public func mintNow(name: String) async throws -> URL {
        guard var entry = entries[name] else {
            throw ShellXCoreError(code: "ticket_not_registered", message: "keepFresh was not called for this ticket")
        }
        entry.task?.cancel()
        entry.task = nil
        entry.generation = nextGeneration()
        entries[name] = entry
        let generation = entry.generation
        let reply = try await mint(name: name, entry: entry)
        relayURLs[name] = reply.relay_url
        if entries[name]?.generation == generation {
            schedule(name: name, generation: generation, expiresAt: Date(timeIntervalSince1970: reply.expires_at_unix))
        }
        return URL(fileURLWithPath: reply.path)
    }

    public func stop(name: String) {
        entries[name]?.task?.cancel()
        entries[name] = nil
        relayURLs[name] = nil
    }

    /// The `relay_url` of the latest successful mint of `name` (not a secret; the only source of the relay URL).
    public func relayURL(name: String) -> String? { relayURLs[name] }

    public func isRegistered(name: String) -> Bool { entries[name] != nil }

    // MARK: - Private

    private func nextGeneration() -> Int {
        generations += 1
        return generations
    }

    private func schedule(name: String, generation: Int, expiresAt: Date) {
        let now = clock.now
        let wakeAt = now.addingTimeInterval(TicketSchedule.nextRefresh(expiresAt: expiresAt, now: now))
        entries[name]?.task = Task { [weak self] in
            await self?.refreshLoop(name: name, generation: generation, firstWake: wakeAt)
        }
    }

    private func isCurrent(_ name: String, _ generation: Int) -> Bool {
        entries[name]?.generation == generation && !Task.isCancelled
    }

    private func refreshLoop(name: String, generation: Int, firstWake: Date) async {
        var wakeAt = firstWake
        var failures = 0
        while true {
            do { try await clock.sleep(until: wakeAt) } catch { return }
            guard isCurrent(name, generation), let entry = entries[name] else { return }
            do {
                let reply = try await mint(name: name, entry: entry)
                guard isCurrent(name, generation) else { return }
                relayURLs[name] = reply.relay_url
                failures = 0
                let expires = Date(timeIntervalSince1970: reply.expires_at_unix)
                let now = clock.now
                wakeAt = now.addingTimeInterval(TicketSchedule.nextRefresh(expiresAt: expires, now: now))
            } catch {
                guard isCurrent(name, generation), !LinkFailure.isFatal(LinkFailure.code(for: error)) else { return }
                wakeAt = clock.now.addingTimeInterval(ReconnectBackoff.delay(attempt: failures))
                failures += 1
            }
        }
    }

    /// The core call blocks on HTTP and disk, so it runs on a global queue, never on the cooperative
    /// pool or the main thread.
    private func mint(name: String, entry: Entry) async throws -> MintReply {
        var params: [String: JSONValue] = ["permission": .string(entry.permission), "write_to": .string(name)]
        if let target = entry.target { params["target_machine_id"] = .string(target) }
        let core = self.core
        let sendable = params
        let reply: MintReply = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                do { cont.resume(returning: try core.call("tickets.mint", sendable, as: MintReply.self)) }
                catch { cont.resume(throwing: error) }
            }
        }
        // The ticket file must be the one we asked for; never hand an unexpected path to argv.
        guard URL(fileURLWithPath: reply.path).lastPathComponent == name else {
            throw ShellXCoreError(code: "bad_response", message: "tickets.mint wrote an unexpected file")
        }
        return reply
    }
}
