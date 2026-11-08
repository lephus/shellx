import Foundation
import ShellXAppTestSupport
import ShellXLinkAccount
import ShellXLinkCore
import XCTest

@testable import ShellXAppCore

@MainActor
final class PairingModelTests: XCTestCase {
    private struct Rig {
        var model: PairingModel
        var hub: MachineHub
        var vault: AccountVault
        var relay: FakeRelayAccount
        /// The relay's wait for the user to press Allow on the Mac.
        var approval: ManualSleeper
        var store: InMemorySecretStore
    }

    private func rig(
        _ macs: [FakeMac], saved: [FakeMac] = [],
        relay wrapRelay: (FakeRelayAccount) -> any RelayAccountCalling = { $0 }
    ) async throws -> Rig {
        let store = InMemorySecretStore()
        let vault = AccountVault(store: store)
        try await vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "tok-1", email: "a@b.c"))
        if !saved.isEmpty { try await vault.setMachines(saved.map(\.machine), owner: "u1") }
        let approval = ManualSleeper()
        let fake = FakeRelayAccount(sleep: approval.sleep)
        let relay = wrapRelay(fake)
        let suite = "PairingModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let hub = MachineHub(
            vault: vault, relay: relay, connector: FakeMacFleet(macs, phoneKey: { try await vault.phoneKey() }),
            latency: LatencyLog(), defaults: defaults, sleep: instantSleep, onUnauthorized: {})
        addTeardownBlock { await hub.stopAll() }
        await hub.start()
        return Rig(
            model: PairingModel(hub: hub, relay: relay, vault: vault), hub: hub, vault: vault, relay: fake,
            approval: approval, store: store)
    }

    private func unpairCalls(_ relay: FakeRelayAccount) async -> [String] {
        await relay.calls.compactMap {
            if case let .unpair(grantID, _) = $0 { return grantID }
            return nil
        }
    }

    private func pairCalls(_ relay: FakeRelayAccount) async -> Int {
        await relay.calls.filter {
            if case .pair = $0 { return true }
            return false
        }.count
    }

    // MARK: - Brief tests

    func testValidURIAsksConfirmationBeforeNetwork() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let rig = try await rig([mac])
        let offer = await mac.pairingOffer()

        rig.model.begin(uri: offer.uri)

        XCTAssertEqual(rig.model.step, .confirm(machineName: "MacBook Pro"))
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [], "nothing reaches the relay before the user confirms")
        XCTAssertTrue(rig.hub.machines.isEmpty)

        // A code pasted with blanks or a line break around it is still the code.
        rig.model.cancel()
        XCTAssertEqual(rig.model.step, .idle)
        rig.model.begin(uri: "  \(offer.uri)\n")
        XCTAssertEqual(rig.model.step, .confirm(machineName: "MacBook Pro"))
        let after = await rig.relay.calls
        XCTAssertEqual(after, [])
    }

    func testConfirmPairsSavesAndConnects() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let rig = try await rig([mac])
        let offer = await mac.pairingOffer()
        rig.model.begin(uri: offer.uri)

        await rig.model.confirm()

        XCTAssertEqual(rig.model.step, .paired(machineName: "MacBook Pro"))
        let key = try await rig.vault.phoneKey().publicKey
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [.pair(offerURI: offer.uri, clientKey: key, token: "tok-1")])
        let saved = try await rig.vault.machines()
        XCTAssertEqual(saved, [mac.machine], "the hub saved the Mac, with the host key from the QR code")
        let owner = try await rig.vault.machinesOwner()
        XCTAssertEqual(owner, "u1")
        XCTAssertEqual(rig.hub.machines.map(\.name), ["MacBook Pro"])
        let online = await eventually { rig.hub.machines.first?.state == .online }
        XCTAssertTrue(online, "\(rig.hub.machines.map(\.state))")

        // The offer was used up: confirming again sends nothing.
        await rig.model.confirm()
        let pairs = await pairCalls(rig.relay)
        XCTAssertEqual(pairs, 1)
    }

    func testRepairReplacesSameMachine() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let rig = try await rig([mac], saved: [mac])
        let online = await eventually { rig.hub.machines.first?.state == .online }
        XCTAssertTrue(online)
        await mac.rotateHostKey()
        await mac.dropLiveSessions()
        let changed = await eventually { rig.hub.machines.first?.state == .hostKeyChanged }
        XCTAssertTrue(changed, "\(rig.hub.machines.map(\.state))")

        let offer = await mac.pairingOffer()
        XCTAssertNotEqual(offer.hostKey, mac.machine.hostKey)
        rig.model.begin(uri: offer.uri)
        await rig.model.confirm()

        XCTAssertEqual(rig.model.step, .paired(machineName: "MacBook Pro"))
        let saved = try await rig.vault.machines()
        XCTAssertEqual(saved.map(\.machineID), [mac.machine.machineID], "one record per Mac")
        XCTAssertEqual(saved.first?.hostKey, offer.hostKey, "the new key is pinned")
        XCTAssertEqual(rig.hub.machines.count, 1)
        let back = await eventually { rig.hub.machines.first?.state == .online }
        XCTAssertTrue(back, "\(rig.hub.machines.map(\.state))")
    }

    func testDeniedAndExpiredMapped() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let rig = try await rig([mac])
        let offer = await mac.pairingOffer()

        for (error, failure) in [(PhonePairingError.denied, PairingFailure.denied), (.expired, .expired)] {
            await rig.relay.setError(error, for: .pair)
            rig.model.begin(uri: offer.uri)
            await rig.model.confirm()
            XCTAssertEqual(rig.model.step, .failed(failure))
        }

        XCTAssertTrue(rig.hub.machines.isEmpty)
        let saved = try await rig.vault.machines()
        XCTAssertEqual(saved, [])
    }

    func testOtherAccountMapped() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let rig = try await rig([mac])
        await rig.relay.setError(RelayAPIError.http(status: 404, code: "machine_not_found"), for: .pair)

        rig.model.begin(uri: await mac.pairingOffer().uri)
        await rig.model.confirm()

        XCTAssertEqual(rig.model.step, .failed(.otherAccount))
        XCTAssertTrue(rig.hub.machines.isEmpty)
    }

    func testBadURIMapped() async throws {
        let rig = try await rig([])
        let good = PairingOffer(
            machineID: "m1", linkSlot: "s1", hostKey: Data(repeating: 7, count: 32), code: Data(repeating: 9, count: 16),
            machineName: "Mac"
        ).uri
        /// `good` with the query field `name` set to `value`, or removed when `value` is nil.
        func variant(_ name: String, _ value: String?) -> String {
            var parts = URLComponents(string: good)!
            parts.queryItems = (parts.queryItems ?? []).compactMap { item in
                guard item.name == name else { return item }
                return value.map { URLQueryItem(name: name, value: $0) }
            }
            return parts.string!
        }
        let cases: [(String, PairingFailure)] = [
            ("", .notShellXCode),
            ("hello", .notShellXCode),
            ("https://shellx.pro/pair?v=1", .notShellXCode),
            (variant("v", "2"), .needsUpdate),
            (variant("k", "short"), .damagedCode),
            (variant("n", nil), .damagedCode),
        ]
        for (text, failure) in cases {
            rig.model.begin(uri: text)
            XCTAssertEqual(rig.model.step, .failed(failure), text)
        }
        // A good code still works after a bad one.
        rig.model.begin(uri: good)
        XCTAssertEqual(rig.model.step, .confirm(machineName: "Mac"))
        let calls = await rig.relay.calls
        XCTAssertEqual(calls, [])
    }

    func testCancelStopsWaiting() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let rig = try await rig([mac])
        await rig.relay.setApprovalDelay(.seconds(2))
        rig.model.begin(uri: await mac.pairingOffer().uri)

        let confirming = Task { await rig.model.confirm() }
        let waiting = await eventually { rig.approval.waiting.count == 1 }
        XCTAssertTrue(waiting)
        XCTAssertEqual(rig.model.step, .waitingForMac(machineName: "MacBook Pro"))

        rig.model.cancel()

        XCTAssertEqual(rig.model.step, .idle)
        await confirming.value
        XCTAssertEqual(rig.model.step, .idle, "a cancelled attempt reports nothing")
        XCTAssertEqual(rig.approval.cancelled, 1, "the wait for the Mac stopped")
        XCTAssertTrue(rig.hub.machines.isEmpty)
        let saved = try await rig.vault.machines()
        XCTAssertEqual(saved, [])

        // The offer was dropped with the attempt.
        await rig.model.confirm()
        let pairs = await pairCalls(rig.relay)
        XCTAssertEqual(pairs, 1)
    }

    // MARK: - More

    func testNetworkAndServerErrorsMapped() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let rig = try await rig([mac])
        let offer = await mac.pairingOffer()
        let cases: [(any Error, PairingFailure)] = [
            (URLError(.notConnectedToInternet), .network),
            (RelayAPIError.http(status: 500, code: "internal"), .server(code: "internal")),
            (RelayAPIError.badResponse, .server(code: "bad_response")),
        ]
        for (error, failure) in cases {
            await rig.relay.setError(error, for: .pair)
            rig.model.begin(uri: offer.uri)
            await rig.model.confirm()
            XCTAssertEqual(rig.model.step, .failed(failure))
        }
    }

    /// The Mac approves just as the user cancels (the relay call ignores the cancellation): the
    /// cancelled attempt must not save or connect anything, and takes back the grant the relay made,
    /// so the Mac does not list an iPhone that does not know it.
    func testApprovalAfterCancelIsIgnored() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let gate = Gate()
        let rig = try await rig([mac], relay: { HeldPairRelay(base: $0, gate: gate) })
        rig.model.begin(uri: await mac.pairingOffer().uri)

        let confirming = Task { await rig.model.confirm() }
        let held = await eventually { gate.waiting == 1 }
        XCTAssertTrue(held)
        rig.model.cancel()
        gate.open()
        await confirming.value

        XCTAssertEqual(rig.model.step, .idle)
        XCTAssertTrue(rig.hub.machines.isEmpty)
        let saved = try await rig.vault.machines()
        XCTAssertEqual(saved, [])
        let unpaired = await unpairCalls(rig.relay)
        XCTAssertEqual(unpaired, ["grant-\(mac.machine.machineID)"], "the orphan grant was withdrawn")
        let grants = try await rig.relay.machines(token: "tok-1")
        XCTAssertEqual(grants, [])
    }

    /// The Mac approved but the iPhone could not save it: the grant is taken back too.
    func testSaveFailureAfterApprovalWithdrawsGrant() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let rig = try await rig([mac])
        _ = try await rig.vault.phoneKey()
        rig.store.failWrites = .failed(status: -25300)
        rig.model.begin(uri: await mac.pairingOffer().uri)

        await rig.model.confirm()

        XCTAssertEqual(rig.model.step, .failed(.server(code: "keychain")))
        XCTAssertTrue(rig.hub.machines.isEmpty)
        let unpaired = await unpairCalls(rig.relay)
        XCTAssertEqual(unpaired, ["grant-\(mac.machine.machineID)"])
        let grants = try await rig.relay.machines(token: "tok-1")
        XCTAssertEqual(grants, [])
    }

    /// Withdrawing is best effort: a relay that cannot be reached leaves the failure as it was.
    func testWithdrawErrorsAreIgnored() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let rig = try await rig([mac])
        _ = try await rig.vault.phoneKey()
        rig.store.failWrites = .failed(status: -25300)
        await rig.relay.setError(URLError(.notConnectedToInternet), for: .unpair)
        rig.model.begin(uri: await mac.pairingOffer().uri)

        await rig.model.confirm()

        XCTAssertEqual(rig.model.step, .failed(.server(code: "keychain")))
    }

    /// Cancelling a re-pair of a Mac this iPhone already keeps must not take away its grant: that
    /// grant is not an orphan.
    func testCancelledRepairKeepsTheGrantOfAPairedMac() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let gate = Gate()
        let rig = try await rig([mac], saved: [mac], relay: { HeldPairRelay(base: $0, gate: gate) })
        rig.model.begin(uri: await mac.pairingOffer().uri)

        let confirming = Task { await rig.model.confirm() }
        _ = await eventually { gate.waiting == 1 }
        rig.model.cancel()
        gate.open()
        await confirming.value

        let unpaired = await unpairCalls(rig.relay)
        XCTAssertEqual(unpaired, [])
        XCTAssertEqual(rig.hub.machines.map(\.id), [mac.machine.machineID])
    }

    /// The system routes a link whatever the scheme's case, and the parser wants it lowercase: the
    /// inbox and the model agree, so `SHELLX-LINK://pair…` reaches the confirmation, and the relay
    /// gets the code with a lowercase scheme.
    func testUppercaseSchemeLinkReachesConfirmation() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let rig = try await rig([mac])
        let uri = await mac.pairingOffer().uri
        let shouted = "SHELLX-LINK" + uri.dropFirst("shellx-link".count)
        let inbox = PairingInbox()

        XCTAssertTrue(inbox.receive(try XCTUnwrap(URL(string: shouted))))
        rig.model.begin(uri: try XCTUnwrap(inbox.take()))

        XCTAssertEqual(rig.model.step, .confirm(machineName: "MacBook Pro"))
        await rig.model.confirm()
        XCTAssertEqual(rig.model.step, .paired(machineName: "MacBook Pro"))
        let key = try await rig.vault.phoneKey().publicKey
        let calls = await rig.relay.calls
        XCTAssertEqual(calls.first, .pair(offerURI: uri, clientKey: key, token: "tok-1"))
    }

    /// The relay refuses the token while pairing: the app signs out to the "session expired" sign-in,
    /// instead of leaving the user retrying a pairing that cannot work.
    func testUnauthorizedWhilePairingSignsOut() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let saved = FakeMac(name: "Mac mini")
        let vault = AccountVault(store: InMemorySecretStore())
        try await vault.setSession(StoredSession(userID: "u1", deviceID: "d1", token: "tok-1", email: "a@b.c"))
        try await vault.setMachines([saved.machine], owner: "u1")
        let relay = FakeRelayAccount()
        let suite = "PairingModelTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let box = CoordinatorBox()
        let coordinator = AppCoordinator(
            vault: vault, relay: relay, deviceName: "iPhone", wipers: [],
            makeHub: {
                MachineHub(
                    vault: vault, relay: relay,
                    connector: FakeMacFleet([mac, saved], phoneKey: { try await vault.phoneKey() }),
                    latency: LatencyLog(), defaults: UserDefaults(suiteName: suite)!, sleep: instantSleep,
                    onUnauthorized: { await box.coordinator?.handleUnauthorized() })
            })
        box.coordinator = coordinator
        addTeardownBlock { await coordinator.hub?.stopAll() }
        await coordinator.launch()
        let hub = try XCTUnwrap(coordinator.hub)
        await relay.setError(RelayAPIError.http(status: 401, code: "unauthorized"), for: .pair)
        let model = PairingModel(hub: hub, relay: relay, vault: vault)
        model.begin(uri: await mac.pairingOffer().uri)

        await model.confirm()

        XCTAssertEqual(coordinator.phase, .signedOut(expired: true), "sign-in says the session expired")
        let session = try await vault.session()
        XCTAssertNil(session)
        let machines = try await vault.machines()
        XCTAssertEqual(machines, [saved.machine], "the paired Macs stay for the same account")
    }

    /// A second link while waiting replaces the attempt: the first stops and asks again.
    func testNewLinkWhileWaitingStartsOver() async throws {
        let mac = FakeMac(name: "MacBook Pro")
        let other = FakeMac(name: "Mac mini")
        let rig = try await rig([mac, other])
        await rig.relay.setApprovalDelay(.seconds(2))
        rig.model.begin(uri: await mac.pairingOffer().uri)
        let confirming = Task { await rig.model.confirm() }
        _ = await eventually { rig.approval.waiting.count == 1 }

        rig.model.begin(uri: await other.pairingOffer().uri)

        XCTAssertEqual(rig.model.step, .confirm(machineName: "Mac mini"), "a new link always asks first")
        await confirming.value
        XCTAssertEqual(rig.model.step, .confirm(machineName: "Mac mini"))
        XCTAssertEqual(rig.approval.cancelled, 1)
        XCTAssertTrue(rig.hub.machines.isEmpty)
    }
}

