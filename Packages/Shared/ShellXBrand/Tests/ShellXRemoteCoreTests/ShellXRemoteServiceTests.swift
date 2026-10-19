import Foundation
import Testing
@testable import ShellXRemoteCore

private let fpA = "a1b2c3d4e5f60718"
private let hostRoute = "relay+wss://relay.test/v2/relay"

private extension ServiceRig {
    var inviteTicket: URL { paths.coreStateDir.appendingPathComponent("tickets/invite-connect.ticket") }
    func enrollCreate() -> [String] {
        RemoteCommandLine.enrollCreate(paths: paths, route: hostRoute, slot: "slot-self", ticketFile: inviteTicket, ttlSeconds: 300)
    }
    /// Signed in, host up, one pending request `p1` shown.
    func withPending(_ items: [JSONValue]) async -> Bool {
        core.pending.with { $0 = items }
        guard await startConnected() else { return false }
        return await until { self.service.pendingApprovals.map(\.id) == items.compactMap { item -> String? in
            if case .object(let o) = item, case .string(let id)? = o["pairing_id"] { return id }
            return nil
        } }
    }
}

// MARK: - Gate, sign-in and lifecycle

@MainActor @Test func gateOffStartsNothing() async {
    let rig = ServiceRig(gate: false)
    rig.service.startIfEnabled()
    await settle()
    rig.clock.advance(by: 120)
    await settle()
    #expect(rig.launcher.calls.isEmpty)
    #expect(rig.core.calls.isEmpty)
    #expect(rig.bridge.starts.get().isEmpty)
    #expect(rig.service.hostState == .idle)
    #expect(!rig.service.isSignedIn)
}

@MainActor @Test func signedOutStartsNothingButConfig() async {
    let rig = ServiceRig(signedIn: false)
    rig.service.startIfEnabled()
    #expect(await until { rig.core.methods == ["config.set", "machines.list"] })
    await settle()
    rig.clock.advance(by: 120)
    await settle()
    #expect(rig.core.methods == ["config.set", "machines.list"])
    #expect(rig.core.lastParams("config.set") == [
        "api_base": .string("http://127.0.0.1:8787"), "state_dir": .string(rig.paths.coreStateDir.path),
        "app_version": .string("2.0.0"), "os_version": .string("26.0.0"), "platform": .string("macos"),
        "device_name": .string("Phu's Mac (DEV t)")])
    #expect(rig.launcher.calls.isEmpty)
    #expect(rig.bridge.starts.get().isEmpty)
    #expect(!rig.service.isSignedIn)
    #expect(rig.service.hostState == .idle)
}

@MainActor @Test func signInStartsHost() async throws {
    let rig = ServiceRig(signedIn: false)
    rig.service.startIfEnabled()
    #expect(await until { rig.core.methods == ["config.set", "machines.list"] })
    let thrown1 = await errorCode { try await rig.service.signIn(email: "dev@shellx.test", password: "wrong") }
    #expect(thrown1 == "invalid_credentials")
    #expect(!rig.service.isSignedIn)

    try await rig.service.signIn(email: "dev@shellx.test", password: "pw")
    #expect(rig.core.lastParams("auth.login") == ["email": .string("dev@shellx.test"), "password": .string("pw")])
    #expect(rig.service.isSignedIn)
    #expect(await until { rig.service.hostState == rig.hostConnected })
    #expect(rig.core.lastParams("machines.register") == [
        "name": .string("Phu's Mac (DEV t)"), "platform": .string("macos"), "os_version": .string("26.0.0"),
        "app_version": .string("2.0.0")])
    // Bridge first, then the daemon, registered with this machine's slot and the minted relay route.
    #expect(rig.log.all.filter { $0 == "bridge:start" || $0 == "launch:server start" } == ["bridge:start", "launch:server start"])
    #expect(rig.bridge.starts.get() == [rig.paths.bridgeSocket])
    let start = rig.launcher.launches.first { $0.args.starts(with: ["server", "start"]) }
    #expect(start?.args == RemoteCommandLine.serverStart(paths: rig.paths, route: hostRoute, slot: "slot-self",
                                                         ticketFile: rig.base.registerTicket))
    #expect(await until { rig.service.machines.map(\.id) == ["m_1"] })   // this machine is never listed
    #expect(rig.service.machines.first?.access == RemoteMachine.Access.none)
}

@MainActor @Test func devCredentialsSignInAtLaunch() async {
    let dev = ShellXRemoteDevCredentials(email: "dev@shellx.test", password: "pw")
    let rig = ServiceRig(signedIn: false, devCredentials: dev)
    rig.service.startIfEnabled()
    #expect(await until { rig.service.isSignedIn })
    #expect(Array(rig.core.methods.prefix(3)) == ["config.set", "machines.list", "auth.login"])
    #expect(!String(describing: dev).contains("pw") && !String(reflecting: dev).contains("pw"))
}

