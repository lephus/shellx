import AppKit
import Foundation
import ShellXBrand
import ShellXLinkCore
import ShellXRemoteCore
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Pairing an iPhone from the Mac: a phone is trusted only with a proof from the QR on screen and the
/// person's Allow, and Remove cuts the phone off here before the relay hears of it.
@MainActor
struct ShellXPhonePairingCoordinatorTests {
    // MARK: - Proofs and offers

    @Test func testValidProofBecomesCandidate() async throws {
        let rig = Rig()
        rig.coordinator.open()
        await rig.ticker.waitUntilSleeping()
        let offer = try await rig.coordinator.currentOffer()
        let phone = Data(repeating: 7, count: 32)
        rig.relay.setPending([Self.request("p1", name: "Phu's iPhone", key: phone, proof: offer.proof(clientKey: phone))])

        await rig.coordinator.pollNow()

        #expect(rig.coordinator.candidates == [
            ShellXPhonePairingCoordinator.Candidate(id: "p1", deviceName: "Phu's iPhone", platform: "ios", clientKey: phone),
        ])
        #expect(rig.relay.denied.isEmpty)
        #expect(rig.coordinator.proofMismatches == 0)
        // Showing a request trusts nothing: only Allow does.
        #expect(rig.keys.trustedClients().isEmpty)
        rig.coordinator.close()
    }

    @Test func testAppleLinkRequestShowsTheAppleIDNotice() async throws {
        let rig = Rig()
        rig.coordinator.open()
        await rig.ticker.waitUntilSleeping()
        let offer = try await rig.coordinator.currentOffer()
        let phone = Data(repeating: 7, count: 32)
        let other = Data(repeating: 5, count: 32)
        rig.relay.setPending([
            PhonePairingRequest(id: "a1", deviceName: "Apple phone", platform: "ios", clientKey: phone,
                                proof: offer.proof(clientKey: phone), createdAt: Date(), linksAppleID: true),
            Self.request("p1", key: other, proof: offer.proof(clientKey: other)),
        ])

        await rig.coordinator.pollNow()

        let apple = try #require(rig.coordinator.candidates.first { $0.id == "a1" })
        let plain = try #require(rig.coordinator.candidates.first { $0.id == "p1" })
        #expect(apple.linksAppleID)
        #expect(PhonePairingSheet.appleLinkNotice(for: apple) == String(
            localized: "remote.phonePairing.appleLink",
            defaultValue: "Allowing lets this Apple ID sign in to your ShellX account and manage it, including deleting the account."))
        #expect(!plain.linksAppleID)
        #expect(PhonePairingSheet.appleLinkNotice(for: plain) == nil)
        rig.coordinator.close()
    }

    @Test func testApproveAppleLinkIdentityInUseShowsTheNotice() async throws {
        let rig = Rig()
        rig.coordinator.open()
        await rig.ticker.waitUntilSleeping()
        let offer = try await rig.coordinator.currentOffer()
        let phone = Data(repeating: 6, count: 32)
        rig.relay.setPending([PhonePairingRequest(id: "a1", deviceName: "Apple phone", platform: "ios", clientKey: phone,
                                                  proof: offer.proof(clientKey: phone), createdAt: Date(), linksAppleID: true)])
        await rig.coordinator.pollNow()
        rig.relay.approveError = ShellXCoreError(code: "identity_in_use", message: "in use")
        await #expect(throws: ShellXCoreError.self) { try await rig.coordinator.approve("a1") }
        #expect(rig.coordinator.errorText == String(
            localized: "remote.phonePairing.error.appleIdInUse",
            defaultValue: "This Apple ID already signs in to another ShellX account."))
        rig.coordinator.close()
    }

    @Test func testApproveExpiredAppleLinkShowsExpired() async throws {
        let rig = Rig()
        rig.coordinator.open()
        await rig.ticker.waitUntilSleeping()
        let offer = try await rig.coordinator.currentOffer()
        let phone = Data(repeating: 6, count: 32)
        rig.relay.setPending([PhonePairingRequest(id: "a1", deviceName: "Apple phone", platform: "ios", clientKey: phone,
                                                  proof: offer.proof(clientKey: phone), createdAt: Date(), linksAppleID: true)])
        await rig.coordinator.pollNow()
        rig.relay.approveError = ShellXCoreError(code: "pairing_expired", message: "expired")
        await #expect(throws: ShellXCoreError.self) { try await rig.coordinator.approve("a1") }
        #expect(rig.coordinator.errorText == String(
            format: String(localized: "remote.phonePairing.error", defaultValue: "Something went wrong (%@)"), "pairing_expired"))
        rig.coordinator.close()
    }

    @Test func testProofForOldOfferIsDeniedNotShown() async throws {
        let rig = Rig()
        rig.coordinator.open()
        await rig.ticker.waitUntilSleeping()
        let old = try await rig.coordinator.currentOffer()
        // The offer outlives its lifetime: the next round shows a new QR.
        rig.clock.advance(by: PairingOffer.lifetime + 1)
        await rig.coordinator.pollNow()
        let current = try #require(rig.coordinator.offer)
        #expect(current != old)

        let stale = Data(repeating: 1, count: 32)
        let forged = Data(repeating: 2, count: 32)
        rig.relay.setPending([
            Self.request("old", key: stale, proof: old.proof(clientKey: stale)),
            Self.request("forged", key: forged, proof: Data(repeating: 9, count: 32)),
        ])
        await rig.coordinator.pollNow()
        await rig.coordinator.pollNow()   // a lagging relay lists them again

        #expect(rig.coordinator.candidates.isEmpty)
        #expect(rig.relay.denied.sorted() == ["forged", "old"])   // each refused once
        #expect(rig.coordinator.proofMismatches == 2)
        #expect(rig.relay.approved.isEmpty)
        #expect(rig.keys.trustedClients().isEmpty)
        rig.coordinator.close()
    }

    @Test func testOfferIsSingleUse() async throws {
        let rig = Rig()
        rig.coordinator.open()
        await rig.ticker.waitUntilSleeping()
        let offer = try await rig.coordinator.currentOffer()
        let first = Data(repeating: 3, count: 32)
        let second = Data(repeating: 4, count: 32)
        // Two phones scanned the same QR.
        rig.relay.setPending([
            Self.request("pa", name: "iPhone A", key: first, proof: offer.proof(clientKey: first)),
            Self.request("pb", name: "iPhone B", key: second, proof: offer.proof(clientKey: second)),
        ])
        await rig.coordinator.pollNow()
        #expect(rig.coordinator.candidates.map(\.id) == ["pa", "pb"])

        try await rig.coordinator.approve("pa")
        rig.relay.removePending("pa")

        #expect(rig.relay.approved == ["pa"])
        #expect(rig.keys.trustedClients() == [first])
        // The QR that paired A is spent: B is refused and a new QR is up.
        #expect(rig.relay.denied == ["pb"])
        #expect(rig.coordinator.candidates.isEmpty)
        let next = try #require(rig.coordinator.offer)
        #expect(next != offer)

        // A third phone with a proof for the spent QR is refused, never shown.
        let third = Data(repeating: 5, count: 32)
        rig.relay.setPending([Self.request("pc", key: third, proof: offer.proof(clientKey: third))])
        await rig.coordinator.pollNow()
        #expect(rig.coordinator.candidates.isEmpty)
        #expect(rig.relay.denied == ["pb", "pc"])
        #expect(rig.keys.trustedClients() == [first])
        rig.coordinator.close()
    }

    // MARK: - Allow and Remove

    @Test func testApproveTrustsBeforeRelayAndRollsBackOnFailure() async throws {
        let rig = Rig()
        rig.coordinator.open()
        await rig.ticker.waitUntilSleeping()
        let keys = rig.keys
        let trustedAtApprove = Recorder<Bool>()
        rig.relay.onApprove = { _, key in trustedAtApprove.add(keys.trustedClients().contains(key)) }

        // The relay refuses: the phone must not stay trusted here.
        let phone = Data(repeating: 6, count: 32)
        var offer = try await rig.coordinator.currentOffer()
        rig.relay.setPending([Self.request("p1", key: phone, proof: offer.proof(clientKey: phone))])
        await rig.coordinator.pollNow()
        rig.relay.approveError = ShellXCoreError(code: "pairing_expired", message: "expired")
        await #expect(throws: ShellXCoreError.self) { try await rig.coordinator.approve("p1") }

        #expect(trustedAtApprove.all == [true])   // trusted before the relay was asked
        #expect(!rig.keys.trustedClients().contains(phone))
        #expect(rig.coordinator.errorText != nil)
        // Not only memory: the stored list does not hold it either.
        let reloaded = ShellXLinkKeyStore(storage: rig.storage, accountID: Rig.accountID)
        try reloaded.load()
        #expect(!reloaded.trustedClients().contains(phone))

        // The relay accepts: trusted first, then granted.
        rig.relay.approveError = nil
        try await rig.coordinator.approve("p1")
        #expect(trustedAtApprove.all == [true, true])
        #expect(rig.relay.approved == ["p1"])
        #expect(rig.keys.trustedClients().contains(phone))
        rig.relay.removePending("p1")

        // A phone already paired that scans again keeps its trust when the relay refuses the new request.
        offer = try await rig.coordinator.currentOffer()
        rig.relay.setPending([Self.request("p2", key: phone, proof: offer.proof(clientKey: phone))])
        await rig.coordinator.pollNow()
        rig.relay.approveError = ShellXCoreError(code: "pairing_expired", message: "expired")
        await #expect(throws: ShellXCoreError.self) { try await rig.coordinator.approve("p2") }
        #expect(rig.keys.trustedClients().contains(phone))
        rig.coordinator.close()
    }

    @Test func testRevokeUntrustsAndDisconnectsBeforeRelayCall() async throws {
        let rig = Rig()
        let phoneKey = Data(repeating: 8, count: 32)
        try rig.keys.trust(TrustedPhone(key: phoneKey, deviceID: "d1", name: "iPhone", pairedAt: Date()))
        let phone = PairedPhone(grantID: "g1", deviceID: "d1", deviceName: "iPhone", platform: "ios",
                                clientKey: phoneKey, createdAt: Date(), lastSeen: nil)
        rig.relay.setGrants([phone])
        let keys = rig.keys
        let trustedAtRelay = Recorder<Bool>()
        rig.relay.onRevoke = { _ in trustedAtRelay.add(keys.trustedClients().contains(phoneKey)) }
        rig.coordinator.open()
        await rig.ticker.waitUntilSleeping()

        try await rig.coordinator.revoke(phone)

        #expect(rig.journal.all == ["host.revoke", "relay.revoke g1"])
        #expect(rig.host.revokedKeys == [phoneKey])
        #expect(trustedAtRelay.all == [false])
        #expect(!rig.keys.trustedClients().contains(phoneKey))
        #expect(rig.coordinator.phones.isEmpty)

        // The relay fails: the error shows, and this Mac still does not trust the phone (fail closed).
        try rig.keys.trust(TrustedPhone(key: phoneKey, deviceID: "d1", name: "iPhone", pairedAt: Date()))
        rig.relay.setGrants([phone])
        rig.relay.revokeError = ShellXCoreError(code: "network", message: "offline")
        await #expect(throws: ShellXCoreError.self) { try await rig.coordinator.revoke(phone) }
        #expect(rig.coordinator.errorText != nil)
        #expect(!rig.keys.trustedClients().contains(phoneKey))
        rig.coordinator.close()
    }

    @Test func testOneApprovalAtATime() async throws {
        let rig = Rig()
        rig.coordinator.open()
        await rig.ticker.waitUntilSleeping()
        let offer = try await rig.coordinator.currentOffer()
        let first = Data(repeating: 3, count: 32)
        let second = Data(repeating: 4, count: 32)
        rig.relay.setPending([
            Self.request("pa", key: first, proof: offer.proof(clientKey: first)),
            Self.request("pb", key: second, proof: offer.proof(clientKey: second)),
        ])
        await rig.coordinator.pollNow()
        rig.relay.holdApprovals()
        let approval = Task { try await rig.coordinator.approve("pa") }
        await Self.waitUntil { rig.relay.approvesEntered == 1 }

        // A second Allow while the first is still at the relay is refused before anything is trusted or sent.
        await #expect(throws: ShellXCoreError.self) { try await rig.coordinator.approve("pb") }
        #expect(rig.coordinator.approvingID == "pa")
        #expect(rig.relay.approvesEntered == 1)
        #expect(!rig.keys.trustedClients().contains(second))

        // The QR expires mid-approval: the request being allowed is never refused as a proof mismatch.
        rig.clock.advance(by: PairingOffer.lifetime + 1)
        await rig.coordinator.pollNow()
        #expect(!rig.relay.denied.contains("pa"))
        #expect(rig.coordinator.candidates.map(\.id) == ["pa"])

        rig.relay.releaseApprovals()
        try await approval.value
        rig.relay.removePending("pa")
        #expect(rig.relay.approved == ["pa"])
        #expect(rig.keys.trustedClients() == [first])
        #expect(rig.relay.denied == ["pb"])
        #expect(rig.coordinator.approvingID == nil)
        rig.coordinator.close()
    }

    @Test func testRemoveWithoutRunningHostStillUntrustsFirst() async throws {
        let rig = Rig()
        let phoneKey = Data(repeating: 8, count: 32)
        try rig.keys.trust(TrustedPhone(key: phoneKey, deviceID: "d1", name: "iPhone", pairedAt: Date()))
        let phone = PairedPhone(grantID: "g1", deviceID: "d1", deviceName: "iPhone", platform: "ios",
                                clientKey: phoneKey, createdAt: Date(), lastSeen: nil)
        rig.relay.setGrants([phone])
        let keys = rig.keys
        let trustedAtRelay = Recorder<Bool>()
        rig.relay.onRevoke = { _ in trustedAtRelay.add(keys.trustedClients().contains(phoneKey)) }
        rig.coordinator.open()
        await rig.ticker.waitUntilSleeping()

        // The link host stops (sign-out, relay restart) while the list is still on screen.
        rig.host.pairingHost = nil
        try await rig.coordinator.revoke(phone)

        #expect(trustedAtRelay.all == [false])
        #expect(rig.journal.all == ["relay.revoke g1"])
        #expect(!rig.keys.trustedClients().contains(phoneKey))
        let reloaded = ShellXLinkKeyStore(storage: rig.storage, accountID: Rig.accountID)
        try reloaded.load()
        #expect(!reloaded.trustedClients().contains(phoneKey))
        rig.coordinator.close()

        // Nothing local was ever reachable: refused before the relay is asked.
        let cold = Rig(hostRunning: false)
        cold.relay.setGrants([phone])
        cold.coordinator.open()
        await cold.ticker.waitUntilSleeping()
        await #expect(throws: ShellXCoreError.self) { try await cold.coordinator.revoke(phone) }
        #expect(cold.journal.all.isEmpty)
        cold.coordinator.close()
    }

    @Test func testApproveRefusesWhenTheLinkChanged() async throws {
        let rig = Rig()
        rig.coordinator.open()
        await rig.ticker.waitUntilSleeping()
        let offer = try await rig.coordinator.currentOffer()
        let phone = Data(repeating: 6, count: 32)
        rig.relay.setPending([Self.request("p1", key: phone, proof: offer.proof(clientKey: phone))])
        await rig.coordinator.pollNow()

        // Before Allow, the link host restarts for another account and machine.
        let otherKeys = ShellXLinkKeyStore(storage: rig.storage, accountID: "acct-other")
        rig.host.pairingHost = PhonePairingHost(machineID: "other-machine", linkSlot: "slot_Other",
                                                accountID: "acct-other", machineName: "Mac", keys: otherKeys)
        await #expect(throws: ShellXCoreError.self) { try await rig.coordinator.approve("p1") }

        #expect(rig.relay.approved.isEmpty)
        #expect(!rig.journal.all.contains { $0.hasPrefix("relay.approve") })
        #expect(!rig.keys.trustedClients().contains(phone))
        #expect(!otherKeys.trustedClients().contains(phone))
        #expect(!rig.coordinator.isReady)
        #expect(rig.coordinator.offer == nil)
        #expect(rig.coordinator.candidates.isEmpty)
        #expect(rig.relay.denied == ["p1"])
        rig.coordinator.close()

        // The link host stopped: refused the same way.
        let stopped = Rig()
        stopped.coordinator.open()
        await stopped.ticker.waitUntilSleeping()
        let stoppedOffer = try await stopped.coordinator.currentOffer()
        stopped.relay.setPending([Self.request("p2", key: phone, proof: stoppedOffer.proof(clientKey: phone))])
        await stopped.coordinator.pollNow()
        stopped.host.pairingHost = nil
        await #expect(throws: ShellXCoreError.self) { try await stopped.coordinator.approve("p2") }
        #expect(stopped.relay.approved.isEmpty)
        #expect(!stopped.keys.trustedClients().contains(phone))
        #expect(!stopped.coordinator.isReady)
        stopped.coordinator.close()
    }

    @Test func testErrorsClearOnTheNextSuccessOfTheSameKind() async throws {
        let rig = Rig()
        rig.coordinator.open()
        await rig.ticker.waitUntilSleeping()

        // The paired phones list.
        rig.relay.grantsError = ShellXCoreError(code: "bad_response", message: "bad row")
        await rig.coordinator.refreshPhones()
        #expect(rig.coordinator.errorText != nil)
        rig.relay.grantsError = nil
        await rig.coordinator.refreshPhones()
        #expect(rig.coordinator.errorText == nil)

        // Allow: another kind's success leaves the error; the next approval clears it.
        let phone = Data(repeating: 6, count: 32)
        let offer = try await rig.coordinator.currentOffer()
        rig.relay.setPending([Self.request("p1", key: phone, proof: offer.proof(clientKey: phone))])
        await rig.coordinator.pollNow()
        rig.relay.approveError = ShellXCoreError(code: "pairing_expired", message: "expired")
        await #expect(throws: ShellXCoreError.self) { try await rig.coordinator.approve("p1") }
        #expect(rig.coordinator.errorText != nil)
        await rig.coordinator.refreshPhones()
        #expect(rig.coordinator.errorText != nil)
        rig.relay.approveError = nil
        try await rig.coordinator.approve("p1")
        #expect(rig.coordinator.errorText == nil)

        // Remove.
        let paired = PairedPhone(grantID: "g1", deviceID: "d1", deviceName: "iPhone", platform: "ios",
                                 clientKey: phone, createdAt: Date(), lastSeen: nil)
        rig.relay.setGrants([paired])
        rig.relay.revokeError = ShellXCoreError(code: "network", message: "offline")
        await #expect(throws: ShellXCoreError.self) { try await rig.coordinator.revoke(paired) }
        #expect(rig.coordinator.errorText != nil)
        rig.relay.revokeError = nil
        try await rig.coordinator.revoke(paired)
        #expect(rig.coordinator.errorText == nil)
        rig.coordinator.close()
    }

    @Test func testApproveRewritesTrustAfterTheRelayGrants() async throws {
        let rig = Rig()
        rig.coordinator.open()
        await rig.ticker.waitUntilSleeping()
        let offer = try await rig.coordinator.currentOffer()
        let phone = Data(repeating: 6, count: 32)
        rig.relay.setPending([Self.request("p1", key: phone, proof: offer.proof(clientKey: phone))])
        await rig.coordinator.pollNow()
        let keys = rig.keys, clock = rig.clock
        let firstWrite = rig.clock.now
        let droppedDuringApprove = Recorder<Bool>()
        rig.relay.onApprove = { _, key in
            // A grants check took its snapshot after the first trust write and before this grant existed.
            clock.advance(by: 10)
            _ = try? keys.retainOnly(keys: [], pairedSince: firstWrite.addingTimeInterval(5))
            droppedDuringApprove.add(!keys.trustedClients().contains(key))
        }

        try await rig.coordinator.approve("p1")

        #expect(droppedDuringApprove.all == [true])
        #expect(rig.keys.trustedClients().contains(phone))
        let reloaded = ShellXLinkKeyStore(storage: rig.storage, accountID: Rig.accountID)
        try reloaded.load()
        #expect(reloaded.trustedPhones().first { $0.key == phone }?.pairedAt == firstWrite.addingTimeInterval(10))
        rig.coordinator.close()
    }

    // MARK: - Lifecycle

    @Test func testCloseStopsPolling() async throws {
        let rig = Rig()
        rig.coordinator.open()
        await rig.ticker.waitUntilSleeping()
        #expect(rig.relay.pendingCalls == 1)
        rig.ticker.advance()
        await rig.ticker.waitUntilSleeping(count: 2)
        #expect(rig.relay.pendingCalls == 2)
        #expect(rig.coordinator.offer != nil)

        rig.coordinator.close()
        await rig.ticker.waitUntilCancelled()
        rig.ticker.advance()
        for _ in 0..<20 { await Task.yield() }

        #expect(rig.relay.pendingCalls == 2)
        #expect(rig.coordinator.offer == nil)
        #expect(rig.coordinator.candidates.isEmpty)
        await #expect(throws: ShellXCoreError.self) { _ = try await rig.coordinator.currentOffer() }
    }

    @Test func testMacNotReadyShowsNoOffer() async throws {
        let rig = Rig(hostRunning: false)
        rig.coordinator.open()
        await rig.ticker.waitUntilSleeping()

        #expect(!rig.coordinator.isReady)
        #expect(rig.coordinator.offer == nil)
        #expect(rig.relay.pendingCalls == 0)
        await #expect(throws: ShellXCoreError.self) { _ = try await rig.coordinator.currentOffer() }

        // The link host starts while the sheet is open: the next round makes a QR.
        rig.host.pairingHost = rig.hostInfo
        await rig.coordinator.pollNow()
        #expect(rig.coordinator.isReady)
        #expect(rig.coordinator.offer != nil)
        rig.coordinator.close()
    }

    /// Signed out, this Mac serves no phones until someone signs in under Settings › Account, and the sheet
    /// says so instead of only "not ready".
    @Test func testSignedOutMacAsksToSignIn() async throws {
        let rig = Rig(hostRunning: false, signedIn: false)
        rig.coordinator.open()
        await rig.ticker.waitUntilSleeping()
        #expect(!rig.coordinator.isReady)
        #expect(rig.coordinator.needsSignIn)

        // Signed in from Settings while the sheet is open: the link host starts and a QR shows.
        rig.account.signedIn = true
        rig.host.pairingHost = rig.hostInfo
        await rig.coordinator.pollNow()
        #expect(rig.coordinator.isReady)
        #expect(!rig.coordinator.needsSignIn)
        #expect(rig.coordinator.offer != nil)

        // Signed out again: the hint comes back.
        rig.account.signedIn = false
        rig.host.pairingHost = nil
        await rig.coordinator.pollNow()
        #expect(!rig.coordinator.isReady)
        #expect(rig.coordinator.needsSignIn)
        rig.coordinator.close()
    }

    /// Signed in but the link host is not running yet (still registering): no sign-in hint.
    @Test func testSignedInMacNotReadyYetDoesNotAskToSignIn() async {
        let rig = Rig(hostRunning: false, signedIn: true)
        rig.coordinator.open()
        await rig.ticker.waitUntilSleeping()
        #expect(!rig.coordinator.isReady)
        #expect(!rig.coordinator.needsSignIn)
        rig.coordinator.close()
    }

    // MARK: - Machine name in the QR

    @Test func testOfferNameIsSanitizedForThePhoneParser() async throws {
        let name = ShellXPhonePairingCoordinator.offerName
        #expect(name("  \u{202E}Phu\u{0007}'s Mac\u{2066}\n", "Mac") == "Phu's Mac")
        #expect(name("\u{0000}\u{202A} \u{2069}", "Mac") == "Mac")
        #expect(name("", "Mac") == "Mac")
        let long = name(String(repeating: "é", count: 150), "Mac")
        #expect(long.unicodeScalars.count == 100)

        // Through the coordinator: the QR a hostile-looking name produces still parses on the phone.
        let rig = Rig(machineName: "\u{202E}cam\u{2067} " + String(repeating: "M", count: 120))
        rig.coordinator.open()
        await rig.ticker.waitUntilSleeping()
        let offer = try await rig.coordinator.currentOffer()
        let parsed = try PairingOffer(uri: offer.uri)
        #expect(parsed == offer)
        #expect(parsed.machineName.unicodeScalars.count == 100)
        #expect(!parsed.machineName.unicodeScalars.contains { $0.value == 0x202E || $0.value == 0x2067 })
        rig.coordinator.close()
    }

    // MARK: - Entry point

    @Test func testPairIPhoneMenuOnlyOnThisMacHeader() {
        let local = SidebarMachineHeaderModel(key: .local, title: "MacBook Pro", note: "this Mac",
                                              coolicon: "Laptop", isOnline: true)
        let remote = SidebarMachineHeaderModel(key: .remote(machineID: "m2"), title: "Mac mini", note: "",
                                               coolicon: "Desktop", isOnline: true)

        let menu = SidebarMachineHeaderCellView.contextMenu(for: local, pairingAvailable: true, target: nil)
        #expect(menu?.items.map(\.title) == [String(localized: "remote.phonePairing.menu", defaultValue: "Pair Phone…")])
        #expect(SidebarMachineHeaderCellView.contextMenu(for: remote, pairingAvailable: true, target: nil) == nil)
        #expect(SidebarMachineHeaderCellView.contextMenu(for: local, pairingAvailable: false, target: nil) == nil)
    }

    // MARK: - Helpers

    private static func request(_ id: String, name: String = "iPhone", key: Data, proof: Data) -> PhonePairingRequest {
        PhonePairingRequest(id: id, deviceName: name, platform: "ios", clientKey: key, proof: proof, createdAt: Date())
    }

    private static func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        #expect(condition(), "timed out waiting")
    }
}

