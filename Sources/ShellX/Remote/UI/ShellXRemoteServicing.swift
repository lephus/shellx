import Combine
import Foundation
import ShellXBrand
import ShellXRemoteCore
import ShellXRemoteUI

/// What the remote sidebar UI needs from the remote service (the K4
/// contract of `ShellXRemoteService`, L5 Task 13). The DEBUG fixture and,
/// later, the real service conform; views only ever see this protocol.
@MainActor
protocol ShellXRemoteServicing: AnyObject {
    /// The account's other machines (never this Mac).
    var machines: [RemoteMachine] { get }
    var pendingApprovals: [PairingRequest] { get }
    var outgoing: [OutgoingPairing] { get }
    var hostState: LinkState { get }
    var isSignedIn: Bool { get }
    /// Workspace id → the remote machine it is attached to.
    var remoteWorkspaces: [UUID: RemoteMachine.ID] { get }
    /// Fires before any of the properties above changes.
    var changePublisher: AnyPublisher<Void, Never> { get }

    /// Returns the pairing code to show on this Mac.
    func requestAccess(to machineID: RemoteMachine.ID) async throws -> String
    func approve(_ id: PairingRequest.ID) async throws
    func deny(_ id: PairingRequest.ID) async
    func openSession(on machineID: RemoteMachine.ID) async throws
    /// Throws `ShellXCoreError` (`invalid_credentials`, `network`, …).
    func signIn(email: String, password: String) async throws
    func signOut() async
}

extension ShellXRemoteServicing where Self: ObservableObject, Self.ObjectWillChangePublisher == ObservableObjectPublisher {
    /// An `ObservableObject` service (the real one and the fixture) gets this for free.
    var changePublisher: AnyPublisher<Void, Never> {
        objectWillChange.eraseToAnyPublisher()
    }
}

/// The single switch for the remote sidebar UI. Off (the release default
/// while `ShellXFeatures.remoteMachines` is false), the sidebar renders
/// exactly as the local-only W1 sidebar.
enum ShellXRemoteUIGate {
    static let fixturesEnvironmentKey = "SHELLX_REMOTE_UI_FIXTURES"
    /// K4's switch, the one L5's `ShellXRemoteGate` reads.
    static let remoteMachinesEnvironmentKey = "SHELLX_REMOTE_MACHINES"

    static var isEnabled: Bool {
        ShellXFeatures.remoteMachines || usesFixtures || remoteMachinesRequested
    }

    /// DEBUG builds launched with `SHELLX_REMOTE_MACHINES=1`. Turns the UI on
    /// but serves no fixtures: until the real service is bound the provider
    /// returns nil and nothing remote shows.
    static var remoteMachinesRequested: Bool {
#if DEBUG
        return ProcessInfo.processInfo.environment[remoteMachinesEnvironmentKey] == "1"
#else
        return false
#endif
    }

    /// DEBUG builds launched with `SHELLX_REMOTE_UI_FIXTURES=1`.
    static var usesFixtures: Bool {
#if DEBUG
        return ProcessInfo.processInfo.environment[fixturesEnvironmentKey] == "1"
#else
        return false
#endif
    }
}

@MainActor
enum ShellXRemoteServiceProvider {
    /// The service the sidebar reads, or nil while the remote UI is off.
    static func makeService() -> (any ShellXRemoteServicing)? {
        guard ShellXRemoteUIGate.isEnabled else { return nil }
#if DEBUG
        if ShellXRemoteUIGate.usesFixtures {
            return ShellXRemoteFixtureService()
        }
#endif
        // ShellX: bind ShellXRemoteService.shared here when L5 Task 13 lands
        // ShellX: once it lands, ShellXRemoteUIGate.isEnabled must follow ShellXRemoteGate.
        return nil
    }
}

/// Publishes a fresh `RemoteUISnapshot` whenever the service changes. The
/// sidebar observes `shared`; with the gate off `snapshot` stays nil and
/// nothing is ever published.
@MainActor
final class ShellXRemoteUIModel: ObservableObject {
    static let shared = ShellXRemoteUIModel(service: ShellXRemoteServiceProvider.makeService())

    let service: (any ShellXRemoteServicing)?
    @Published private(set) var snapshot: RemoteUISnapshot?
    private var changeCancellable: AnyCancellable?

    init(service: (any ShellXRemoteServicing)?) {
        self.service = service
        if let service {
            snapshot = RemoteUISnapshot(service: service)
        } else {
            snapshot = nil
        }
        // `changePublisher` fires before the change lands; read on the next turn.
        changeCancellable = service?.changePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
    }

    /// The sidebar shows the sign-in row: remote UI on and signed out.
    var showsSignInRow: Bool {
        snapshot.map { !$0.isSignedIn } ?? false
    }

    func refresh() {
        guard let service else { return }
        let next = RemoteUISnapshot(service: service)
        if next != snapshot {
            snapshot = next
        }
    }
}
