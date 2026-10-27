import Foundation
import ShellXLinkAccount
import ShellXLinkCore
import ShellXLinkRelay
import ShellXLinkSession

/// `watch`: logs the pending set, the session list and chat entries until the session ends.
enum Watch {
    static func run(_ args: Arguments) async throws {
        let seconds = try args.optionalInt("seconds")
        let opened = try await Session.open(args)
        let client = opened.client
        let started = ContinuousClock.now
        var spare: SpareTicket?
        if args.flag("recheck") {
            let ticket = SpareTicket()
            await ticket.start(opened)
            spare = ticket
        }
        let closedByTimer = Flag()
        let timer = seconds.map { seconds in
            Task {
                try await Task.sleep(for: .seconds(seconds))
                closedByTimer.set()
                Log.line("watch: \(seconds) s elapsed, closing")
                await client.close()
            }
        }
        async let pending: Void = followPending(client)
        async let sessions: Void = followSessions(client)
        async let chat: Void = followChat(client)
        _ = await (pending, sessions, chat)
        timer?.cancel()
        let lasted = Stats.format(Stats.ms(ContinuousClock.now - started) / 1000)
        Log.line(
            "watch: session ended at \(Log.wallClock()) after \(lasted) s"
                + (closedByTimer.isSet ? "" : " (ended by the Mac or the relay)"))
        if let spare { await Recheck.run(opened, spare: spare) }
        if !closedByTimer.isSet { throw ExitStatus(code: 4) }
    }

    private static func followPending(_ client: LinkClient) async {
        do {
            var current = try await client.snapshot()
            Log.line("snapshot revision=\(current.revision) pending=\(current.pending.count)")
            for item in current.pending { Log.item(item) }
            for await change in client.changes {
                if change.revision <= current.revision { continue }   // already in the snapshot
                if change.revision != current.revision + 1 {
                    Log.line("pending revision gap: had \(current.revision), got \(change.revision); resyncing")
                    current = try await client.snapshot()
                    Log.line("snapshot revision=\(current.revision) pending=\(current.pending.count)")
                    for item in current.pending { Log.item(item) }
                    continue
                }
                current.revision = change.revision
                Log.line(
                    "changed revision=\(change.revision) added=\(change.added.count)"
                        + " resolved=\(change.resolved.map { Log.shown($0) })")
                for item in change.added { Log.item(item) }
            }
        } catch {
            // The other streams keep the watch going until the session ends.
            Log.line("pending: \(ErrorText.describe(error)); no longer following the pending set")
            for await _ in client.changes {}
        }
    }

    private static func followSessions(_ client: LinkClient) async {
        do {
            var revision = try await logSessions(client)
            for await change in client.sessionChanges {
                if change.revision <= revision { continue }
                if change.revision != revision + 1 {
                    Log.line("sessions revision gap: had \(revision), got \(change.revision); resyncing")
                    revision = try await logSessions(client)
                    continue
                }
                revision = change.revision
                Log.line(
                    "sessions changed revision=\(change.revision) upserted=\(change.upserted.count)"
                        + " removed=\(change.removed.map { Log.shown($0) })")
                for session in change.upserted { Log.session(session) }
            }
        } catch {
            Log.line("sessions: \(ErrorText.describe(error))")
            for await _ in client.sessionChanges {}
        }
    }

    private static func logSessions(_ client: LinkClient) async throws -> Int {
        let list = try await client.sessions()
        Log.line("sessions revision=\(list.revision) count=\(list.sessions.count)")
        for session in list.sessions { Log.session(session) }
        return list.revision
    }

    private static func followChat(_ client: LinkClient) async {
        for await push in client.chatEntries {
            Log.line("chat \(Log.shown(push.sessionId)): \(push.entries.count) entr\(push.entries.count == 1 ? "y" : "ies")")
            for entry in push.entries { Log.entry(entry) }
        }
    }
}

/// A connect ticket minted while the session is up, kept fresh (every 60 s) so `--recheck` can try
/// it after the session ends. A failed mint keeps the previous ticket: after a revoke the relay
/// refuses new tickets, and the point is to try one minted before.
actor SpareTicket {
    private(set) var minted: (ticket: RelayTicket, relayURL: URL)?
    private var refresher: Task<Void, Never>?

    func start(_ opened: Session.Opened) {
        let machine = opened.machine
        let api = opened.api
        let token = opened.token
        refresher = Task {
            while !Task.isCancelled {
                do {
                    minted = try await api.mintConnectTicket(
                        machineID: machine.machineID, expectedSlot: machine.linkSlot, token: token)
                } catch {
                    Log.line("recheck: could not mint a spare ticket: \(ErrorText.describe(error))")
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() { refresher?.cancel() }
}

/// Set once, read from any task.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

/// After `watch` ended: can this phone still get in? First with a ticket minted before the end (only
/// the Mac's trust check can refuse it), then with a new ticket (the relay's grant check).
enum Recheck {
    static func run(_ opened: Session.Opened, spare: SpareTicket) async {
        await spare.stop()
        let machine = opened.machine
        if let minted = await spare.minted, minted.ticket.expiresAtUnix > Int64(Date().timeIntervalSince1970) + 2 {
            let started = ContinuousClock.now
            do {
                let circuit = try await RelayClientConnector.connect(
                    relayURL: minted.relayURL, slot: machine.linkSlot, ticket: minted.ticket)
                let client = try await LinkClient.connect(
                    circuit, key: opened.key, hostKey: machine.hostKey, clientVersion: Probe.clientVersion,
                    deviceName: Probe.deviceName)
                Log.line("recheck 1 (ticket minted before the end): CONNECTED, the Mac still accepts this phone")
                await client.close()
            } catch {
                Log.line(
                    "recheck 1 (ticket minted before the end): refused after"
                        + " \(Stats.format(Stats.ms(ContinuousClock.now - started))) ms: \(ErrorText.describe(error))")
            }
        } else {
            Log.line("recheck 1: no unexpired spare ticket; skipped")
        }
        let started = ContinuousClock.now
        do {
            let client = try await LinkConnector.connect(
                machine: machine, key: opened.key, api: opened.api, token: opened.token,
                clientVersion: Probe.clientVersion, deviceName: Probe.deviceName)
            Log.line("recheck 2 (new ticket): CONNECTED, the relay still grants this phone")
            await client.close()
        } catch {
            Log.line(
                "recheck 2 (new ticket): refused after \(Stats.format(Stats.ms(ContinuousClock.now - started))) ms:"
                    + " \(ErrorText.describe(error))")
        }
    }
}
