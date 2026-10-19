#if DEBUG
import Combine
import Foundation
import ShellXRemoteCore

/// DEBUG stand-in for `ShellXRemoteService` (L5 Task 13), served when the app
/// is launched with `SHELLX_REMOTE_UI_FIXTURES=1`. It starts signed out; any
/// non-empty email and password sign in except the password "wrong".
/// Signed in it serves an online granted PC, an offline Mac mini, a MacBook
/// Air with a pending request (code 123456) and an online Mac Studio with
/// no access yet, so every header state shows.
/// Request access: each request is an `OutgoingPairing` from this Mac
/// (fingerprint `ownFingerprint`). The first request to a machine expires
/// after `expiryDelay`, so the sheet shows "Expired" and "Try again"; every
/// later one is approved after `approvalDelay`, which closes the sheet and
/// opens the session. The MacBook Air's pending request stays waiting: click
/// its "waiting" header to reopen the sheet on it.
/// Approvals (U3): signing in also serves two incoming requests so the
/// on-site approval panel shows: a normal one from the Mac Studio (its
/// fingerprint is the one the server reports for that machine) and a
/// suspicious one from the MacBook Air (a different fingerprint, so Approve is
/// disabled and the core would refuse it with `fingerprint_mismatch`).
/// Approve and Deny remove the request from `pendingApprovals`. DEBUG only:
/// nothing here approves a request on the real service's behalf.
@MainActor
final class ShellXRemoteFixtureService: ObservableObject, ShellXRemoteServicing {
    static let requestCode = "123456"
    /// This Mac's fingerprint as the fixture reports it in outgoing pairings.
    /// Distinct from every fixture machine's and every fixture request's.
    static let ownFingerprint = "5a6b7c8d9e0f1a2b"
    static let approveDelay: UInt64 = 400_000_000
    static let approvalDelay: UInt64 = 4_000_000_000
    static let expiryDelay: UInt64 = 6_000_000_000

    @Published private(set) var machines: [RemoteMachine] = []
    @Published private(set) var pendingApprovals: [PairingRequest] = []
    @Published private(set) var outgoing: [OutgoingPairing] = []
    @Published private(set) var hostState: LinkState = .idle
    @Published private(set) var isSignedIn = false
    @Published private(set) var remoteWorkspaces: [UUID: RemoteMachine.ID] = [:]

    private let now: () -> Date
    private var requestCounts: [RemoteMachine.ID: Int] = [:]

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    static func fixtureMachines(now: Date) -> [RemoteMachine] {
        [
            RemoteMachine(
                id: "fixture-pc", name: "PC Windows · văn phòng", platform: .windows, online: true,
                lastSeen: now, fingerprint: "a1b2c3d4e5f60718", isThisMachine: false,
                access: .granted, link: .idle
            ),
            RemoteMachine(
                id: "fixture-mini", name: "Mac mini", platform: .macos, online: false,
                lastSeen: now.addingTimeInterval(-3 * 3600), fingerprint: "0f1e2d3c4b5a6978",
                isThisMachine: false, access: .granted, link: .offline(lastSeen: now.addingTimeInterval(-3 * 3600))
            ),
            RemoteMachine(
                id: "fixture-air", name: "MacBook Air", platform: .macos, online: true,
                lastSeen: now, fingerprint: "1122334455667788", isThisMachine: false,
                access: .requested(pairingID: "p1", code: requestCode), link: .idle
            ),
            RemoteMachine(
                id: "fixture-studio", name: "Mac Studio", platform: .macos, online: true,
                lastSeen: now, fingerprint: "8877665544332211", isThisMachine: false,
                access: .none, link: .idle
            ),
        ]
    }

    /// Two incoming requests, the normal one first. The normal request carries
    /// the fingerprint the server reports for its machine (Mac Studio). The
    /// suspicious one claims to be the MacBook Air but carries a fingerprint
    /// that is neither the Air's nor any other fixture machine's, so the
    /// server's fingerprint and the requester's disagree.
    static func fixtureApprovals(now: Date) -> [PairingRequest] {
        [
            PairingRequest(
                id: "approval-studio", fromMachineID: "fixture-studio", requesterName: "Mac Studio",
                code: "482915", fingerprint: "8877665544332211", suspicious: false, firstSeen: now
            ),
            PairingRequest(
                id: "approval-air", fromMachineID: "fixture-air", requesterName: "MacBook Air",
                code: "730264", fingerprint: "deadbeef01234567", suspicious: true,
                firstSeen: now.addingTimeInterval(1)
            ),
        ]
    }