@MainActor @Test func signOutStopsEverything() async throws {
    let rig = ServiceRig()
    try rig.seedRecord(enrolled: true)
    #expect(await rig.startConnected())
    #expect(await until { rig.connectIndex != nil })               // the enrolled link to online m_1 runs
    #expect(await rig.quiet(at: [5, 15, 30]))                       // pending, list and heartbeat asleep
    let runs = rig.launcher.runs.count, stops = rig.bridge.stops.get()
    await rig.service.signOut()
    #expect(rig.core.methods.last == "auth.logout")
    #expect(!rig.service.isSignedIn)
    #expect(rig.service.machines.isEmpty)
    #expect(rig.service.hostState == .idle)
    #expect(rig.launcher.procs.allSatisfy { $0.terminated })
    #expect(rig.launcher.runs.dropFirst(runs).contains { $0.args == RemoteCommandLine.serverStop(paths: rig.paths) })
    #expect(rig.bridge.stops.get() > stops)
    let calls = rig.core.calls.count, launches = rig.launcher.launches.count
    rig.clock.advance(by: 120)
    await settle()
    #expect(rig.core.calls.count == calls)
    #expect(rig.launcher.launches.count == launches)
}

@MainActor @Test func missingCmuxTuiFailsHostWithoutLaunch() async {
    let rig = ServiceRig(cmuxTuiPresent: false)
    rig.service.startIfEnabled()
    #expect(await until { rig.service.hostState == .failed(code: "cmux_tui_missing") })
    await settle()
    #expect(rig.service.isSignedIn)
    #expect(rig.launcher.calls.isEmpty)
    #expect(rig.bridge.starts.get().isEmpty)
    #expect(rig.core.count("machines.register") == 0)
    let thrown2 = await errorCode { _ = try await rig.service.requestAccess(to: "m_1") }
    #expect(thrown2 == "cmux_tui_missing")
    #expect(rig.launcher.calls.isEmpty)
}

