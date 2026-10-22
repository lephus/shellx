import Foundation
import Testing
@testable import ShellXRemoteCore

private let statusUp = Data(#"{"daemon_name":"Phu's Mac","daemon_fingerprint":"fp1","connected_clients":0}"#.utf8)

// MARK: - Daemon supervisor

@Test func staleDaemonIsStoppedBeforeStart() async {                        // Review Focus 5
    let rig = SupervisorRig(); let sup = rig.daemon()
    await sup.start(route: supRoute, slot: "S1")
    let launcher = rig.launcher
    #expect(launcher.calls.prefix(2).map { Array($0.args.prefix(2)) } == [["server", "stop"], ["server", "start"]])
    #expect(launcher.calls.first?.args == RemoteCommandLine.serverStop(paths: rig.paths))
    #expect(launcher.calls.first?.executable == rig.cmuxTui)
}

@Test func daemonArgumentsUseBundlePaths() async throws {                    // Review Focus 1
    let rig = SupervisorRig(); let sup = rig.daemon()
    await sup.start(route: supRoute, slot: "S1")
    let start = try #require(rig.launcher.calls.first { $0.args.starts(with: ["server", "start"]) })
    #expect(start.args == RemoteCommandLine.serverStart(paths: rig.paths, route: supRoute, slot: "S1",
                                                        ticketFile: rig.paths.coreStateDir.appending(path: "tickets/register.ticket")))
    #expect(start.env["CMUX_SHELLX_BRIDGE_SOCKET"] == rig.paths.bridgeSocket.path)
    #expect(start.env == ["CMUX_SHELLX_BRIDGE_SOCKET": rig.paths.bridgeSocket.path])
    #expect(rig.launcher.runs.allSatisfy { $0.env.isEmpty })
    // Socket and state dirs exist and are private.
    for dir in [rig.paths.socketDir, rig.paths.daemonStateDir] {
        let mode = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        #expect(mode == 0o700)
    }
    // A second bundle gets its own session, sockets and state.
    let other = SupervisorRig(bundleID: "pro.shellx.desktop", sharingHomeWith: rig); let sup2 = other.daemon()
    await sup2.start(route: supRoute, slot: "S2")
    let start2 = try #require(other.launcher.launches.first)
    func value(_ args: [String], _ flag: String) -> String? { args.firstIndex(of: flag).map { args[$0 + 1] } }
    for flag in ["--session", "--socket", "--remote-state-dir", "--remote-admin-socket", "--remote-link-socket", "--relay-ticket-file"] {
        #expect(value(start.args, flag) != nil)
        #expect(value(start.args, flag) != value(start2.args, flag), "\(flag)")
    }
    #expect(start2.env["CMUX_SHELLX_BRIDGE_SOCKET"] != start.env["CMUX_SHELLX_BRIDGE_SOCKET"])
}

@Test func daemonConnectsWhenEnrollStatusAnswers() async {
    let rig = SupervisorRig(); let sup = rig.daemon()
    let polls = Locked(0)
    rig.launcher.runReply.with { $0 = { args in
        guard args.starts(with: ["remote", "enroll", "status"]) else { return (0, Data()) }
        return polls.with { $0 += 1; return $0 >= 3 } ? (0, statusUp) : (1, Data())
    } }
    await sup.start(route: supRoute, slot: "S1")
    #expect(await sup.state == .connecting)
    #expect(await eventually { rig.clock.deadlines.contains(supT0 + 0.25) })
    rig.clock.advance(to: supT0 + 0.25)
    #expect(await eventually { rig.clock.deadlines.contains(supT0 + 0.5) })
    rig.clock.advance(to: supT0 + 0.5)
    #expect(await eventually { await sup.state == .connected(localSocket: rig.paths.muxSocket.path) })
    #expect(polls.get() == 3)
    #expect(rig.launcher.runs.filter { $0.args == RemoteCommandLine.enrollStatus(paths: rig.paths) }.count == 3)
    #expect(await sup.daemonFingerprint == "fp1")
}

