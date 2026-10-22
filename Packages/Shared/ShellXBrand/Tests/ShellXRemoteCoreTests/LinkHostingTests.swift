import Foundation
import Testing
@testable import ShellXRemoteCore

// MARK: - The ShellX Link host follows the host session

@MainActor @Test func registeredLinkSlotStartsTheLinkHost() async {
    let rig = ServiceRig()
    #expect(await rig.startConnected())
    #expect(await until { !rig.linkHost.starts.isEmpty })
    #expect(rig.linkHost.starts == [FakeLinkHost.Start(machineID: "m_self", linkSlot: "link-self")])
}

@MainActor @Test func oldRelayWithoutLinkSlotLeavesTheRestOfTheHostRunning() async {
    let rig = ServiceRig()
    rig.core.linkSlot.with { $0 = nil }
    #expect(await rig.startConnected())                               // the cmux-tui daemon still serves
    await settle()
    #expect(rig.linkHost.starts.isEmpty)
    #expect(rig.core.calls.allSatisfy { $0.params["lane"] == nil })   // no link ticket is ever asked for
}

@MainActor @Test func signOutStopsTheLinkHost() async {
    let rig = ServiceRig()
    #expect(await rig.startConnected())
    #expect(await until { !rig.linkHost.starts.isEmpty })
    await rig.service.signOut()
    #expect(rig.linkHost.stops >= 1)
    #expect(rig.log.all.last { $0.hasPrefix("link:") } == "link:stop")
}

@MainActor @Test func terminationStopsTheLinkHost() async {
    let rig = ServiceRig()
    #expect(await rig.startConnected())
    #expect(await until { !rig.linkHost.starts.isEmpty })
    rig.service.stopForTermination()
    #expect(rig.linkHost.stops >= 1)
}

@MainActor @Test func gateOffNeverStartsTheLinkHost() async {
    let rig = ServiceRig(gate: false)
    rig.service.startIfEnabled()
    await settle()
    #expect(rig.linkHost.starts.isEmpty)
}

// MARK: - Link-lane tickets

@Test func linkTicketIsMintedInlineOnTheLinkLane() throws {
    let rig = FakeRemoteCore(clock: ManualClock(), log: EventLog(), coreStateDir: FileManager.default.temporaryDirectory)
    let client = ShellXCoreClient(rig)
    let ticket = try client.mintLinkTicket(.connect(targetMachineID: "m_self"), expectedSlot: "link-self")
    #expect(ticket.slot == "link-self")
    #expect(ticket.relayURL.absoluteString == FakeRemoteCore.relayURL)
    #expect(rig.lastParams("tickets.mint") == [
        "permission": .string("connect"), "target_machine_id": .string("m_self"), "lane": .string("link")])
    #expect(!String(describing: ticket).contains(ticket.ticket))
}

/// A relay that predates the link lane ignores `lane` and mints a ticket for the cmux-tui slot; registering
/// with it would replace the terminal daemon.
@Test func linkTicketForAnotherSlotIsRefused() {
    let rig = FakeRemoteCore(clock: ManualClock(), log: EventLog(), coreStateDir: FileManager.default.temporaryDirectory)
    rig.linkTicketSlot.with { $0 = "slot-self" }
    let client = ShellXCoreClient(rig)
    #expect(throws: ShellXCoreError(code: "link_slot_mismatch", message: "the relay minted a ticket for another slot")) {
        _ = try client.mintLinkTicket(.register, expectedSlot: "link-self")
    }
}