@MainActor @Test func staleInviteFilesAreSweptAtLaunch() async throws {
    let rig = ServiceRig(signedIn: false)
    let tickets = rig.paths.coreStateDir.appendingPathComponent("tickets", isDirectory: true)
    try FileManager.default.createDirectory(at: tickets, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    func put(_ name: String, age: TimeInterval = 0) throws {
        let url = tickets.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
    }
    try put("invite-1a2b3c4d.uri"); try put("invite-connect.ticket"); try put("invite-old.part", age: 400)
    try put("invite-new.part"); try put("register.ticket", age: 4000); try put("connect-12345678.ticket")
    let outside = rig.base.dir.appendingPathComponent("outside.uri")
    try Data("keep".utf8).write(to: outside)
    try FileManager.default.createSymbolicLink(at: tickets.appendingPathComponent("invite-link.uri"), withDestinationURL: outside)
    // What the directory held when the first core call ran.
    let atFirstCall = Locked<[String]?>(nil)
    rig.core.onCall.with { $0 = { _ in
        atFirstCall.with { if $0 == nil { $0 = ((try? FileManager.default.contentsOfDirectory(atPath: tickets.path)) ?? []).sorted() } }
    } }
    rig.service.startIfEnabled()
    #expect(await until { rig.core.methods.first == "config.set" })
    let expected = ["connect-12345678.ticket", "invite-new.part", "register.ticket"]
    #expect(atFirstCall.get() == expected)
    #expect(try FileManager.default.contentsOfDirectory(atPath: tickets.path).sorted() == expected)
    #expect(FileManager.default.fileExists(atPath: outside.path))   // the link was removed, never followed
}

@MainActor @Test func heartbeatRunsEvery30s() async {
    let rig = ServiceRig()
    #expect(await rig.startConnected())
    #expect(rig.core.count("machines.heartbeat") == 0)
    #expect(await rig.advance(30, waitingFor: "machines.heartbeat"))
    #expect(rig.core.count("machines.heartbeat") == 1)
    #expect(await rig.advance(30, waitingFor: "machines.heartbeat"))
    #expect(rig.core.count("machines.heartbeat") == 2)
    rig.clock.advance(by: 29)
    await settle()
    #expect(rig.core.count("machines.heartbeat") == 2)
}

@MainActor @Test func apiDownKeepsLastMachinesAndRecovers() async {
    let rig = ServiceRig()
    #expect(await rig.startConnected())
    #expect(await until { rig.service.machines.map(\.id) == ["m_1"] })
    rig.core.down.with { $0 = ["machines.list": "network", "machines.heartbeat": "http_503", "pair.pending": "network"] }
    #expect(await rig.advance(15, waitingFor: "machines.list"))
    #expect(await rig.advance(15, waitingFor: "machines.list"))
    await settle()
    #expect(rig.service.isSignedIn)
    #expect(rig.service.machines.map(\.id) == ["m_1"])
    #expect(rig.service.hostState == rig.hostConnected)
    // The API comes back with one more machine.
    rig.core.down.with { $0 = [:] }
    rig.core.machines.with { $0.append(FakeRemoteCore.machine("m_2", "Studio", online: false, lastSeen: 1_700_000_000)) }
    #expect(await rig.advance(15, waitingFor: "machines.list"))
    #expect(await until { rig.service.machines.map(\.id) == ["m_1", "m_2"] })
    #expect(rig.service.machines.last?.online == false)
    #expect(rig.service.machines.last?.lastSeen == Date(timeIntervalSince1970: 1_700_000_000))
}

@MainActor @Test func unauthorizedMidSessionSignsOut() async throws {
    let rig = ServiceRig()
    try rig.seedRecord(enrolled: true)
    #expect(await rig.startConnected())
    #expect(await until { rig.connectIndex != nil })
    rig.core.down.with { $0 = ["machines.list": "unauthorized"] }
    #expect(await rig.advance(15, waitingFor: "machines.list"))
    #expect(await until { !rig.service.isSignedIn && rig.service.hostState == .idle })
    #expect(rig.service.machines.isEmpty)
    #expect(await until { rig.launcher.procs.allSatisfy { $0.terminated } })
}

@MainActor @Test func terminateStopsDaemonAndHeartbeat() async {             // Review Focus 5
    let rig = ServiceRig()
    #expect(await rig.startConnected())
    #expect(await rig.advance(30, waitingFor: "machines.heartbeat"))
    #expect(await rig.quiet(at: [35, 45, 60]))                     // pending, list and heartbeat asleep
    let runs = rig.launcher.runs.count, stops = rig.bridge.stops.get()
    rig.service.stopForTermination()
    #expect(rig.launcher.runs.dropFirst(runs).contains { $0.args == RemoteCommandLine.serverStop(paths: rig.paths) })
    #expect(rig.launcher.procs.allSatisfy { $0.terminated })
    #expect(rig.bridge.stops.get() > stops)
    let beats = rig.core.count("machines.heartbeat"), calls = rig.core.calls.count
    rig.clock.advance(by: 120)
    await settle()
    #expect(rig.core.count("machines.heartbeat") == beats)
    #expect(rig.core.calls.count == calls)
}

@MainActor @Test func terminateIsBoundedWhenServerStopHangs() async {
    let rig = ServiceRig()
    #expect(await rig.startConnected())
    let stops = rig.bridge.stops.get()
    rig.launcher.holdNextServerStop.with { $0 = true }
    let began = Date()
    rig.service.stopForTermination()
    #expect(Date().timeIntervalSince(began) < 2)
    #expect(rig.launcher.isHoldingRun)                              // the hang really happened
    #expect(rig.bridge.stops.get() > stops)                         // and the bridge still stopped
    rig.launcher.releaseHeldRun()
}

// MARK: - On-site approval (target side)

@MainActor @Test func approveCreatesInvitationSealsAndExpectsIt() async throws {
    let rig = ServiceRig()
    #expect(await rig.withPending([FakeRemoteCore.pairing("p1", fingerprint: fpA)]))
    let uri = fixtureInviteURI(id: "inv1")
    rig.stub(["remote", "enroll", "create"], stdout: uri + "\n")
    try await rig.service.approve("p1")
    #expect(rig.core.lastParams("tickets.mint") == ["permission": .string("connect"), "target_machine_id": .string("m_self"),
                                                    "write_to": .string("invite-connect.ticket")])
    #expect(rig.ran(rig.enrollCreate()))
    #expect(rig.core.lastParams("pair.approve") == ["pairing_id": .string("p1"), "invite_uri": .string(uri),
                                                    "fingerprint": .string(fpA)])
    let order = rig.log.all.filter { ["core:tickets.mint", "run:remote enroll", "core:pair.approve"].contains($0) }
    #expect(Array(order.suffix(3)) == ["core:tickets.mint", "run:remote enroll", "core:pair.approve"])
    #expect(rig.service.pendingApprovals.isEmpty)
    // The invite never travels in argv.
    #expect(!rig.launcher.calls.contains { $0.args.contains { $0.contains("cmux://") } })

    rig.stub(["remote", "enroll", "pending"],
             stdout: #"[{"invitation_id":"inv1","device_name":"Mac mini","device_fingerprint":"x","requested_at_unix":1}]"#)
    #expect(await until { rig.clock.deadlines.contains(rig.clock.now + 1) })
    rig.clock.advance(by: 1)
    #expect(await until { rig.ran(RemoteCommandLine.enrollApprove(paths: rig.paths, invitationID: "inv1")) })
    #expect(!rig.ran(RemoteCommandLine.enrollDeny(paths: rig.paths, invitationID: "inv1")))
}