@Test func daemonGivesUpPollingAfterTenSeconds() async {
    let rig = SupervisorRig(); let sup = rig.daemon()
    await sup.start(route: supRoute, slot: "S1")
    for step in 1...40 {
        let next = supT0 + 0.25 * Double(step)
        #expect(await eventually { rig.clock.deadlines.contains(next) })
        rig.clock.advance(to: next)
    }
    #expect(await eventually { await sup.state == .reconnecting(attempt: 1, retryAt: supT0 + 11) })
    #expect(rig.launcher.procs[0].terminated)
    #expect(rig.launcher.runs.filter { $0.args == RemoteCommandLine.enrollStatus(paths: rig.paths) }.count == 41)
}

@Test func daemonCrashRestartsWithBackoff() async {
    let rig = SupervisorRig(); let sup = rig.daemon()
    await sup.start(route: supRoute, slot: "S1")
    #expect(rig.launcher.launches.count == 1)
    rig.launcher.exit(0, status: 1)
    #expect(await eventually { await sup.state == .reconnecting(attempt: 1, retryAt: supT0 + 1) })
    rig.clock.advance(to: supT0 + 1)
    #expect(await eventually { rig.launcher.launches.count == 2 })
    rig.launcher.exit(1, status: 1)
    #expect(await eventually { await sup.state == .reconnecting(attempt: 2, retryAt: supT0 + 3) })
    await settle()
    #expect(rig.launcher.launches.count == 2)
}

@Test func everyRespawnMintsAFreshTicket() async {                          // Review Focus 2
    let rig = SupervisorRig(); let sup = rig.daemon()
    await sup.start(route: supRoute, slot: "S1")
    for crash in 0..<3 {
        rig.launcher.exit(crash, status: 1)
        // The state stays `.reconnecting` across a respawn; wait for this crash's attempt.
        #expect(await eventually { if case .reconnecting(crash + 1, _) = await sup.state { true } else { false } })
        guard let at = await sup.state.retryAt else { return }
        rig.clock.advance(to: at)
        #expect(await eventually { rig.launcher.launches.count == crash + 2 })
    }
    let mints = rig.core.mints.get()
    #expect(mints.count == 4)
    #expect(mints.allSatisfy { $0 == ["permission": .string("register"), "write_to": .string("register.ticket")] })
    let order = rig.log.all.filter { $0.hasPrefix("mint:") || $0.hasPrefix("launch:") || $0.hasPrefix("run:server stop") }
    #expect(order == Array(repeating: ["run:server stop", "mint:register", "launch:server start"], count: 4).flatMap { $0 })
}

@Test func daemonFatalMintFailsWithoutLaunch() async {
    let rig = SupervisorRig(); let sup = rig.daemon()
    rig.core.failures.with { $0 = ["not_registered"] }
    let stream = sup.stateStream
    await sup.start(route: supRoute, slot: "S1")
    #expect(await sup.state == .failed(code: "not_registered"))
    #expect(rig.launcher.launches.isEmpty)
    var seen: [LinkState] = []
    for await s in stream { seen.append(s); if seen.count == 2 { break } }
    #expect(seen == [.connecting, .failed(code: "not_registered")])
    rig.clock.advance(by: 120)
    await settle()
    #expect(rig.core.mintCount == 1)
}

@Test func daemonRetriesNetworkMintFailure() async {
    let rig = SupervisorRig(); let sup = rig.daemon()
    rig.core.failures.with { $0 = ["network"] }
    await sup.start(route: supRoute, slot: "S1")
    #expect(await sup.state == .reconnecting(attempt: 1, retryAt: supT0 + 1))
    #expect(rig.launcher.launches.isEmpty)
    rig.clock.advance(to: supT0 + 1)
    #expect(await eventually { rig.launcher.launches.count == 1 })
    #expect(rig.core.mintCount == 2)
}

@Test func daemonStopTerminatesAndStopsServer() async {
    let rig = SupervisorRig(); let sup = rig.daemon()
    await sup.start(route: supRoute, slot: "S1")
    await sup.stop()
    #expect(rig.launcher.procs[0].terminated)
    #expect(rig.launcher.calls.last?.args == RemoteCommandLine.serverStop(paths: rig.paths))
    #expect(await sup.state == .idle)
    rig.launcher.exit(0, status: 0)          // the terminated process exits late
    rig.clock.advance(by: 900)               // past retry and ticket refresh times
    await settle()
    #expect(rig.launcher.launches.count == 1)
    #expect(rig.core.mintCount == 1)
    #expect(await sup.state == .idle)
}

// MARK: - Client link supervisor

