import Foundation
import ShellXLinkRelay
import XCTest

/// End-to-end tests against a real `cmux-relay serve` process.
///
/// Run with `CMUX_RELAY_BIN=<path to cmux-relay> swift test --package-path shellx-link
/// --filter RelayIntegrationTests`. Without the variable every test is skipped.
final class RelayIntegrationTests: XCTestCase {
    static let secret = "0123456789abcdef0123456789abcdef"
    static let otherSecret = "fedcba9876543210fedcba9876543210"

    private var relay: RelayProcess?
    private var hostTasks: [Task<Void, Error>] = []

    override func setUp() async throws {
        guard let bin = ProcessInfo.processInfo.environment["CMUX_RELAY_BIN"], !bin.isEmpty else {
            throw XCTSkip("CMUX_RELAY_BIN is not set")
        }
        // A short lease makes the heartbeat test observable; the host pings every lease / 3.
        relay = try await RelayProcess.start(
            binary: bin, secret: Self.secret, extraEnvironment: ["CMUX_RELAY_LEASE_SECONDS": "3"])
    }

    override func tearDown() async throws {
        for task in hostTasks { task.cancel() }
        // A host task that ignores cancellation must not hang the suite: give up after 10 s.
        let tasks = hostTasks
        let finished = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for task in tasks { _ = await task.result }
                return true
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        hostTasks.removeAll()
        XCTAssertTrue(finished, "a host task did not stop within 10 s of cancellation")
        relay?.stop()
        relay = nil
    }

    // MARK: - Tests

    func testClientAndHostExchangeBytes() async throws {
        let relay = try XCTUnwrap(relay)
        let minter = TestTicketMinter(secret: Self.secret)
        let hostReceived = Inbox<Data>()
        startHost(relay: relay, slot: "s1", minter: minter) { circuit in
            do {
                try await circuit.send(Data([0x01, 0x02]))
                await hostReceived.put(try await circuit.receive())
                while true { _ = try await circuit.receive() }
            } catch {}
        }

        let client = try await connectWhenOnline(relay: relay, slot: "s1", minter: minter)
        try await client.send(Data([0x01, 0x02]))
        let fromHost = try await client.receive()
        XCTAssertEqual(fromHost, Data([0x01, 0x02]))
        let atHost = await hostReceived.take()
        XCTAssertEqual(atHost, Data([0x01, 0x02]))
        await client.close()
    }

    func testTwoCircuitsOnOneRegistration() async throws {
        let relay = try XCTUnwrap(relay)
        let minter = TestTicketMinter(secret: Self.secret)
        let accepted = Counter()
        startHost(relay: relay, slot: "s1", minter: minter) { circuit in
            await accepted.increment()
            // Echo every frame back on the same circuit.
            do {
                while true { try await circuit.send(try await circuit.receive()) }
            } catch {}
        }

        let first = try await connectWhenOnline(relay: relay, slot: "s1", minter: minter)
        let second = try await connectWhenOnline(relay: relay, slot: "s1", minter: minter)

        // Send on the second circuit first so a crossed route would show up as a wrong echo.
        try await second.send(Data([0xB2, 0xB2]))
        try await first.send(Data([0xA1]))
        let secondEcho = try await second.receive()
        let firstEcho = try await first.receive()
        XCTAssertEqual(firstEcho, Data([0xA1]))
        XCTAssertEqual(secondEcho, Data([0xB2, 0xB2]))
        let acceptedCount = await accepted.value
        XCTAssertEqual(acceptedCount, 2)

        await first.close()
        await second.close()
    }