/// One coordinator over a fake host, a fake relay, a test clock and a hand-driven poll timer.
@MainActor
private final class Rig {
    static let accountID = "acct-test"

    let journal: Recorder<String>
    let storage: InMemoryLinkSecretStorage
    let keys: ShellXLinkKeyStore
    let relay: FakePhonePairingRelay
    let host: FakePairingHost
    let clock: TestClock
    let ticker: ManualTicker
    let hostInfo: PhonePairingHost
    let coordinator: ShellXPhonePairingCoordinator

    let account: AccountState

    init(hostRunning: Bool = true, signedIn: Bool = true, machineName: String = "Phu's MacBook Pro") {
        let journal = Recorder<String>(), storage = InMemoryLinkSecretStorage(), clock = TestClock()
        let ticker = ManualTicker()
        let keys = ShellXLinkKeyStore(storage: storage, accountID: Self.accountID)
        let relay = FakePhonePairingRelay(journal: journal)
        let hostInfo = PhonePairingHost(machineID: "3f2b9c1e-machine", linkSlot: "slot_AbC-123",
                                        accountID: Self.accountID, machineName: machineName, keys: keys)
        let host = FakePairingHost(journal: journal, keys: keys)
        host.pairingHost = hostRunning ? hostInfo : nil
        self.journal = journal
        self.storage = storage
        self.clock = clock
        self.ticker = ticker
        self.keys = keys
        self.relay = relay
        self.hostInfo = hostInfo
        self.host = host
        let account = AccountState(signedIn: signedIn)
        self.account = account
        coordinator = ShellXPhonePairingCoordinator(
            host: host, relay: relay, pollInterval: .seconds(2), now: { clock.now },
            sleep: { try await ticker.sleep($0) }, fallbackName: "Mac", isSignedIn: { account.signedIn })
    }
}