@Test func clientConnectsOnSnapshotLineAndDropsInviteFile() async throws {
    let rig = SupervisorRig(); let invite = try rig.makeInvite()
    let sup = rig.client()
    await sup.start(inviteFile: invite)
    let ticket = rig.paths.coreStateDir.appendingPathComponent("tickets/" + rig.paths.connectTicketName(for: "m_1"))
    let first = try #require(rig.launcher.launches.first)
    #expect(first.args == RemoteCommandLine.connect(paths: rig.paths, machine: "m_1", route: supRoute, slot: "S9",
                                                    ticketFile: ticket, inviteFile: invite, deviceName: "Phu's Mac"))
    #expect(first.env.isEmpty)
    #expect(rig.core.mints.get() == [["permission": .string("connect"), "target_machine_id": .string("m_1"),
                                      "write_to": .string(rig.paths.connectTicketName(for: "m_1"))]])
    rig.launcher.line(0, "not json at all")
    rig.launcher.line(0, #"{"event":"something-else"}"#)
    await settle()
    #expect(await sup.state == .connecting)
    #expect(FileManager.default.fileExists(atPath: invite.path))
    rig.launcher.line(0, #"{"event":"connection-snapshot","local_socket":"/x","connection":{}}"#)
    #expect(await eventually { await sup.state == .connected(localSocket: rig.paths.clientSocket(for: "m_1").path) })
    #expect(!FileManager.default.fileExists(atPath: invite.path))
    #expect(await sup.record.enrolled)
    #expect(await eventually { (try? rig.store.load()) == [rig.record(enrolled: true)] })   // saved on the links queue
    // The next spawn runs without the (consumed) invite.
    rig.launcher.exit(0, status: 1)
    #expect(await eventually { await sup.state == .reconnecting(attempt: 1, retryAt: supT0 + 1) })
    rig.clock.advance(to: supT0 + 1)
    #expect(await eventually { rig.launcher.launches.count == 2 })
    #expect(rig.launcher.launches[1].args == RemoteCommandLine.connect(paths: rig.paths, machine: "m_1", route: supRoute,
        slot: "S9", ticketFile: ticket, inviteFile: nil, deviceName: "Phu's Mac", daemonFingerprint: "a1b2c3d4e5f60718"))
    #expect(rig.core.mintCount == 2)
}

