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
@MainActor
final class ShellXRemoteFixtureService: ObservableObject, ShellXRemoteServicing {
    static let requestCode = "123456"

    @Published private(set) var machines: [RemoteMachine] = []
    @Published private(set) var pendingApprovals: [PairingRequest] = []
    @Published private(set) var outgoing: [OutgoingPairing] = []
    @Published private(set) var hostState: LinkState = .idle
    @Published private(set) var isSignedIn = false
    @Published private(set) var remoteWorkspaces: [UUID: RemoteMachine.ID] = [:]

    private let now: () -> Date

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

    func requestAccess(to machineID: RemoteMachine.ID) async throws -> String {
        update(machineID) { $0.access = .requested(pairingID: "p-" + machineID, code: Self.requestCode) }
        return Self.requestCode
    }

    func approve(_ id: PairingRequest.ID) async throws {
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
        isSignedIn = true
    }

    func signOut() async {
        machines = []
        remoteWorkspaces = [:]
        isSignedIn = false
    }

    private func update(_ machineID: RemoteMachine.ID, _ change: (inout RemoteMachine) -> Void) {
        guard let index = machines.firstIndex(where: { $0.id == machineID }) else { return }
        change(&machines[index])
    }
}
#endif