    func requestAccess(to machineID: RemoteMachine.ID) async throws -> String {
        let count = (requestCounts[machineID] ?? 0) + 1
        requestCounts[machineID] = count
        let pairingID = "p-\(machineID)-\(count)"
        update(machineID) { $0.access = .requested(pairingID: pairingID, code: Self.requestCode) }
        // A new request replaces any earlier one to the same machine.
        outgoing.removeAll { $0.toMachineID == machineID }
        outgoing.append(OutgoingPairing(
            id: pairingID, toMachineID: machineID, code: Self.requestCode,
            ownFingerprint: Self.ownFingerprint, status: .waiting, createdAt: now()
        ))
        let expires = count == 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: expires ? Self.expiryDelay : Self.approvalDelay)
            if expires {
                self?.finish(pairingID, as: .expired, access: .none)
            } else {
                self?.finish(pairingID, as: .approved, access: .granted)
            }
        }
        return Self.requestCode
    }

    /// Settles a still-waiting pairing and updates its machine's access.
    private func finish(_ pairingID: OutgoingPairing.ID, as status: OutgoingPairing.Status, access: RemoteMachine.Access) {
        guard isSignedIn,
              let index = outgoing.firstIndex(where: { $0.id == pairingID }),
              outgoing[index].status == .waiting else { return }
        outgoing[index].status = status
        update(outgoing[index].toMachineID) { $0.access = access }
    }

    /// Like the real service: a suspicious request is refused with
    /// `fingerprint_mismatch` and stays listed; otherwise the request leaves
    /// `pendingApprovals`.
    func approve(_ id: PairingRequest.ID) async throws {
        try? await Task.sleep(nanoseconds: Self.approveDelay)
        guard let request = pendingApprovals.first(where: { $0.id == id }) else {
            throw ShellXCoreError(code: "pairing_not_pending", message: "pairing is not pending")
        }
        guard !request.suspicious else {
            throw ShellXCoreError(code: "fingerprint_mismatch", message: "requester fingerprint does not match the server's")
        }
        pendingApprovals.removeAll { $0.id == id }
    }

    func deny(_ id: PairingRequest.ID) async {
        pendingApprovals.removeAll { $0.id == id }
    }

    func openSession(on machineID: RemoteMachine.ID) async throws {
        guard let machine = machines.first(where: { $0.id == machineID }), machine.online else {
            throw ShellXCoreError(code: "offline", message: "machine is offline")
        }
        update(machineID) { $0.link = .connecting }
        try? await Task.sleep(nanoseconds: 800_000_000)
        update(machineID) { $0.link = .connected(localSocket: "/tmp/shellx-fixture.sock") }
    }

    func signIn(email: String, password: String) async throws {
        try? await Task.sleep(nanoseconds: 400_000_000)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty, password != "wrong" else {
            throw ShellXCoreError(code: "invalid_credentials", message: "email or password is incorrect")
        }
        machines = Self.fixtureMachines(now: now())
        // The MacBook Air's pending request, reopened from its header.
        outgoing = [OutgoingPairing(
            id: "p1", toMachineID: "fixture-air", code: Self.requestCode,
            ownFingerprint: Self.ownFingerprint, status: .waiting, createdAt: now()
        )]
        pendingApprovals = Self.fixtureApprovals(now: now())
        isSignedIn = true
    }

    func signOut() async {
        machines = []
        outgoing = []
        pendingApprovals = []
        requestCounts = [:]
        remoteWorkspaces = [:]
        isSignedIn = false
    }

    private func update(_ machineID: RemoteMachine.ID, _ change: (inout RemoteMachine) -> Void) {
        guard let index = machines.firstIndex(where: { $0.id == machineID }) else { return }
        change(&machines[index])
    }
}
#endif
