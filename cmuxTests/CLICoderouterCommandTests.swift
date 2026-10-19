import XCTest
import Darwin
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct AgentAliasArgumentTests {
    final class BundleProbe {}

    @Test(arguments: ["claude", "codex", "opencode", "pi"], ["--help", "-h"])
    func helpKeepsTheProviderArgumentBoundary(agent: String, help: String) {
        #expect(CmuxTuiRemoteRouting.vmAgentAliasArgs([agent, help]) == ["--agent", agent, help])
        #expect(CmuxTuiRemoteRouting.vmAgentAliasArgs([agent, "--", help]) == ["--agent", agent, "--", help])
        #expect(CmuxTuiRemoteRouting.vmAgentAliasArgs([agent, "prompt", help]) == ["--agent", agent, "--", "prompt", help])
        #expect(CmuxTuiRemoteRouting.vmAgentRequestsHelp([agent, help]))
        #expect(!CmuxTuiRemoteRouting.vmAgentRequestsHelp([agent, "--", help]))
        #expect(!CmuxTuiRemoteRouting.vmAgentRequestsHelp([agent, "prompt", help]))
        #expect(!CmuxTuiRemoteRouting.vmAgentRequestsHelp([agent, "--name", help]))
        #expect(!CmuxTuiRemoteRouting.vmAgentRequestsHelp([agent, "--machine", "--", help]))
    }

    @Test func agentSubcommandMatchingIgnoresCase() {
        #expect(CmuxTuiRemoteRouting.isAgentSubcommand("agent"))
        #expect(CmuxTuiRemoteRouting.isAgentSubcommand("Agent"))
        #expect(CmuxTuiRemoteRouting.isAgentSubcommand("AGENT"))
        #expect(!CmuxTuiRemoteRouting.isAgentSubcommand("agents"))
    }

    @Test(arguments: ["open", "project"], ["--left", "--right", "--up", "--down"])
    func surfaceOpenRejectsTabAndSideBeforeMutation(subcommand: String, side: String) throws {
        let result = try runWithoutMutationRequests(["surface", subcommand, "vm/terminal/test", "--pane", "pane:1", "--tab", side])
        #expect(result.status != 0, "\(result.text)")
        #expect(result.text.contains("--tab and a pane side"), "\(result.text)")
    }

    /// ShellX: `cmux agent <provider>` would start an agent on a Cloud machine
    /// (`vm agent`), so it is refused before any request (Cloud is off).
    @Test
    func topLevelAgentAliasIsRefusedInShellX() throws {
        let result = try runWithoutMutationRequests(["agent", "claude", "--size", "1", "reply pong"])
        #expect(result.status == 127, "\(result.text)")
        #expect(result.text.contains("ShellX"), "\(result.text)")
        #expect(!result.text.contains("vm agent: unknown size"), "\(result.text)")
    }

    @Test(arguments: ["--help", "-h"])
    func topLevelAgentHelpDoesNotConnect(help: String) throws {
        for command in [["agent", help], ["agent", "claude", help], ["agent", "--agent", "claude", help]] {
            let result = try runWithoutMutationRequests(command)
            #expect(result.status == 0, "\(result.text)")
            #expect(result.text.contains("Usage:") && result.text.contains("cmux agent"), "\(result.text)")
            #expect(!result.connected, "Help unexpectedly connected to the app socket")
        }
    }

    private func runWithoutMutationRequests(_ arguments: [String]) throws -> (status: Int32, text: String, connected: Bool) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cmux-agent-help-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = try BundledCLITestSupport.bundledCLIURL(for: BundleProbe.self)
        let socketPath = "/tmp/cmux-args-\(UUID().uuidString).sock"
        let listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(listener >= 0)
        defer { Darwin.close(listener); unlink(socketPath) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            bytes.copyBytes(from: socketPath.utf8CString.map { UInt8(bitPattern: $0) })
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        try #require(bound == 0)
        try #require(Darwin.listen(listener, 1) == 0)
        try #require(fcntl(listener, F_SETFL, O_NONBLOCK) == 0)
        do {
            let output = directory.appendingPathComponent("output")
            try Data().write(to: output)
            let handle = try FileHandle(forWritingTo: output)
            defer { try? handle.close() }
            let process = Process()
            process.executableURL = binary
            process.arguments = ["--socket", socketPath] + arguments
            var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("CMUX_") }
            environment["HOME"] = directory.path
            environment["CMUX_CLI_SENTRY_DISABLED"] = "1"
            process.environment = environment
            process.standardOutput = handle
            process.standardError = handle
            let ended = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in ended.signal() }
            try process.run()
            let finished = ended.wait(timeout: .now() + 10) == .success
            if !finished { Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            let text = try String(contentsOf: output, encoding: .utf8)
            #expect(finished, "\(arguments): \(text)")
            let connection = Darwin.accept(listener, nil, nil)
            if connection >= 0 {
                defer { Darwin.close(connection) }
                var buffer = [UInt8](repeating: 0, count: 4096)
                let received = buffer.withUnsafeMutableBytes { bytes in
                    Darwin.recv(connection, bytes.baseAddress, bytes.count, MSG_DONTWAIT)
                }
                #expect(received == 0, "Unexpected socket request: \(String(decoding: buffer.prefix(max(received, 0)), as: UTF8.self))")
            }
            return (process.terminationStatus, text, connection >= 0)
        }
    }

    @Test(arguments: ["claude", "codex", "opencode", "pi"], ["--machine", "--size", "--cwd", "--name", "--remote-workspace", "--timeout"])
    func incompleteVMOptionRemainsAnOption(agent: String, option: String) {
        #expect(CmuxTuiRemoteRouting.vmAgentAliasArgs([agent, option]) == ["--agent", agent, option])
        #expect(CmuxTuiRemoteRouting.vmAgentAliasArgs([agent, "--no-open", option]) == ["--agent", agent, "--no-open", option])
        #expect(CmuxTuiRemoteRouting.vmAgentAliasArgs([agent, "--", option]) == ["--agent", agent, "--", option])
        #expect(CmuxTuiRemoteRouting.vmAgentAliasArgs([agent, "prompt", option]) == ["--agent", agent, "--", "prompt", option])
    }

    /// The until-done flags belong to `cmux vm agent`, not to the agent: the
    /// short forms must keep them in front of `--`, and a `--timeout` value
    /// must not hide a later `--help`.
    @Test(arguments: ["claude", "codex", "opencode", "pi"])
    func untilDoneOptionsStayVMOptions(agent: String) {
        #expect(
            CmuxTuiRemoteRouting.vmAgentAliasArgs([agent, "--wait", "--output", "--timeout", "30", "fix the tests"])
                == ["--agent", agent, "--wait", "--output", "--timeout", "30", "--", "fix the tests"]
        )
        #expect(
            CmuxTuiRemoteRouting.vmAgentAliasArgs([agent, "--timeout", "30", "--", "--wait"])
                == ["--agent", agent, "--timeout", "30", "--", "--wait"]
        )
        #expect(CmuxTuiRemoteRouting.vmAgentRequestsHelp([agent, "--timeout", "30", "--help"]))
        #expect(CmuxTuiRemoteRouting.vmAgentRequestsHelp([agent, "--wait", "-h"]))
    }

    /// `--focus` takes an optional value only when the next token is exactly a
    /// boolean word, so a prompt after a bare `--focus` stays the prompt.
    @Test(arguments: ["claude", "codex", "opencode", "pi"])
    func focusFlagsStayVMOptions(agent: String) {
        #expect(
            CmuxTuiRemoteRouting.vmAgentAliasArgs([agent, "--focus", "true", "fix it"])
                == ["--agent", agent, "--focus", "true", "--", "fix it"]
        )
        #expect(
            CmuxTuiRemoteRouting.vmAgentAliasArgs([agent, "--focus", "fix it"])
                == ["--agent", agent, "--focus", "--", "fix it"]
        )
        #expect(
            CmuxTuiRemoteRouting.vmAgentAliasArgs([agent, "--focus=no", "--no-focus", "fix it"])
                == ["--agent", agent, "--focus=no", "--no-focus", "--", "fix it"]
        )
    }

    @Test func focusFlagValueAcceptsOnlyBooleanWords() {
        for token in ["true", "TRUE", "1", "yes"] { #expect(CmuxTuiRemoteRouting.focusFlagValue(token) == true) }
        for token in ["false", "0", "No"] { #expect(CmuxTuiRemoteRouting.focusFlagValue(token) == false) }
        for token in ["", "fix", "truely", "on"] { #expect(CmuxTuiRemoteRouting.focusFlagValue(token) == nil) }
    }
}

// ShellX refuses every `cmux coderouter` verb (exit 127, "CodeRouter is not
// available in ShellX.") before it connects: the owned verbs
// (`status|machines|claude|agent`) drove Manaflow's `coderouter.*` service and
// the rest would exec the CodeRouter CLI. Upstream's per-verb wire tests are
// gone; ShellXCloudOffTests covers the owned verbs.
extension CLINotifyProcessIntegrationRegressionTests {
    private static let sampleOAuthToken = "sk-ant-oat01-abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJ"
    private static let accountA = "11111111-2222-4333-8444-555555555555"
    private static let accountB = "66666666-7777-4888-9999-000000000000"

    private static func account(
        id: String,
        kind: String,
        identifier: String,
        label: String = "",
        state: String = "active",
        cooldownUntil: Any = NSNull(),
        lastFailureCode: Any = NSNull()
    ) -> [String: Any] {
        [
            "id": id,
            "kind": kind,
            "label": label,
            "identifier": identifier,
            "region": NSNull(),
            "modelIds": [String: Any](),
            "state": state,
            "cooldownUntil": cooldownUntil,
            "lastFailureCode": lastFailureCode,
            "lastUsedAt": NSNull(),
            "createdAt": "2026-09-02T10:00:00.000Z",
            "updatedAt": "2026-09-02T10:00:00.000Z",
        ]
    }

    private static func listPayload(_ accounts: [[String: Any]]) -> [String: Any] {
        ["teamId": "team_local", "accounts": accounts, "upstream": accounts.first ?? NSNull()]
    }

    private func runCoderouterCLI(
        _ arguments: [String],
        socketName: String,
        standardInput: String? = nil,
        extraEnvironment: [String: String] = [:],
        underTerminal: Bool = false,
        waitForSocket: Bool = true,
        handler: @escaping (String, [String: Any]) -> String?
    ) throws -> (result: ProcessRunResult, state: MockSocketServerState) {
        let cliPath = try bundledCLIPath()
        let socketPath = makeSocketPath(socketName)
        let listenerFD = try bindUnixSocket(at: socketPath)
        let state = MockSocketServerState()

        defer {
            Darwin.close(listenerFD)
            unlink(socketPath)
        }

        let serverHandler: @Sendable (String) -> String = { [self] line in
            guard let payload = self.jsonObject(line),
                  let id = payload["id"] as? String,
                  let method = payload["method"] as? String else {
                return self.malformedRequestResponse(raw: line)
            }
            let params = (payload["params"] as? [String: Any]) ?? [:]
            if let result = handler(method, params) {
                return result.replacingOccurrences(of: "__ID__", with: id)
            }
            return self.v2Response(
                id: id,
                ok: false,
                error: ["code": "unexpected", "message": "Unexpected method \(method)"]
            )
        }
        // A test that expects the CLI to stay off the socket must not hold a
        // case-bound expectation it never waits on: the detached accept loop
        // records any unexpected request without turning cleanup into a test
        // failure.
        let serverHandled: XCTestExpectation?
        if waitForSocket {
            serverHandled = startMockServer(
                listenerFD: listenerFD,
                state: state,
                handler: serverHandler
            )
        } else {
            startDetachedMockServer(
                listenerFD: listenerFD,
                state: state,
                handler: serverHandler
            )
            serverHandled = nil
        }

        var environment = ProcessInfo.processInfo.environment
        environment["CMUX_SOCKET_PATH"] = socketPath
        environment["CMUX_CLI_SENTRY_DISABLED"] = "1"
        environment.removeValue(forKey: "CLAUDE_CODE_OAUTH_TOKEN")
        environment.removeValue(forKey: "ANTHROPIC_API_KEY")
        for (key, value) in extraEnvironment {
            environment[key] = value
        }

        // `underTerminal` runs the CLI on a pseudo-terminal, the only way to reach
        // its interactive prompts. `script` turns a closed stdin into an EOF that
        // can overtake typed input, so the shell keeps the pipe open until the
        // CLI exits and `standardInput` is typed through it.
        let doneSignal = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-coderouter-terminal-\(UUID().uuidString)").path
        defer { unlink(doneSignal) }
        if underTerminal {
            environment["CMUX_TEST_TERMINAL_INPUT"] = standardInput ?? ""
        }
        let result = runProcess(
            executablePath: underTerminal ? "/bin/sh" : cliPath,
            arguments: underTerminal ? ["-c", Self.terminalRunner, "sh", doneSignal, cliPath] + arguments : arguments,
            environment: environment,
            standardInput: underTerminal ? nil : standardInput,
            timeout: 5
        )
        if let serverHandled {
            wait(for: [serverHandled], timeout: 5)
        }
        return (result, state)
    }

    /// `sh -c` body: `$1` is a path for the done signal, the rest is the command.
    private static let terminalRunner = #"""
        done="$1"; shift
        mkfifo "$done" || exit 125
        { printf '%s' "$CMUX_TEST_TERMINAL_INPUT"; read _ < "$done"; } |
            { /usr/bin/script -q /dev/null "$@"; status=$?; echo > "$done"; exit "$status"; }
        """#

    /// The mock responds with `__ID__` so the handler closure does not need the
    /// request id; `runCoderouterCLI` substitutes it.
    private func okResponse(_ result: [String: Any]) -> String {
        v2Response(id: "__ID__", ok: true, result: result)
    }

    private static let loggedInClaudeJSON = #"{"oauthAccount":{"emailAddress":"dev@example.com","organizationName":"Example"}}"#

    func testProviderFirstAgentAliasAddsTheCanonicalSeparator() {
        XCTAssertEqual(
            CmuxTuiRemoteRouting.vmAgentAliasArgs(["claude", "--machine", "vm-agent-test", "reply exactly pong"]),
            ["--agent", "claude", "--machine", "vm-agent-test", "--", "reply exactly pong"]
        )
        XCTAssertEqual(
            CmuxTuiRemoteRouting.vmAgentAliasArgs(["codex", "--", "exec", "summarize"]),
            ["--agent", "codex", "--", "exec", "summarize"]
        )
        // Focus flags belong to `vm agent`, not to the agent's prompt.
        XCTAssertEqual(
            CmuxTuiRemoteRouting.vmAgentAliasArgs(["claude", "--no-focus", "reply exactly pong"]),
            ["--agent", "claude", "--no-focus", "--", "reply exactly pong"]
        )
    }

    func testCoderouterUnknownVerbIsRefusedWithoutTheSocket() throws {
        // A verb cmux does not own goes to the CodeRouter passthrough, which
        // ShellX refuses before looking for an executable; the socket is never
        // consulted for a non-cmux verb.
        let emptyPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-empty-path-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyPath) }

        let (result, state) = try runCoderouterCLI(
            ["coderouter", "accounts"],
            socketName: "coderouter-passthrough",
            extraEnvironment: [
                "PATH": emptyPath.path,
                "HOME": emptyPath.path,
                "CFFIXED_USER_HOME": emptyPath.path,
                "AppleLanguages": "(en)",
            ],
            waitForSocket: false
        ) { _, _ in nil }

        XCTAssertEqual(result.status, 127, result.stderr)
        XCTAssertTrue(result.stderr.contains("CodeRouter is not available in ShellX."), result.stderr)
        XCTAssertTrue(state.commands.isEmpty, "passthrough verbs must not touch the cmux socket: \(state.commands)")
    }
}