/// A relay whose `pair` waits for the gate, ignoring cancellation, then answers like the base.
private struct HeldPairRelay: RelayAccountCalling {
    let base: FakeRelayAccount
    let gate: Gate

    func login(email: String, password: String, deviceName: String, clientKey: Data) async throws -> AccountSession {
        try await base.login(email: email, password: password, deviceName: deviceName, clientKey: clientKey)
    }
    func nonce() async throws -> String { try await base.nonce() }
    func signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: Data) async throws -> AccountSignIn {
        try await base.signInWithGoogle(idToken: idToken, nonce: nonce, deviceName: deviceName, clientKey: clientKey)
    }
    func linkGoogle(idToken: String, nonce: String, token: String) async throws -> AccountSignIn {
        try await base.linkGoogle(idToken: idToken, nonce: nonce, token: token)
    }
    func signInWithApple(
        identityToken: String, authorizationCode: String, nonce: String, deviceName: String, clientKey: Data
    ) async throws -> AppleSignInResult {
        try await base.signInWithApple(
            identityToken: identityToken, authorizationCode: authorizationCode, nonce: nonce, deviceName: deviceName,
            clientKey: clientKey)
    }
    func linkApple(offerURI: String, linkToken: String, clientKey: Data) async throws -> AppleLinkApproval {
        try await base.linkApple(offerURI: offerURI, linkToken: linkToken, clientKey: clientKey)
    }
    func deleteAccount(idToken: String, nonce: String, token: String) async throws {
        try await base.deleteAccount(idToken: idToken, nonce: nonce, token: token)
    }
    func logout(token: String) async throws { try await base.logout(token: token) }
    func machines(token: String) async throws -> [PairedMachineListing] { try await base.machines(token: token) }
    func unpair(grantID: String, token: String) async throws { try await base.unpair(grantID: grantID, token: token) }
    func pair(offerURI: String, clientKey: Data, token: String) async throws -> PairedMachine {
        await gate.wait()
        return try await base.pair(offerURI: offerURI, clientKey: clientKey, token: token)
    }
    func setPushToken(_ hexToken: String, topic: String, environment: APNsEnvironment, token: String) async throws {
        try await base.setPushToken(hexToken, topic: topic, environment: environment, token: token)
    }
}