/// Whether a ShellX account is signed in on this Mac, as the coordinator reads it.
@MainActor
private final class AccountState {
    var signedIn: Bool
    init(signedIn: Bool) { self.signedIn = signedIn }
}

/// `ShellXLinkHostController` as pairing sees it: `revoke` drops trust, then ends the phone's sessions.
@MainActor
private final class FakePairingHost: PhonePairingHosting {
    var pairingHost: PhonePairingHost?
    private(set) var revokedKeys: [Data] = []
    private let journal: Recorder<String>
    private let keys: ShellXLinkKeyStore

    init(journal: Recorder<String>, keys: ShellXLinkKeyStore) {
        self.journal = journal
        self.keys = keys
    }

    /// Like the real controller, does nothing while no link host runs.
    func revoke(clientKey: Data) async {
        guard pairingHost != nil else { return }
        journal.add("host.revoke")
        revokedKeys.append(clientKey)
        try? keys.untrust(key: clientKey)
    }
}

/// The relay's `phones.*`, in memory. Called off the main thread, like the real FFI.
private final class FakePhonePairingRelay: PhonePairingCalling, @unchecked Sendable {
    private let lock = NSLock()
    private let journal: Recorder<String>
    private var pending: [PhonePairingRequest] = []
    private var grants: [PairedPhone] = []
    private var deniedIDs: [String] = []
    private var approvedIDs: [String] = []
    private var pendingCount = 0
    private var approveFailure: ShellXCoreError?
    private var revokeFailure: ShellXCoreError?
    private var approveHook: (@Sendable (String, Data) -> Void)?
    private var revokeHook: (@Sendable (String) -> Void)?
    private var grantsFailure: ShellXCoreError?
    private var approveGate: DispatchSemaphore?
    private var approveEntries = 0