@MainActor @Test func unknownPendingEnrollmentIsDenied() async throws {             // Review Focus 3
    let rig = ServiceRig()
    #expect(await rig.withPending([FakeRemoteCore.pairing("p1", fingerprint: fpA)]))
    rig.stub(["remote", "enroll", "create"], stdout: fixtureInviteURI(id: "inv1"))
    try await rig.service.approve("p1")
    rig.stub(["remote", "enroll", "pending"], stdout: #"[{"invitation_id":"evil"}]"#)
    #expect(await until { rig.clock.deadlines.contains(rig.clock.now + 1) })
    rig.clock.advance(by: 1)
    #expect(await until { rig.ran(RemoteCommandLine.enrollDeny(paths: rig.paths, invitationID: "evil")) })
    #expect(!rig.ran(RemoteCommandLine.enrollApprove(paths: rig.paths, invitationID: "evil")))
    // The real enrollment still goes through afterwards; another stranger is denied.
    rig.stub(["remote", "enroll", "pending"], stdout: #"[{"invitation_id":"inv1"},{"invitation_id":"evil2"}]"#)
    #expect(await until { rig.clock.deadlines.contains(rig.clock.now + 1) })
    rig.clock.advance(by: 1)
    #expect(await until { rig.ran(RemoteCommandLine.enrollApprove(paths: rig.paths, invitationID: "inv1")) })
    #expect(await until { rig.ran(RemoteCommandLine.enrollDeny(paths: rig.paths, invitationID: "evil2")) })
}

@MainActor @Test func suspiciousRequestIsRefusedBeforeAnyProcess() async {
    let rig = ServiceRig()
    #expect(await rig.withPending([FakeRemoteCore.pairing("p1", suspicious: true)]))
    #expect(rig.service.pendingApprovals.first?.suspicious == true)
    let runs = rig.launcher.runs.count, mints = rig.core.count("tickets.mint")
    let thrown3 = await errorCode { try await rig.service.approve("p1") }
    #expect(thrown3 == "fingerprint_mismatch")
    #expect(rig.launcher.runs.count == runs)
    #expect(rig.core.count("tickets.mint") == mints)
    #expect(rig.core.count("pair.approve") == 0)
}

@MainActor @Test func fingerprintChangeForSamePairingMarksSuspicious() async {
    let rig = ServiceRig()
    #expect(await rig.withPending([FakeRemoteCore.pairing("p1", fingerprint: fpA), FakeRemoteCore.pairing("p2", code: "111111")]))
    #expect(rig.service.pendingApprovals.allSatisfy { !$0.suspicious })
    #expect(rig.service.pendingApprovals.first?.requesterName == "Mac mini")
    // The server swaps p1's key and p2's code while both are shown.
    rig.core.pending.with { $0 = [FakeRemoteCore.pairing("p1", fingerprint: "ffffffffffffffff"), FakeRemoteCore.pairing("p2", code: "222222")] }
    #expect(await rig.advance(5, waitingFor: "pair.pending"))
    #expect(await until { rig.service.pendingApprovals.allSatisfy { $0.suspicious } })
    #expect(rig.service.pendingApprovals.map(\.fingerprint) == [fpA, fpA])   // still what the person saw
    #expect(rig.service.pendingApprovals.map(\.code) == ["123456", "111111"])
    // Sticky: going back to the shown values does not clear it.
    rig.core.pending.with { $0 = [FakeRemoteCore.pairing("p1", fingerprint: fpA), FakeRemoteCore.pairing("p2", code: "111111")] }
    #expect(await rig.advance(5, waitingFor: "pair.pending"))
    await settle()
    #expect(rig.service.pendingApprovals.allSatisfy { $0.suspicious })
    let thrown4 = await errorCode { try await rig.service.approve("p1") }
    #expect(thrown4 == "fingerprint_mismatch")
    #expect(rig.core.count("pair.approve") == 0)
}

@MainActor @Test func approveAlwaysPassesShownFingerprint() async throws {
    let rig = ServiceRig()
    #expect(await rig.withPending([FakeRemoteCore.pairing("p1", fingerprint: fpA),
                                   FakeRemoteCore.pairing("p2", from: "m_2", fingerprint: "0123456789abcdef")]))
    rig.stub(["remote", "enroll", "create"], stdout: fixtureInviteURI(id: "inv1"))
    try await rig.service.approve("p1")
    #expect(rig.core.lastParams("pair.approve")?["fingerprint"] == .string(fpA))
    // The core refuses p2 (key swapped server side): the invitation made for it is denied at the daemon.
    rig.stub(["remote", "enroll", "create"], stdout: fixtureInviteURI(id: "inv2"))
    rig.core.failures.with { $0["pair.approve"] = ["fingerprint_mismatch"] }
    let thrown5 = await errorCode { try await rig.service.approve("p2") }
    #expect(thrown5 == "fingerprint_mismatch")
    #expect(rig.core.lastParams("pair.approve")?["fingerprint"] == .string("0123456789abcdef"))
    #expect(rig.ran(RemoteCommandLine.enrollDeny(paths: rig.paths, invitationID: "inv2")))
    // inv2 is no longer expected: if it shows up at the daemon it is denied, inv1 still approved.
    rig.stub(["remote", "enroll", "pending"], stdout: #"[{"invitation_id":"inv2"},{"invitation_id":"inv1"}]"#)
    #expect(await until { rig.clock.deadlines.contains(rig.clock.now + 1) })
    rig.clock.advance(by: 1)
    #expect(await until { rig.ran(RemoteCommandLine.enrollApprove(paths: rig.paths, invitationID: "inv1")) })
    #expect(!rig.ran(RemoteCommandLine.enrollApprove(paths: rig.paths, invitationID: "inv2")))
}

@MainActor @Test func denyRemovesTheRequest() async {
    let rig = ServiceRig()
    #expect(await rig.withPending([FakeRemoteCore.pairing("p1")]))
    await rig.service.deny("p1")
    #expect(rig.core.lastParams("pair.deny") == ["pairing_id": .string("p1")])
    #expect(rig.service.pendingApprovals.isEmpty)
    // A poll that still lists it (server lag) does not bring it back.
    #expect(await rig.advance(5, waitingFor: "pair.pending"))
    await settle()
    #expect(rig.service.pendingApprovals.isEmpty)
}

// MARK: - Requesting access and opening sessions (viewer side)

