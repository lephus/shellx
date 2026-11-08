import Foundation
import ShellXLinkCore
import ShellXLinkRelay
@testable import ShellXLinkSession
import XCTest

/// Shared rig for the terminal view and `terminal.create` tests (PROTOCOL.md section 11).
class TerminalSessionTestCase: XCTestCase {
    struct Rig {
        let host: LinkHost
        let hostKey: NoiseStaticKey
        let clientKey: NoiseStaticKey
    }

    private var serveTasks: [Task<Void, Never>] = []
    private var clients: [LinkClient] = []

    override func tearDown() async throws {
        for client in clients { await client.close() }
        for task in serveTasks {
            task.cancel()
            await task.value
        }
        serveTasks = []
        clients = []
    }

    func makeHost(
        terminalViews: (any TerminalViewSource)? = nil, terminalCreator: (any TerminalCreator)? = nil
    ) -> Rig {
        let hostKey = NoiseStaticKey()
        let clientKey = NoiseStaticKey()
        let trusted: Set<Data> = [clientKey.publicKey]
        let host = LinkHost(
            key: hostKey, trustedClients: { trusted }, feed: FakeFeedSource(), sessions: nil, chat: nil,
            terminalViews: terminalViews, terminalCreator: terminalCreator, hostVersion: "test-host", machineName: "Test Mac", timings: .standard)
        return Rig(host: host, hostKey: hostKey, clientKey: clientKey)
    }

    /// Serves one new circuit; returns the client end and a flag set when `serve` returns. `wrap` slows or watches the
    /// host's end.
    func startServe(
        _ rig: Rig, wrap: @escaping @Sendable (any RelayCircuit) -> any RelayCircuit = { $0 }
    ) -> (end: any RelayCircuit, served: Flag) {
        let (clientEnd, hostEnd) = makeInMemoryCircuitPair()
        let hostSide = wrap(hostEnd)
        let done = Flag()
        serveTasks.append(Task {
            await rig.host.serve(hostSide)
            done.set()
        })
        return (clientEnd, done)
    }

    func connect(
        _ rig: Rig, wrap: @escaping @Sendable (any RelayCircuit) -> any RelayCircuit = { $0 }
    ) async throws -> LinkClient {
        let (end, _) = startServe(rig, wrap: wrap)
        let client = try await LinkClient.connect(
            end, key: rig.clientKey, hostKey: rig.hostKey.publicKey, clientVersion: "test-client",
            deviceName: "Test Phone", timings: .standard)
        clients.append(client)
        return client
    }

    /// A raw secure channel after the handshake, `hello` sent and `welcome` read.
    func rawSession(_ rig: Rig) async throws -> SecureChannel {
        let (end, _) = startServe(rig)
        let hostPublic = rig.hostKey.publicKey
        let raw = try await SecureChannel.open(end, role: .initiator, key: rig.clientKey, trusts: { $0 == hostPublic })
        try await raw.send(.hello(clientVersion: "raw", deviceName: "raw"))
        let welcome = try await within { try await raw.receive() }
        guard case .welcome = welcome else {
            XCTFail("expected welcome, got \(welcome)")
            throw TimedOut()
        }
        return raw
    }

    /// The `features` of the `welcome` the host sends to a raw client.
    func welcomeFeatures(_ rig: Rig) async throws -> [String] {
        let (end, _) = startServe(rig)
        let hostPublic = rig.hostKey.publicKey
        let raw = try await SecureChannel.open(end, role: .initiator, key: rig.clientKey, trusts: { $0 == hostPublic })
        try await raw.send(.hello(clientVersion: "raw", deviceName: "raw"))
        let welcome = try await within { try await raw.receive() }
        guard case let .welcome(_, _, _, features) = welcome else {
            XCTFail("expected welcome, got \(welcome)")
            return []
        }
        return features
    }

    /// Asserts that `operation` fails with the host's `error` `code`.
    func expectRemote<T: Sendable>(
        _ code: String, file: StaticString = #filePath, line: UInt = #line,
        _ operation: @escaping @Sendable () async throws -> T
    ) async {
        do {
            _ = try await within { try await operation() }
            XCTFail("expected error \(code), got an answer", file: file, line: line)
        } catch {
            guard case let .remote(got, _)? = error as? LinkClientError else {
                return XCTFail("unexpected error \(error)", file: file, line: line)
            }
            XCTAssertEqual(got, code, file: file, line: line)
        }
    }

    /// `XCTAssertEqual` for an expression that awaits (XCTest's autoclosure cannot).
    func assertEqual<T: Equatable>(
        _ actual: @autoclosure () async throws -> T, _ expected: @autoclosure () -> T, _ message: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            let value = try await actual()
            XCTAssertEqual(value, expected(), message, file: file, line: line)
        } catch {
            XCTFail("threw \(error) \(message)", file: file, line: line)
        }
    }
}

// MARK: - Terminal push helpers

/// The frames after the last `.opened(terminalId)` (all of them when there is none), put through a fresh assembler and
/// screen: the screen the phone would show, the kinds and revisions of the frames it applied, and its resyncs.
func assembled(
    _ pushes: [TerminalViewPush], terminalId: String = "t-1"
) -> (screen: TerminalScreen, kinds: [TerminalFrameKind], revisions: [Int], resyncs: Int) {
    let start = pushes.lastIndex { $0 == .opened(terminalId: terminalId) }.map { $0 + 1 } ?? 0
    var assembler = TerminalFrameAssembler()
    var screen = TerminalScreen()
    var kinds: [TerminalFrameKind] = []
    var revisions: [Int] = []
    var resyncs = 0
    for push in pushes[start...] {
        guard case let .frame(id, part) = push, id == terminalId else { continue }
        let result = assembler.receive(part)
        if let frame = result.frame {
            screen.apply(frame)
            kinds.append(frame.head.kind)
            revisions.append(assembler.revision)
        }
        if result.resync { resyncs += 1 }
    }
    return (screen, kinds, revisions, resyncs)
}

func assembledText(_ pushes: [TerminalViewPush]) -> [String] {
    assembled(pushes).screen.screenText()
}

/// Polls until `condition` holds for the pushes collected so far, or `within` has passed.
func waitFor(
    _ pushes: Collector<TerminalViewPush>, within timeout: Duration = .seconds(5),
    _ condition: @escaping @Sendable ([TerminalViewPush]) -> Bool
) async -> Bool {
    await eventually(within: timeout) { condition(pushes.items) }
}