    init(journal: Recorder<String>) { self.journal = journal }

    var grantsError: ShellXCoreError? {
        get { lock.withLock { grantsFailure } }
        set { lock.withLock { grantsFailure = newValue } }
    }
    /// How many `phones.approve` calls have started.
    var approvesEntered: Int { lock.withLock { approveEntries } }

    /// Makes `phones.approve` wait inside the relay until `releaseApprovals()`.
    func holdApprovals() { lock.withLock { approveGate = DispatchSemaphore(value: 0) } }

    func releaseApprovals() {
        let gate = lock.withLock { () -> DispatchSemaphore? in
            defer { approveGate = nil }
            return approveGate
        }
        gate?.signal()
    }

    var denied: [String] { lock.withLock { deniedIDs } }
    var approved: [String] { lock.withLock { approvedIDs } }
    var pendingCalls: Int { lock.withLock { pendingCount } }
    var approveError: ShellXCoreError? {
        get { lock.withLock { approveFailure } }
        set { lock.withLock { approveFailure = newValue } }
    }
    var revokeError: ShellXCoreError? {
        get { lock.withLock { revokeFailure } }
        set { lock.withLock { revokeFailure = newValue } }
    }
    var onApprove: (@Sendable (String, Data) -> Void)? {
        get { lock.withLock { approveHook } }
        set { lock.withLock { approveHook = newValue } }
    }
    var onRevoke: (@Sendable (String) -> Void)? {
        get { lock.withLock { revokeHook } }
        set { lock.withLock { revokeHook = newValue } }
    }