@MainActor @Test func requestAccessReturnsCodeAndTracksOutgoing() async throws {
    let rig = ServiceRig()
    #expect(await rig.startConnected())
    #expect(await until { rig.service.machines.map(\.id) == ["m_1"] })
    let code = try await rig.service.requestAccess(to: "m_1")
    #expect(code == "123456")
    #expect(rig.core.lastParams("pair.request") == ["to_machine_id": .string("m_1")])
    #expect(rig.service.outgoing.map(\.status) == [.waiting])
    #expect(rig.service.outgoing.first?.ownFingerprint == FakeRemoteCore.ownFingerprint)
    #expect(rig.service.machines.first?.access == .requested(pairingID: "p_out", code: "123456"))

    let inviteName = "invite-\(SHA256Pure.hash8("p_out")).uri"
    #expect(await rig.advance(2, waitingFor: "pair.poll"))
    #expect(rig.core.lastParams("pair.poll") == ["pairing_id": .string("p_out"), "write_invite_to": .string(inviteName)])
    #expect(rig.service.outgoing.map(\.status) == [.waiting])
    rig.core.pollStatus.with { $0["p_out"] = "approved" }
    #expect(await rig.advance(2, waitingFor: "pair.poll"))
    #expect(await until { rig.service.outgoing.map(\.status) == [.approved] })
    let invite = rig.paths.coreStateDir.appendingPathComponent("tickets/" + inviteName)
    #expect(await until { rig.connectIndex != nil })
    let connect = rig.launcher.launches[rig.connectIndex!].args
    #expect(connect.firstIndex(of: "--invite-file").map { connect[$0 + 1] } == invite.path)
    #expect(try rig.store.load() == [RemoteLinkRecord(machineID: "m_1", route: hostRoute, slot: "slot-m1",
                                                      daemonFingerprint: "dfp-m1", enrolled: false)])
    #expect(rig.service.machines.first?.access == .granted)
}

@MainActor @Test func outgoingPairingExpiresAfter300s() async throws {
    let rig = ServiceRig()
    #expect(await rig.startConnected())
    _ = try await rig.service.requestAccess(to: "m_1")
    #expect(await rig.advance(2, waitingFor: "pair.poll"))
    #expect(await until { rig.clock.deadlines.contains(supT0 + 4) })
    rig.clock.advance(to: supT0 + 300)
    #expect(await until { rig.service.outgoing.map(\.status) == [.expired] })
    #expect(rig.service.machines.first?.access == RemoteMachine.Access.none)
    #expect(rig.connectIndex == nil)
}

@MainActor @Test func openSessionRunsListThenCreateThenOpensWorkspace() async throws {
    let rig = ServiceRig()
    try rig.seedRecord(enrolled: true)
    #expect(await rig.startConnected())
    #expect(await until { rig.connectIndex != nil })                // enrolled + online: the link starts by itself
    let index = rig.connectIndex!
    let connect = rig.launcher.launches[index].args
    #expect(connect.contains("--daemon") && !connect.contains("--invite-file"))
    rig.stubSequence(["terminal", "list"], ["[]", #"[{"id":"term_7","title":"zsh","cols":80,"rows":24}]"#])
    let socket = rig.paths.clientSocket(for: "m_1")
    rig.launcher.line(index, #"{"event":"connection-snapshot","local_socket":"x","connection":{}}"#)
    #expect(await until { rig.service.machines.first?.link == .connected(localSocket: socket.path) })

    try await rig.service.openSession(on: "m_1")
    let cli = rig.launcher.runs.filter { $0.args.first == "--socket" }.map(\.args)
    #expect(cli == [RemoteCommandLine.terminalList(clientSocket: socket),
                    RemoteCommandLine.workspaceCreate(clientSocket: socket, name: "ShellX"),
                    RemoteCommandLine.terminalList(clientSocket: socket)])
    #expect(rig.opener.opened.count == 1)
    let opened = try #require(rig.opener.opened.first)
    #expect(opened.title == "Mac mini")
    #expect(opened.command == RemoteCommandLine.attachShellCommand(clientPath: rig.cmuxTui.path, socketPath: socket.path,
                                                                   terminalID: "term_7"))
    #expect(rig.service.remoteWorkspaces == [opened.id: "m_1"])
    rig.service.forgetRemoteWorkspace(opened.id)                     // L3 calls this when the workspace closes
    #expect(rig.service.remoteWorkspaces.isEmpty)
    try await rig.service.openSession(on: "m_1")
    #expect(rig.service.remoteWorkspaces.count == 1)
    await rig.service.signOut()
    #expect(rig.service.remoteWorkspaces.isEmpty)
}

@MainActor @Test func openSessionThrowsOfflineAfter20s() async throws {
    let rig = ServiceRig()
    try rig.seedRecord(enrolled: true)
    rig.core.machines.with { $0 = [FakeRemoteCore.machine("m_self", "me", online: true, thisMachine: true),
                                   FakeRemoteCore.machine("m_1", "Mac mini", online: false)] }
    #expect(await rig.startConnected())
    #expect(await until { rig.service.machines.first?.online == false })
    let target = rig.clock.now + 20
    let outcome = Task { @MainActor in await errorCode { try await rig.service.openSession(on: "m_1") } }
    #expect(await until { rig.clock.deadlines.contains(target) })
    rig.clock.advance(to: target)
    #expect(await outcome.value == "offline")
    #expect(rig.opener.opened.isEmpty)
    let thrown6 = await errorCode { try await rig.service.openSession(on: "m_9") }
    #expect(thrown6 == "not_granted")
}

