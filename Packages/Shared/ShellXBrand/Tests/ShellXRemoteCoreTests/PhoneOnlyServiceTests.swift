import Foundation
import Testing
@testable import ShellXRemoteCore

// MARK: - Serving phones without remote machines (ShellX 1.5.1)
//
// `gateEnabled` on and `remoteMachinesEnabled` off: the session signs in, registers this Mac and runs the ShellX
// Link host for phones. Nothing that serves or uses the account's other machines runs: no cmux-tui daemon or
// bridge, no access requests either way, no links to other Macs, no machine list.

@MainActor @Test func phonesOnlyStartsTheLinkHostWithoutTheTerminalHost() async {
    let rig = ServiceRig(remoteMachines: false)
    rig.service.startIfEnabled()
    #expect(await until { !rig.linkHost.starts.isEmpty })
    #expect(rig.linkHost.starts == [FakeLinkHost.Start(machineID: "m_self", linkSlot: "link-self", accountID: "u_1")])
    await settle()
    #expect(rig.core.count("machines.register") == 1)
    #expect(rig.core.count("tickets.mint") == 0)          // no register ticket for the cmux-tui daemon
    #expect(rig.bridge.starts.get().isEmpty)
    #expect(rig.launcher.calls.isEmpty)                    // cmux-tui never runs
    #expect(rig.service.hostState == .idle)
}

@MainActor @Test func phonesOnlyNeedsNoCmuxTui() async {
    let rig = ServiceRig(cmuxTuiPresent: false, remoteMachines: false)
    rig.service.startIfEnabled()
    #expect(await until { !rig.linkHost.starts.isEmpty })
    #expect(rig.service.hostState == .idle)
    #expect(rig.launcher.calls.isEmpty)
}

@MainActor @Test func phonesOnlyKeepsTheHeartbeatAndPollsNoOtherMachines() async {
    let rig = ServiceRig(remoteMachines: false)
    rig.service.startIfEnabled()
    #expect(await until { !rig.linkHost.starts.isEmpty })
    #expect(await rig.quiet(at: [30]))                     // the heartbeat is asleep
    #expect(!rig.clock.deadlines.contains(supT0 + 5))      // no pair.pending timer
    #expect(!rig.clock.deadlines.contains(supT0 + 15))     // no machines.list timer
    // Phones see this Mac online through its heartbeat (`last_seen_at`).
    #expect(await rig.advance(30, waitingFor: "machines.heartbeat"))
    await settle()
    #expect(rig.core.count("pair.pending") == 0)
    #expect(rig.core.count("machines.list") == 1)          // the launch check for a session only
}

@MainActor @Test func phonesOnlyNeverConnectsToOtherMachines() async throws {
    let rig = ServiceRig(remoteMachines: false)
    try rig.seedRecord(enrolled: true)                     // m_1 is online
    try rig.seedRecord("m_2", enrolled: false)
    rig.service.startIfEnabled()
    #expect(await until { !rig.linkHost.starts.isEmpty })
    rig.clock.advance(by: 60)
    await settle()
    #expect(rig.connectIndex == nil)
    #expect(rig.launcher.calls.isEmpty)
    #expect(try rig.store.load().map(\.machineID).sorted() == ["m_1", "m_2"])   // kept for remote machines
}

@MainActor @Test func phonesOnlyRefusesAccessRequestsAndRemoteSessions() async {
    let rig = ServiceRig(remoteMachines: false)
    rig.service.startIfEnabled()
    #expect(await until { !rig.linkHost.starts.isEmpty })
    let requested = await errorCode { _ = try await rig.service.requestAccess(to: "m_1") }
    #expect(requested == "disabled")
    let opened = await errorCode { try await rig.service.openSession(on: "m_1") }
    #expect(opened == "disabled")
    #expect(rig.core.count("pair.request") == 0)
    #expect(rig.opener.opened.isEmpty)
}

@MainActor @Test func phonesOnlySignInStartsTheLinkHostAndSignOutStopsIt() async throws {
    let rig = ServiceRig(signedIn: false, remoteMachines: false)
    rig.service.startIfEnabled()
    #expect(await until { rig.core.methods == ["config.set", "machines.list"] })
    try await rig.service.signIn(email: "a@shellx.test", password: "pw")
    #expect(await until { !rig.linkHost.starts.isEmpty })
    #expect(rig.linkHost.starts.last == FakeLinkHost.Start(machineID: "m_self", linkSlot: "link-self", accountID: "u_1"))
    await rig.service.signOut()
    #expect(rig.linkHost.stops >= 1)
    #expect(rig.core.methods.last == "auth.logout")
    #expect(rig.launcher.calls.isEmpty)
}