    func setPending(_ requests: [PhonePairingRequest]) { lock.withLock { pending = requests } }
    func removePending(_ id: String) { lock.withLock { pending.removeAll { $0.id == id } } }
    func setGrants(_ phones: [PairedPhone]) { lock.withLock { grants = phones } }

    func pendingPhonePairings() throws -> [PhonePairingRequest] {
        lock.withLock {
            pendingCount += 1
            return pending
        }
    }

    func approvePhonePairing(_ id: String) throws {
        let gate = lock.withLock { () -> DispatchSemaphore? in
            approveEntries += 1
            return approveGate
        }
        gate?.wait()
        let (hook, failure, key) = lock.withLock { (approveHook, approveFailure, pending.first { $0.id == id }?.clientKey) }
        journal.add("relay.approve \(id)")
        if let key { hook?(id, key) }
        if let failure { throw failure }
        lock.withLock { approvedIDs.append(id) }
    }

    func denyPhonePairing(_ id: String) throws {
        journal.add("relay.deny \(id)")
        lock.withLock { deniedIDs.append(id) }
    }

    func pairedPhones() throws -> [PairedPhone] {
        try lock.withLock {
            if let grantsFailure { throw grantsFailure }
            return grants
        }
    }

    func revokePhone(grantID: String) throws {
        let (hook, failure) = lock.withLock { (revokeHook, revokeFailure) }
        journal.add("relay.revoke \(grantID)")
        hook?(grantID)
        if let failure { throw failure }
        lock.withLock { grants.removeAll { $0.grantID == grantID } }
    }
}