@MainActor @Test func coreCallsNeverRunOnMainThread() async throws {           // Review Focus 2
    let rig = ServiceRig(signedIn: false)
    rig.core.pending.with { $0 = [FakeRemoteCore.pairing("p1"), FakeRemoteCore.pairing("p2")] }
    rig.service.startIfEnabled()
    #expect(await until { rig.core.methods == ["config.set", "machines.list"] })
    try await rig.service.signIn(email: "dev@shellx.test", password: "pw")
    #expect(await until { rig.service.hostState == rig.hostConnected && rig.service.pendingApprovals.count == 2 })
    rig.stub(["remote", "enroll", "create"], stdout: fixtureInviteURI(id: "inv1"))
    try await rig.service.approve("p1")
    await rig.service.deny("p2")
    _ = try await rig.service.requestAccess(to: "m_1")
    #expect(await rig.advance(2, waitingFor: "pair.poll"))
    #expect(await rig.advance(to: supT0 + 30, waitingFor: "machines.heartbeat"))
    await rig.service.signOut()
    let methods = Set(rig.core.methods)
    #expect(methods.isSuperset(of: ["config.set", "machines.list", "auth.login", "machines.register", "tickets.mint",
                                    "pair.pending", "pair.approve", "pair.deny", "pair.request", "pair.poll",
                                    "machines.heartbeat", "auth.logout"]))
    #expect(rig.core.calls.allSatisfy { !$0.onMainThread })
}

// MARK: - Fix round 1

@MainActor private func serverStopArgs(_ rig: ServiceRig) -> [String] { RemoteCommandLine.serverStop(paths: rig.paths) }

@MainActor @Test func pairingThatVanishesAndReturnsChangedStaysSuspicious() async {          // I1
    let rig = ServiceRig()
    #expect(await rig.withPending([FakeRemoteCore.pairing("p1", fingerprint: fpA), FakeRemoteCore.pairing("p2", code: "222222")]))
    // The server leaves both out of one poll...
    rig.core.pending.with { $0 = [] }
    #expect(await rig.advance(5, waitingFor: "pair.pending"))
    #expect(await until { rig.service.pendingApprovals.isEmpty })
    // ...then lists p1 with another key and p2 unchanged.
    rig.core.pending.with { $0 = [FakeRemoteCore.pairing("p1", fingerprint: "ffffffffffffffff"),
                                  FakeRemoteCore.pairing("p2", code: "222222")] }
    #expect(await rig.advance(5, waitingFor: "pair.pending"))
    #expect(await until { rig.service.pendingApprovals.count == 2 })
    let p1 = rig.service.pendingApprovals.first { $0.id == "p1" }, p2 = rig.service.pendingApprovals.first { $0.id == "p2" }
    #expect(p1?.suspicious == true)
    #expect(p1?.fingerprint == fpA)                                   // what the person saw
    #expect(p1?.firstSeen == supT0)                                   // the 300 s cap does not restart
    #expect(p2?.suspicious == false)
    #expect(p2?.firstSeen == supT0)
    let thrown = await errorCode { try await rig.service.approve("p1") }
    #expect(thrown == "fingerprint_mismatch")
    #expect(rig.core.count("pair.approve") == 0)
}

@MainActor @Test func expiredPairingIsNotShownAgain() async {
    let rig = ServiceRig()
    #expect(await rig.withPending([FakeRemoteCore.pairing("p1")]))
    #expect(await until { rig.clock.deadlines.contains(supT0 + 5) })
    let polls = rig.core.count("pair.pending")
    rig.clock.advance(to: supT0 + 300)
    #expect(await until { rig.core.count("pair.pending") > polls })
    #expect(await until { rig.service.pendingApprovals.isEmpty })
    #expect(await rig.advance(5, waitingFor: "pair.pending"))         // the server keeps listing it
    await settle()
    #expect(rig.service.pendingApprovals.isEmpty)
}

@MainActor @Test func unenrolledRecordsAreDroppedAtLaunch() async throws {                  // R33
    let rig = ServiceRig()
    try rig.seedRecord("m_1", enrolled: false)
    try rig.seedRecord("m_2", enrolled: true)
    #expect(await rig.startConnected())                               // records are loaded before the host starts
    #expect(try rig.store.load().map(\.machineID) == ["m_2"])
    #expect(rig.service.machines.first?.access == RemoteMachine.Access.none)
    #expect(rig.connectIndex == nil)
}