@Test func clientRestartsAsEnrolledAfterExit() async throws {
    // Upstream `remote connect` exits for good on a relay rejection or a lost session: restart it on the
    // backoff, enrolled (no invite, daemon pinned), with a fresh connect ticket before each spawn.
    let rig = SupervisorRig(); let sup = rig.client(record: rig.record(enrolled: true))
    await sup.start(inviteFile: nil)
    let ticket = rig.paths.coreStateDir.appendingPathComponent("tickets/" + rig.paths.connectTicketName(for: "m_1"))
    let enrolledArgs = RemoteCommandLine.connect(paths: rig.paths, machine: "m_1", route: supRoute, slot: "S9", ticketFile: ticket,
                                                 inviteFile: nil, deviceName: "Phu's Mac", daemonFingerprint: "a1b2c3d4e5f60718")
    #expect(rig.launcher.launches.first?.args == enrolledArgs)
    #expect(!enrolledArgs.contains("--invite-file"))
    rig.launcher.line(0, #"{"event":"connection-snapshot"}"#)
    #expect(await eventually { await sup.state == .connected(localSocket: rig.paths.clientSocket(for: "m_1").path) })
    // Exit after a connection, then two back-to-back failures: backoff 1 s, 2 s, 4 s.
    var now = supT0
    for (index, (attempt, delay)) in [(1, 1.0), (2, 2.0), (3, 4.0)].enumerated() {
        rig.launcher.exit(index, status: 1)
        let due = now + delay
        #expect(await eventually { await sup.state == .reconnecting(attempt: attempt, retryAt: due) })
        now = due
        rig.clock.advance(to: now)
        #expect(await eventually { rig.launcher.launches.count == index + 2 })
        #expect(rig.core.mintCount == index + 2)
    }
    #expect(rig.launcher.launches.allSatisfy { $0.args == enrolledArgs })
    let order = rig.log.all.filter { $0.hasPrefix("mint:") || $0.hasPrefix("launch:") }
    #expect(order == Array(repeating: ["mint:connect", "launch:remote connect"], count: 4).flatMap { $0 })
}

@Test func clientUsesRouteFromMintNotRecord() async throws {
    // cmux strips the path from invite routes; the positional route must be the minted relay_url's.
    let rig = SupervisorRig()
    var record = rig.record(enrolled: true); record.route = "relay+wss://relay.test"
    rig.core.relayURL.with { $0 = "wss://relay.test/v2/relay" }
    let sup = rig.client(record: record)
    await sup.start(inviteFile: nil)
    #expect(rig.launcher.launches.first.map { Array($0.args.prefix(3)) } == ["remote", "connect", "relay+wss://relay.test/v2/relay"])
    rig.core.relayURL.with { $0 = "wss://relay2.test/v2/relay" }
    rig.launcher.exit(0, status: 1)
    #expect(await eventually { await sup.state.retryAt != nil })
    rig.clock.advance(to: supT0 + 1)
    #expect(await eventually { rig.launcher.launches.count == 2 })
    #expect(rig.launcher.launches[1].args[2] == "relay+wss://relay2.test/v2/relay")
}

@Test func clientPassesNoDaemonPinWithInviteOrWithoutFingerprint() async throws {
    let rig = SupervisorRig(); let invite = try rig.makeInvite()
    let sup = rig.client(record: rig.record(enrolled: true))
    await sup.start(inviteFile: invite)                          // re-pairing: invite, no pin
    #expect(rig.launcher.launches[0].args.contains("--invite-file"))
    #expect(!rig.launcher.launches[0].args.contains("--daemon"))
    var bare = rig.record(enrolled: true); bare.daemonFingerprint = ""
    let other = SupervisorRig(); let sup2 = other.client(record: bare)
    await sup2.start(inviteFile: nil)
    #expect(!other.launcher.launches[0].args.contains("--daemon"))
}

@Test func clientGoesOfflineWithoutRetrying() async {
    let rig = SupervisorRig(); let sup = rig.client(record: rig.record(enrolled: true))
    await sup.start(inviteFile: nil)
    rig.launcher.exit(0, status: 1)
    #expect(await eventually { await sup.state.retryAt != nil })
    await sup.machineAvailability(online: false, lastSeen: supT0 - 5)
    #expect(await sup.state == .offline(lastSeen: supT0 - 5))
    for _ in 0..<12 { rig.clock.advance(by: 10); await settle() }
    #expect(rig.launcher.launches.count == 1)
    #expect(rig.core.mintCount == 1)
    #expect(await sup.state == .offline(lastSeen: supT0 - 5))
    await sup.machineAvailability(online: true, lastSeen: nil)
    #expect(await eventually { rig.launcher.launches.count == 2 })
    #expect(await sup.state == .connecting)
}

@Test func clientOfflineTerminatesRunningLink() async {
    let rig = SupervisorRig(); let sup = rig.client(record: rig.record(enrolled: true))
    await sup.start(inviteFile: nil)
    rig.launcher.line(0, #"{"event":"connection-snapshot"}"#)
    #expect(await eventually { await sup.state == .connected(localSocket: rig.paths.clientSocket(for: "m_1").path) })
    await sup.machineAvailability(online: false, lastSeen: nil)
    #expect(rig.launcher.procs[0].terminated)
    rig.launcher.exit(0, status: 15)
    await settle()
    #expect(await sup.state == .offline(lastSeen: nil))
}

@Test func duplicateRetryTimersSpawnOnce() async {
    let rig = SupervisorRig(); let sup = rig.client(record: rig.record(enrolled: true))
    await sup.start(inviteFile: nil)
    rig.launcher.exit(0, status: 1)                       // retry A due at t0+1
    #expect(await eventually { await sup.state == .reconnecting(attempt: 1, retryAt: supT0 + 1) })
    await sup.machineAvailability(online: false, lastSeen: nil)
    await sup.machineAvailability(online: true, lastSeen: nil)
    #expect(await eventually { rig.launcher.launches.count == 2 })
    rig.clock.advance(to: supT0 + 0.5)
    rig.launcher.exit(1, status: 1)                       // retry B due at t0+1.5
    #expect(await eventually { await sup.state == .reconnecting(attempt: 1, retryAt: supT0 + 1.5) })
    rig.clock.advance(to: supT0 + 1)                      // A is stale: nothing spawns
    await settle()
    #expect(rig.launcher.launches.count == 2)
    rig.clock.advance(to: supT0 + 1.5)
    #expect(await eventually { rig.launcher.launches.count == 3 })
    rig.launcher.exit(2, status: 1)                       // a stale retryDue must not double-spawn later either
    #expect(await eventually { await sup.state == .reconnecting(attempt: 2, retryAt: supT0 + 3.5) })
    rig.clock.advance(to: supT0 + 3.5)
    #expect(await eventually { rig.launcher.launches.count == 4 })
    await settle()
    #expect(rig.launcher.launches.count == 4)
}

@Test func staleProcessLinesAreIgnored() async {
    let rig = SupervisorRig(); let sup = rig.client(record: rig.record(enrolled: true))
    await sup.start(inviteFile: nil)
    let early = rig.launcher.procs[0]
    await sup.machineAvailability(online: false, lastSeen: nil)
    await sup.machineAvailability(online: true, lastSeen: nil)
    #expect(await eventually { rig.launcher.launches.count == 2 })
    early.onLine(#"{"event":"connection-snapshot"}"#)       // killed process, late line
    early.onExit(1)
    await settle()
    #expect(await sup.state == .connecting)
    rig.launcher.line(1, #"{"event":"connection-snapshot"}"#)
    #expect(await eventually { await sup.state == .connected(localSocket: rig.paths.clientSocket(for: "m_1").path) })
}

@Test func clientDropsInviteOnStopBeforeConnecting() async throws {
    let rig = SupervisorRig(); let invite = try rig.makeInvite()
    let sup = rig.client()
    await sup.start(inviteFile: invite)
    await sup.stop()
    #expect(!FileManager.default.fileExists(atPath: invite.path))
    #expect(rig.launcher.procs[0].terminated)
    #expect(await sup.state == .idle)
    #expect(await !sup.record.enrolled)
    #expect(try rig.store.load() == [])
    rig.clock.advance(by: 900)
    await settle()
    #expect(rig.core.mintCount == 1)
}

@Test func clientDropsInviteOnFatalFailure() async throws {
    let rig = SupervisorRig(); let invite = try rig.makeInvite()
    rig.core.failures.with { $0 = ["not_granted"] }
    let sup = rig.client()
    await sup.start(inviteFile: invite)
    #expect(await sup.state == .failed(code: "not_granted"))
    #expect(rig.launcher.launches.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: invite.path))
}

@Test func clientInviteExpiresAfter300Seconds() async throws {
    let rig = SupervisorRig(); let invite = try rig.makeInvite()
    let sup = rig.client()
    await sup.start(inviteFile: invite)
    rig.launcher.exit(0, status: 1)
    #expect(await eventually { await sup.state.retryAt != nil })
    rig.clock.advance(to: supT0 + 301)
    #expect(await eventually { await sup.state == .failed(code: "invite_expired") })
    #expect(rig.launcher.launches.count == 1)
    #expect(!FileManager.default.fileExists(atPath: invite.path))
}

@Test func clientLaunchFailureRetries() async {
    let rig = SupervisorRig(); let sup = rig.client(record: rig.record(enrolled: true))
    rig.launcher.launchFails.with { $0 = true }
    await sup.start(inviteFile: nil)
    #expect(await sup.state == .reconnecting(attempt: 1, retryAt: supT0 + 1))
}

// MARK: - Ticket refresher

@Test func refresherUsesHalfLife() async throws {
    let rig = SupervisorRig()
    rig.core.lifetime.with { $0 = 2 }
    let url = try await rig.refresher.keepFresh(name: "register.ticket", permission: "register", target: nil)
    #expect(url == rig.registerTicket)
    #expect(rig.core.mintCount == 1)
    #expect(await eventually { rig.clock.deadlines == [supT0 + 1] })
    rig.clock.advance(to: supT0 + 0.999)
    await settle()
    #expect(rig.core.mintCount == 1)
    rig.clock.advance(to: supT0 + 1)
    #expect(await eventually { rig.core.mintCount == 2 })
    #expect(await eventually { rig.clock.deadlines == [supT0 + 2] })
    await rig.refresher.stop(name: "register.ticket")
    #expect(await eventually { rig.clock.deadlines.isEmpty })
    rig.clock.advance(by: 60)
    await settle()
    #expect(rig.core.mintCount == 2)
}

@Test func refresherRetriesWithBackoff() async throws {
    let rig = SupervisorRig()
    rig.core.lifetime.with { $0 = 2 }
    _ = try await rig.refresher.keepFresh(name: "register.ticket", permission: "register", target: nil)
    rig.core.failures.with { $0 = ["network", "http_503"] }
    rig.clock.advance(to: supT0 + 1)                       // refresh fails
    #expect(await eventually { rig.clock.deadlines == [supT0 + 2] })
    rig.clock.advance(to: supT0 + 2)                       // fails again, backoff 2 s
    #expect(await eventually { rig.clock.deadlines == [supT0 + 4] })
    rig.clock.advance(to: supT0 + 4)                       // succeeds, half of 2 s
    #expect(await eventually { rig.clock.deadlines == [supT0 + 5] })
    #expect(rig.core.mintCount == 4)
}

@Test func refresherStopsOnFatalRefreshFailure() async throws {
    let rig = SupervisorRig()
    rig.core.lifetime.with { $0 = 2 }
    _ = try await rig.refresher.keepFresh(name: "register.ticket", permission: "register", target: nil)
    rig.core.failures.with { $0 = ["unauthorized"] }
    rig.clock.advance(to: supT0 + 1)
    #expect(await eventually { rig.core.mintCount == 2 })
    #expect(await eventually { rig.clock.deadlines.isEmpty })
}

@Test func refresherFirstMintFailureThrowsAndMintNowRecovers() async throws {
    let rig = SupervisorRig()
    rig.core.failures.with { $0 = ["network"] }
    await #expect(throws: ShellXCoreError.self) {
        try await rig.refresher.keepFresh(name: "connect-x.ticket", permission: "connect", target: "m_2")
    }
    let url = try await rig.refresher.mintNow(name: "connect-x.ticket")
    #expect(url.lastPathComponent == "connect-x.ticket")
    #expect(rig.core.mints.get().last == ["permission": .string("connect"), "target_machine_id": .string("m_2"),
                                          "write_to": .string("connect-x.ticket")])
    await #expect(throws: ShellXCoreError.self) { try await rig.refresher.mintNow(name: "unknown.ticket") }
}

// MARK: - Failure classes and sidecar process

@Test func linkFailureClassification() {
    for code in ["unauthorized", "forbidden", "not_logged_in", "not_registered", "not_granted", "machine_not_found",
                 "invalid_params", "state_dir_insecure", "invite_expired", "http_401", "http_404"] {
        #expect(LinkFailure.isFatal(code), "\(code)")
    }
    for code in ["network", "server", "internal", "io", "http_500", "http_503", "http_408", "http_429", "bad_response", "core_call_failed"] {
        #expect(!LinkFailure.isFatal(code), "\(code)")
    }
    #expect(LinkFailure.code(for: ShellXCoreError(code: "network", message: "m")) == "network")
    #expect(LinkFailure.code(for: CocoaError(.fileNoSuchFile)) == "core_call_failed")
}

@Test func sidecarProcessScrubsEnvironment() async throws {
    setenv("CMUX_SHELLX_LEAK_TEST", "leak", 1)
    let env = URL(fileURLWithPath: "/usr/bin/env")
    let process = ShellXSidecarProcess()
    let allowed: Set<String> = ["HOME", "PATH", "LANG", "TMPDIR", "CMUX_SHELLX_BRIDGE_SOCKET"]
    func parse(_ lines: [String]) -> [String: String] {
        Dictionary(lines.compactMap { l in l.firstIndex(of: "=").map { (String(l[..<$0]), String(l[l.index(after: $0)...])) } },
                   uniquingKeysWith: { a, _ in a })
    }
    let ran = try await process.run(env, [], env: ["CMUX_SHELLX_BRIDGE_SOCKET": "/tmp/sx/bridge.sock"])
    #expect(ran.status == 0)
    let vars = parse(String(decoding: ran.stdout, as: UTF8.self).split(separator: "\n").map(String.init))
    #expect(Set(vars.keys).isSubset(of: allowed), "\(vars.keys.sorted())")
    #expect(vars["PATH"] == "/usr/bin:/bin")
    #expect(vars["CMUX_SHELLX_BRIDGE_SOCKET"] == "/tmp/sx/bridge.sock")
    #expect(vars["HOME"] == ProcessInfo.processInfo.environment["HOME"])

    let lines = Locked<[String]>([])
    let status: Int32 = await withCheckedContinuation { cont in
        do {
            _ = try process.launch(env, [], env: [:], onLine: { line in lines.with { $0.append(line) } },
                                   onExit: { cont.resume(returning: $0) })
        } catch { cont.resume(returning: -99) }
    }
    #expect(status == 0)
    let launched = parse(lines.get())
    #expect(launched["PATH"] == "/usr/bin:/bin")
    #expect(Set(launched.keys).isSubset(of: allowed.subtracting(["CMUX_SHELLX_BRIDGE_SOCKET"])), "\(launched.keys.sorted())")
    #expect(ShellXSidecarProcess.scrubbedEnvironment(base: ["HOME": "/h", "CMUX_SOCKET": "/s", "PATH": "/opt/bin", "LANG": "vi_VN.UTF-8",
                                                            "TMPDIR": "/t", "SSH_AUTH_SOCK": "/a"], extra: ["K": "v"])
            == ["HOME": "/h", "PATH": "/usr/bin:/bin", "LANG": "vi_VN.UTF-8", "TMPDIR": "/t", "K": "v"])
}