/// The poll timer under the test's hand: each `sleep` waits for `advance()` or cancellation.
private final class ManualTicker: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var sleeps = 0
    private var cancellations = 0

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let cancelled: Bool = lock.withLock {
                    sleeps += 1
                    if Task.isCancelled {
                        cancellations += 1
                        return true
                    }
                    waiting[id] = continuation
                    return false
                }
                if cancelled { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let continuation: CheckedContinuation<Void, any Error>? = lock.withLock {
                guard let continuation = waiting.removeValue(forKey: id) else { return nil }
                cancellations += 1
                return continuation
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    /// Ends every current sleep.
    func advance() {
        let all = lock.withLock { () -> [CheckedContinuation<Void, any Error>] in
            defer { waiting.removeAll() }
            return Array(waiting.values)
        }
        for continuation in all { continuation.resume() }
    }

    /// Waits until the poll loop has reached its `count`-th sleep and is parked in it.
    func waitUntilSleeping(count: Int = 1) async {
        await waitFor { self.lock.withLock { self.sleeps >= count && !self.waiting.isEmpty } }
    }

    func waitUntilCancelled() async {
        await waitFor { self.lock.withLock { self.cancellations > 0 } }
    }

    private func waitFor(_ condition: @escaping @Sendable () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        #expect(condition(), "timed out waiting for the poll loop")
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date { lock.withLock { current } }
    func advance(by seconds: TimeInterval) { lock.withLock { current += seconds } }
}

private final class Recorder<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Element] = []
    func add(_ value: Element) { lock.withLock { values.append(value) } }
    var all: [Element] { lock.withLock { values } }
}