@MainActor @Test func failedFirstEnrollmentForgetsTheGrant() async throws {                 // R33
    let rig = ServiceRig()
    #expect(await rig.startConnected())
    _ = try await rig.service.requestAccess(to: "m_1")
    rig.core.pollStatus.with { $0["p_out"] = "approved" }
    rig.core.failures.with { $0["tickets.mint"] = ["not_granted"] }   // the link's first connect mint fails for good
    #expect(await rig.advance(2, waitingFor: "pair.poll"))
    #expect(await until { rig.service.outgoing.first?.status == .approved })
    #expect(await until { rig.service.machines.first?.access == RemoteMachine.Access.none })
    #expect(await until { (try? rig.store.load())?.isEmpty == true })
    #expect(rig.connectIndex == nil)
    rig.core.pollStatus.with { $0["p_out"] = "pending" }
    let code = try await rig.service.requestAccess(to: "m_1")         // requesting again works
    #expect(code == "123456")
    #expect(rig.service.machines.first?.access == .requested(pairingID: "p_out", code: "123456"))
}

@MainActor @Test func terminationRightAfterTeardownStillStopsTheDaemon() async {           // M2
    let rig = ServiceRig()
    #expect(await rig.startConnected())
    let runs = rig.launcher.runs.count
    rig.service.beginTeardown()                                      // what signOut and a 401 do first, on main
    let began = Date()
    rig.service.stopForTermination()                                 // then main blocks until the stops are done
    #expect(Date().timeIntervalSince(began) < 1)
    #expect(rig.launcher.runs.dropFirst(runs).contains { $0.args == serverStopArgs(rig) })
    #expect(rig.launcher.procs.allSatisfy { $0.terminated })
}

@MainActor @Test func terminationBeforeBootstrapMakesNoCoreCall() async {                  // M4
    let rig = ServiceRig()
    rig.service.startIfEnabled()
    rig.service.stopForTermination()
    for _ in 0..<5 { await settle() }
    #expect(rig.core.calls.isEmpty)
    #expect(rig.launcher.calls.isEmpty)
}

@MainActor @Test func signOutThenSignInConnectsTheHostAgain() async throws {               // M7
    let rig = ServiceRig()
    #expect(await rig.startConnected())
    await rig.service.signOut()
    #expect(rig.service.hostState == .idle)
    #expect(rig.launcher.procs.first?.terminated == true)
    try await rig.service.signIn(email: "dev@shellx.test", password: "pw")
    #expect(await until { rig.service.hostState == rig.hostConnected })
    #expect(rig.launcher.launches.filter { $0.args.starts(with: ["server", "start"]) }.count == 2)
    #expect(rig.bridge.starts.get().count == 2)
    #expect(await until { rig.service.machines.map(\.id) == ["m_1"] })
}

@MainActor @Test func terminationDuringApproveIsBoundedAndLeavesNothing() async {          // M7
    let rig = ServiceRig()
    #expect(await rig.withPending([FakeRemoteCore.pairing("p1", fingerprint: fpA)]))
    rig.stub(["remote", "enroll", "create"], stdout: fixtureInviteURI(id: "inv1"))
    rig.core.holdNext.with { $0 = "pair.approve" }
    let approving = Task { @MainActor in await errorCode { try await rig.service.approve("p1") } }
    #expect(await until { rig.core.isHoldingCall })
    let runs = rig.launcher.runs.count
    let began = Date()
    rig.service.stopForTermination()
    #expect(Date().timeIntervalSince(began) < 2)
    #expect(rig.launcher.runs.dropFirst(runs).contains { $0.args == serverStopArgs(rig) })
    #expect(rig.launcher.procs.allSatisfy { $0.terminated })
    #expect(rig.service.gate.isEmpty)
    rig.core.releaseHeldCall()                                       // the server answers after the quit began
    #expect(await approving.value == "cancelled")
    for _ in 0..<5 { await settle() }
    #expect(rig.service.gate.isEmpty)
    #expect(!rig.launcher.runs.dropFirst(runs).contains { $0.args.starts(with: ["remote", "enroll"]) })
}

// MARK: - Final review fixes