// MARK: - Fix round 1

@Test func daemonStopDuringStaleStopLeavesNoRefresher() async {
    // stop() while start() is suspended in its pre-start `server stop`: nothing may be minted afterwards.
    let rig = SupervisorRig(); let sup = rig.daemon()
    rig.launcher.holdNextServerStop.with { $0 = true }
    let starting = Task { await sup.start(route: supRoute, slot: "S1") }
    #expect(await eventually { rig.launcher.isHoldingRun })
    await sup.stop()
    rig.launcher.releaseHeldRun()
    await starting.value
    await settle()
    #expect(await sup.state == .idle)
    #expect(rig.core.mintCount == 0)
    #expect(await !rig.refresher.isRegistered(name: "register.ticket"))
    #expect(rig.clock.deadlines.isEmpty)
    rig.clock.advance(by: 900)
    await settle()
    #expect(rig.core.mintCount == 0)
    #expect(rig.launcher.launches.isEmpty)
}

@Test func clientStopDuringMintLeavesNoRefresher() async {
    let rig = SupervisorRig(); let sup = rig.client(record: rig.record(enrolled: true))
    rig.core.lifetime.with { $0 = 2 }
    await sup.start(inviteFile: nil)
    rig.launcher.exit(0, status: 1)
    #expect(await eventually { await sup.state.retryAt != nil })
    await sup.stop()
    rig.clock.advance(by: 900)
    await settle()
    #expect(await !rig.refresher.isRegistered(name: rig.paths.connectTicketName(for: "m_1")))
    #expect(rig.core.mintCount == 1)
}