    func testBadTicketSurfacesServerError() async throws {
        let relay = try XCTUnwrap(relay)
        let minter = TestTicketMinter(secret: Self.secret)
        startHost(relay: relay, slot: "s1", minter: minter) { _ in }
        // Make sure the slot is online, so the failure below is about the ticket only.
        let probe = try await connectWhenOnline(relay: relay, slot: "s1", minter: minter)
        await probe.close()

        let forged = TestTicketMinter(secret: Self.otherSecret).mint(.connect, slot: "s1")
        do {
            let circuit = try await RelayClientConnector.connect(
                relayURL: relay.url, slot: "s1", ticket: forged)
            await circuit.close()
            XCTFail("a ticket signed with the wrong secret connected")
        } catch let RelayError.server(code, retryable) {
            XCTAssertEqual(code, "invalid-ticket")
            XCTAssertFalse(retryable)
        }
    }

    func testReRegisterAsksForFreshTicket() async throws {
        let relay = try XCTUnwrap(relay)
        let minter = TestTicketMinter(secret: Self.secret)
        let issued = Counter()
        let host = RelayHostRegistration(relayURL: relay.url, slot: "s1") {
            await issued.increment()
            return minter.mint(.register, slot: "s1")
        }
        hostTasks.append(Task {
            try await host.run { circuit in
                do {
                    while true { try await circuit.send(try await circuit.receive()) }
                } catch {}
            }
        })

        let before = try await connectWhenOnline(relay: relay, slot: "s1", minter: minter)
        await before.close()
        let firstCount = await issued.value
        XCTAssertEqual(firstCount, 1)

        await host._dropControlForTesting()
        try await waitUntil("the host asks for a fresh register ticket") {
            await issued.value >= 2
        }

        let after = try await connectWhenOnline(relay: relay, slot: "s1", minter: minter)
        try await after.send(Data([0x07]))
        let echo = try await after.receive()
        XCTAssertEqual(echo, Data([0x07]))
        await after.close()
    }

    func testHeartbeatKeepsRegistrationPastLease() async throws {
        let relay = try XCTUnwrap(relay)
        let minter = TestTicketMinter(secret: Self.secret)
        let issued = Counter()
        let host = RelayHostRegistration(relayURL: relay.url, slot: "s1") {
            await issued.increment()
            return minter.mint(.register, slot: "s1")
        }
        hostTasks.append(Task { try await host.run { _ in } })
        let probe = try await connectWhenOnline(relay: relay, slot: "s1", minter: minter)
        await probe.close()

        // Outlive the 3 s lease twice over; pings must keep the first registration alive.
        try await Task.sleep(for: .seconds(7))
        let circuit = try await RelayClientConnector.connect(
            relayURL: relay.url, slot: "s1", ticket: minter.mint(.connect, slot: "s1"))
        await circuit.close()
        let count = await issued.value
        XCTAssertEqual(count, 1, "the host had to re-register, so the heartbeat did not hold the lease")
    }