@MainActor @Test func failedEnrollApproveIsRetriedNotDenied() async throws {               // final review 1
    let rig = ServiceRig()
    #expect(await rig.withPending([FakeRemoteCore.pairing("p1", fingerprint: fpA)]))
    rig.stub(["remote", "enroll", "create"], stdout: fixtureInviteURI(id: "inv1"))
    try await rig.service.approve("p1")
    rig.stubs.with { $0.insert(.init(key: ["remote", "enroll", "approve"], replies: [(Int32(1), Data()), (Int32(0), Data())]), at: 0) }
    rig.stub(["remote", "enroll", "pending"], stdout: #"[{"invitation_id":"inv1"}]"#)
    let approveArgs = RemoteCommandLine.enrollApprove(paths: rig.paths, invitationID: "inv1")
    let denyArgs = RemoteCommandLine.enrollDeny(paths: rig.paths, invitationID: "inv1")
    #expect(await until { rig.clock.deadlines.contains(rig.clock.now + 1) })
    rig.clock.advance(by: 1)
    #expect(await until { rig.launcher.runs.filter { $0.args == approveArgs }.count == 1 })   // exits 1
    #expect(await until { rig.clock.deadlines.contains(rig.clock.now + 1) })
    rig.clock.advance(by: 1)
    #expect(await until { rig.launcher.runs.filter { $0.args == approveArgs }.count == 2 })   // tried again, exits 0
    #expect(!rig.ran(denyArgs))
    #expect(await until { rig.service.gate.isEmpty })                                         // single use once it went through
}

/// Signs in as `u_1` (no session at launch), adds a link record and an invite file, signs out, then signs in as `user`.
@MainActor private func signInAgain(as user: String) async throws -> (ServiceRig, URL) {
    let rig = ServiceRig(signedIn: false)
    rig.service.startIfEnabled()
    #expect(await until { rig.core.methods == ["config.set", "machines.list"] })
    try await rig.service.signIn(email: "a@shellx.test", password: "pw")
    #expect(await until { rig.service.hostState == rig.hostConnected })
    try rig.seedRecord("m_1", enrolled: true)
    let invite = rig.paths.coreStateDir.appendingPathComponent("tickets/invite-0123abcd.uri")
    FileManager.default.createFile(atPath: invite.path, contents: Data("cmux://enroll/x".utf8), attributes: [.posixPermissions: 0o600])
    await rig.service.signOut()
    rig.core.userID.with { $0 = user }
    try await rig.service.signIn(email: "b@shellx.test", password: "pw")
    #expect(await until { rig.service.hostState == rig.hostConnected })
    return (rig, invite)
}

@MainActor @Test func signingInAsAnotherAccountDropsTheOldLinks() async throws {          // final review 2
    let (rig, invite) = try await signInAgain(as: "u_2")
    #expect(try rig.store.load().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: invite.path))
    await settle()
    #expect(rig.connectIndex == nil)
    #expect(await until { rig.service.machines.map(\.id) == ["m_1"] })
    #expect(rig.service.machines.first?.access == RemoteMachine.Access.none)
}

@MainActor @Test func signingInAgainAsTheSameAccountKeepsTheLinks() async throws {         // final review 2
    let (rig, _) = try await signInAgain(as: "u_1")
    #expect(try rig.store.load().map(\.machineID) == ["m_1"])
    #expect(await until { rig.connectIndex != nil })
    #expect(await until { rig.service.machines.first?.access == .granted })
}

@MainActor @Test func signInBeforeTheLaunchSweepStillStartsTheHost() async throws {        // final review 3
    let rig = ServiceRig(signedIn: false)
    let tickets = rig.paths.coreStateDir.appendingPathComponent("tickets", isDirectory: true)
    try FileManager.default.createDirectory(at: tickets, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let stale = tickets.appendingPathComponent("invite-stale.uri")
    FileManager.default.createFile(atPath: stale.path, contents: Data("x".utf8), attributes: [.posixPermissions: 0o600])
    // No launch sweep has run yet (startIfEnabled not called): sign-in must not conclude cmux-tui is missing.
    try await rig.service.signIn(email: "dev@shellx.test", password: "pw")
    #expect(await until { rig.service.hostState == rig.hostConnected })
    #expect(!FileManager.default.fileExists(atPath: stale.path))
}

@MainActor @Test func newSessionSweepsRecordsOnlyAfterTheOldLinksStopped() async throws {  // final review 4
    let rig = ServiceRig(signedIn: false)
    rig.service.startIfEnabled()
    #expect(await until { rig.core.methods == ["config.set", "machines.list"] })
    try await rig.service.signIn(email: "dev@shellx.test", password: "pw")
    #expect(await until { rig.service.hostState == rig.hostConnected })
    rig.launcher.holdNextServerStop.with { $0 = true }
    rig.service.beginTeardown()                                     // a 401: nobody awaits these stops
    #expect(await until { rig.launcher.isHoldingRun })
    try rig.seedRecord("m_1", enrolled: false)                      // a grant the stopping link is still enrolling
    let signingIn = Task { @MainActor in try await rig.service.signIn(email: "dev@shellx.test", password: "pw") }
    for _ in 0..<5 { await settle() }
    #expect(try rig.store.load().count == 1)                        // not swept while the old links still stop
    try rig.seedRecord("m_1", enrolled: true)                       // the old link connected meanwhile and saved it
    rig.launcher.releaseHeldRun()
    try await signingIn.value
    #expect(await until { rig.service.hostState == rig.hostConnected })
    #expect(try rig.store.load().map(\.enrolled) == [true])
    #expect(await until { rig.connectIndex != nil })
}

@MainActor @Test func terminationJoinsATeardownEvenWithoutLaunch() async throws {           // final review 5
    let rig = ServiceRig(signedIn: false)
    try await rig.service.signIn(email: "dev@shellx.test", password: "pw")   // started stays false
    #expect(await until { rig.service.hostState == rig.hostConnected })
    let runs = rig.launcher.runs.count
    rig.service.beginTeardown()
    rig.service.stopForTermination()
    #expect(rig.launcher.runs.dropFirst(runs).contains { $0.args == serverStopArgs(rig) })
}

@MainActor @Test func signInWithNoRecordedOwnerDropsTheLinks() async throws {              // final review 2
    let rig = ServiceRig(signedIn: false)
    try rig.seedRecord("m_1", enrolled: true)                       // saved before owners were kept: account unknown
    rig.service.startIfEnabled()
    #expect(await until { rig.core.methods == ["config.set", "machines.list"] })
    try await rig.service.signIn(email: "dev@shellx.test", password: "pw")
    #expect(await until { rig.service.hostState == rig.hostConnected })
    #expect(try rig.store.load().isEmpty)
    #expect(try rig.store.loadOwner() == "u_1")
    #expect(rig.connectIndex == nil)
}