@Test func inviteGivenWhileConnectingIsAdoptedForTheNextSpawn() async throws {
    let rig = SupervisorRig(); let sup = rig.client()
    await sup.start(inviteFile: nil)
    let first = try rig.makeInvite()
    let second = first.deletingLastPathComponent().appendingPathComponent("invite-2")
    try Data("cmux://enroll/other".utf8).write(to: second)
    await sup.start(inviteFile: first)                       // not startable: adopted
    await sup.start(inviteFile: second)                      // replaces the first, which is unlinked
    #expect(!FileManager.default.fileExists(atPath: first.path))
    #expect(FileManager.default.fileExists(atPath: second.path))
    rig.launcher.exit(0, status: 1)
    #expect(await eventually { await sup.state.retryAt != nil })
    rig.clock.advance(to: supT0 + 1)
    #expect(await eventually { rig.launcher.launches.count == 2 })
    let args = rig.launcher.launches[1].args
    #expect(args.firstIndex(of: "--invite-file").map { args[$0 + 1] } == second.path)
    await sup.stop()
    #expect(!FileManager.default.fileExists(atPath: second.path))
}

@Test func inviteGivenWhileConnectedIsDropped() async throws {
    let rig = SupervisorRig(); let sup = rig.client(record: rig.record(enrolled: true))
    await sup.start(inviteFile: nil)
    rig.launcher.line(0, #"{"event":"connection-snapshot"}"#)
    #expect(await eventually { await sup.state == .connected(localSocket: rig.paths.clientSocket(for: "m_1").path) })
    let invite = try rig.makeInvite()
    await sup.start(inviteFile: invite)
    #expect(!FileManager.default.fileExists(atPath: invite.path))
}

@Test func adoptedInviteGetsAFreshLifetime() async throws {
    let rig = SupervisorRig(); let sup = rig.client()
    await sup.start(inviteFile: nil)
    rig.launcher.exit(0, status: 1)
    #expect(await eventually { await sup.state.retryAt != nil })
    rig.clock.advance(to: supT0 + 0.5)
    let invite = try rig.makeInvite()
    await sup.start(inviteFile: invite)                      // deadline t0+300.5
    rig.clock.advance(to: supT0 + 1)
    #expect(await eventually { rig.launcher.launches.count == 2 })
    #expect(rig.launcher.launches[1].args.contains("--invite-file"))
    rig.launcher.exit(1, status: 1)
    #expect(await eventually { await sup.state == .reconnecting(attempt: 2, retryAt: supT0 + 3) })
    rig.clock.advance(to: supT0 + 301)
    #expect(await eventually { await sup.state == .failed(code: "invite_expired") })
    #expect(!FileManager.default.fileExists(atPath: invite.path))
}

@Test func hugeExpiryIsClampedToOneDay() async throws {
    let rig = SupervisorRig()
    rig.core.lifetime.with { $0 = 1e300 }
    _ = try await rig.refresher.keepFresh(name: "register.ticket", permission: "register", target: nil)
    #expect(await eventually { rig.clock.deadlines == [supT0 + RemoteTimers.maxDelay] })
    #expect(RemoteTimers.maxDelay == 86_400)
    #expect(RemoteTimers.clamp(1e300) == 86_400)
    #expect(RemoteTimers.clamp(-5) == 0)
    #expect(RemoteTimers.clamp(.infinity) == 86_400)
    #expect(RemoteTimers.clamp(.nan) == 86_400)
    #expect(RemoteTimers.clamp(2.5) == 2.5)
}

@Test func systemClockSurvivesAbsurdDeadlines() async {
    let clock = SystemRemoteClock()
    try? await clock.sleep(until: .distantPast)              // returns at once
    let far = Task { try await clock.sleep(until: Date(timeIntervalSince1970: 1e300)) }
    far.cancel()
    await #expect(throws: CancellationError.self) { try await far.value }
}

@Test func terminateEscalatesToSigkill() async throws {
    let process = ShellXSidecarProcess(killGrace: 0.2)
    /// Terminates the child once it prints `ready` when `untilReady`, otherwise 0.1 s after launch.
    func exitStatus(_ args: [String], _ executable: String, untilReady: Bool = false) async throws -> Int32 {
        let once = Locked(false)
        // `ready` can arrive before `launch` returns the handle; whichever of the two comes second terminates.
        let start = Locked<(handle: (any SidecarHandle)?, ready: Bool)>((nil, false))
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, any Error>) in
            let finish: @Sendable (Int32) -> Void = { status in
                if once.with({ done in let was = done; done = true; return !was }) { cont.resume(returning: status) }
            }
            let onLine: @Sendable (String) -> Void = { line in
                guard untilReady, line == "ready" else { return }
                start.with { state in state.ready = true; return state.handle }?.terminate()
            }
            do {
                let handle = try process.launch(URL(fileURLWithPath: executable), args, env: [:], onLine: onLine, onExit: finish)
                if untilReady {
                    start.with { state in state.handle = handle; return state.ready ? handle : nil }?.terminate()
                } else {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { handle.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 10) { finish(-1) }
            } catch { cont.resume(throwing: error) }
        }
    }
    // A child that ignores SIGTERM (the ignore survives exec) dies by SIGKILL after the grace period. It says
    // `ready` once its trap is set, so a slow machine cannot deliver the SIGTERM before the trap exists.
    #expect(try await exitStatus(["-c", "trap '' TERM; echo ready; exec /bin/sleep 30"], "/bin/sh", untilReady: true) == SIGKILL)
    // A normal child dies by SIGTERM.
    #expect(try await exitStatus(["30"], "/bin/sleep") == SIGTERM)
}