    func testRenewalOverlapsOldRegistration() async throws {
        let relay = try XCTUnwrap(relay)
        let minter = TestTicketMinter(secret: Self.secret)
        let events = EventLog()
        let host = RelayHostRegistration(
            relayURL: relay.url, slot: "s1", renewLead: .seconds(3), onEvent: { events.append($0) }
        ) {
            minter.mint(.register, slot: "s1", lifetime: 6)
        }
        hostTasks.append(Task {
            try await host.run { circuit in
                do {
                    while true { try await circuit.send(try await circuit.receive()) }
                } catch {}
            }
        })
        let probe = try await connectWhenOnline(relay: relay, slot: "s1", minter: minter)
        await probe.close()

        // One attempt per connect, no retry: a gap in the registration would show as a failure.
        // Run past the first ticket's 6 s expiry.
        let started = Date()
        var attempts = 0
        var failures: [String] = []
        while Date().timeIntervalSince(started) < 8.5 {
            attempts += 1
            do {
                let circuit = try await RelayClientConnector.connect(
                    relayURL: relay.url, slot: "s1", ticket: minter.mint(.connect, slot: "s1"),
                    slotOfflineRetries: [])
                try await circuit.send(Data([0x01]))
                let echo = try await circuit.receive()
                if echo != Data([0x01]) { failures.append("wrong echo") }
                await circuit.close()
            } catch {
                failures.append("\(error)")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertGreaterThan(attempts, 15)
        XCTAssertEqual(failures, [], "clients must connect throughout the renewal")
        let seen = events.all
        XCTAssertEqual(seen.first, .registered)
        XCTAssertTrue(seen.contains(.renewed), "events: \(seen)")
        XCTAssertFalse(seen.contains { if case .failed = $0 { return true } else { return false } }, "events: \(seen)")
    }

    func testConnectRetriesSlotOffline() async throws {
        let relay = try XCTUnwrap(relay)
        let minter = TestTicketMinter(secret: Self.secret)
        let url = relay.url
        let ticket = minter.mint(.connect, slot: "s1")
        let client = Task {
            try await RelayClientConnector.connect(relayURL: url, slot: "s1", ticket: ticket)
        }
        try await Task.sleep(for: .milliseconds(300))
        startHost(relay: relay, slot: "s1", minter: minter) { circuit in
            do {
                while true { try await circuit.send(try await circuit.receive()) }
            } catch {}
        }
        let circuit = try await client.value
        try await circuit.send(Data([0x09]))
        let echo = try await circuit.receive()
        XCTAssertEqual(echo, Data([0x09]))
        await circuit.close()

        // With no retries the same situation is reported, not hidden.
        let lonely = minter.mint(.connect, slot: "nobody")
        do {
            _ = try await RelayClientConnector.connect(
                relayURL: url, slot: "nobody", ticket: lonely, slotOfflineRetries: [])
            XCTFail("connected to an unregistered slot")
        } catch let RelayError.server(code, retryable) {
            XCTAssertEqual(code, "slot-offline")
            XCTAssertTrue(retryable)
        }
    }

    func testRegistrationGivesUpAfterConsecutiveFailures() async throws {
        let relay = try XCTUnwrap(relay)
        let minter = TestTicketMinter(secret: Self.secret)
        let events = EventLog()
        let issued = Counter()
        let host = RelayHostRegistration(
            relayURL: relay.url, slot: "s1", maxConsecutiveFailures: 5, onEvent: { events.append($0) }
        ) {
            await issued.increment()
            if await issued.value == 1 { return minter.mint(.register, slot: "s1") }
            // Shaped like a ticket, signed by nobody.
            return RelayTicket(ticket: "v2.e30.AAAA", expiresAtUnix: Int64(Date().timeIntervalSince1970) + 60)
        }
        let run = Task { try await host.run { _ in } }
        hostTasks.append(Task { _ = await run.result })
        let probe = try await connectWhenOnline(relay: relay, slot: "s1", minter: minter)
        await probe.close()
        await host._dropControlForTesting()

        switch await run.result {
        case .success: XCTFail("run returned instead of giving up")
        case .failure(let error): XCTAssertTrue(error is RelayError, "unexpected error \(error)")
        }
        let seen = events.all
        XCTAssertEqual(seen.first, .registered)
        let failed = seen.filter { if case .failed = $0 { return true } else { return false } }
        XCTAssertEqual(failed.count, 4, "events: \(seen)")
        guard case .gaveUp(let code)? = seen.last else { return XCTFail("events: \(seen)") }
        XCTAssertFalse(code.isEmpty)
        let tickets = await issued.value
        XCTAssertEqual(tickets, 5, "one good ticket, then four refused ones after the dropped socket")
    }

    // MARK: - Helpers

    private func startHost(
        relay: RelayProcess,
        slot: String,
        minter: TestTicketMinter,
        onCircuit: @escaping @Sendable (any RelayCircuit) async -> Void
    ) {
        let host = RelayHostRegistration(relayURL: relay.url, slot: slot) {
            minter.mint(.register, slot: slot)
        }
        hostTasks.append(Task { try await host.run(onCircuit: onCircuit) })
    }

    /// Connects as a client, retrying while the host has not registered the slot yet.
    private func connectWhenOnline(
        relay: RelayProcess,
        slot: String,
        minter: TestTicketMinter
    ) async throws -> any RelayCircuit {
        let deadline = Date().addingTimeInterval(10)
        while true {
            do {
                return try await RelayClientConnector.connect(
                    relayURL: relay.url, slot: slot, ticket: minter.mint(.connect, slot: slot))
            } catch RelayError.server(code: "slot-offline", retryable: true) where Date() < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func waitUntil(
        _ what: String,
        timeout: TimeInterval = 10,
        _ condition: @Sendable () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() {
            if Date() > deadline {
                XCTFail("timed out waiting until \(what)")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

// MARK: - Test doubles

/// Records host events in the order they are emitted (the callback is synchronous).
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [RelayHostEvent] = []

    var all: [RelayHostEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    func append(_ event: RelayHostEvent) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }
}

actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

/// A one-slot-at-a-time mailbox that lets a test await values produced inside host callbacks.
actor Inbox<Value: Sendable> {
    private var items: [Value] = []
    private var waiters: [CheckedContinuation<Value, Never>] = []

    func put(_ value: Value) {
        if waiters.isEmpty {
            items.append(value)
        } else {
            waiters.removeFirst().resume(returning: value)
        }
    }

    func take() async -> Value {
        if !items.isEmpty { return items.removeFirst() }
        return await withCheckedContinuation { waiters.append($0) }
    }
}

/// A `cmux-relay serve` child process bound to a free loopback port.
final class RelayProcess: @unchecked Sendable {
    let url: URL
    private let process: Process

    private init(url: URL, process: Process) {
        self.url = url
        self.process = process
    }

    static func start(
        binary: String,
        secret: String,
        extraEnvironment: [String: String] = [:]
    ) async throws -> RelayProcess {
        let port = try freeLoopbackPort()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["serve"]
        process.environment = [
            "CMUX_RELAY_HMAC_SECRET": secret,
            "CMUX_RELAY_ISSUER": TestTicketMinter.issuer,
            "CMUX_RELAY_BIND": "127.0.0.1:\(port)",
        ].merging(extraEnvironment) { _, extra in extra }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let relay = RelayProcess(url: URL(string: "ws://127.0.0.1:\(port)/v1/relay")!, process: process)

        let health = URL(string: "http://127.0.0.1:\(port)/healthz")!
        let deadline = Date().addingTimeInterval(10)
        while true {
            if !process.isRunning {
                throw NSError(domain: "RelayProcess", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "cmux-relay exited before it was healthy",
                ])
            }
            if let (_, response) = try? await URLSession.shared.data(from: health),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return relay
            }
            if Date() > deadline {
                relay.stop()
                throw NSError(domain: "RelayProcess", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "cmux-relay did not become healthy",
                ])
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Stops and reaps the relay. `Process.waitUntilExit` was seen to hang here when the
    /// child had already exited, so reap with `waitpid` and escalate to SIGKILL after 5 s.
    func stop() {
        let pid = process.processIdentifier
        guard pid > 0, process.isRunning else { return }
        kill(pid, SIGTERM)
        var status: Int32 = 0
        for _ in 0..<500 {
            let reaped = waitpid(pid, &status, WNOHANG)
            // `reaped == -1` means Foundation already reaped it.
            if reaped == pid || reaped == -1 { return }
            usleep(10_000)
        }
        kill(pid, SIGKILL)
        _ = waitpid(pid, &status, 0)
    }

    private static func freeLoopbackPort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EMFILE) }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                bind(fd, generic, length) == 0 && getsockname(fd, generic, &length) == 0
            }
        }
        guard bound else { throw POSIXError(.EADDRINUSE) }
        return UInt16(bigEndian: address.sin_port)
    }
}
