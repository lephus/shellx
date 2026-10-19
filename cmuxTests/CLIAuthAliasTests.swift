import CmuxControlSocket
import Darwin
import Foundation
import Testing
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Minimal authenticated-socket stand-in for routed alias tests. The real app
/// performs the same request over its local control socket. Keeping this test
/// server here lets the child-launch tests exercise the one-use arm step
/// without starting the full AppKit host.
private enum CLICoderouterMockResponseMutation: Sendable, Equatable {
    case none
    case tamperProof
    case addEnvelopeKey
    case addPayloadKey
    case unsignedError
    case missingNewline
    case oversizedFrame
    case secondFrame
    case trailingWhitespace
}

private final class CLICoderouterMockHandoffServer: @unchecked Sendable {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var commands: [String] = []
        let handled = DispatchSemaphore(value: 0)
    }

    let path: String
    let teamBinding: String
    let capability: String
    private let listenerFD: Int32
    private let state: State
    private let lifecycleLock = NSLock()
    private var stopped = false

    init(
        name: String,
        teamBinding: String = String(repeating: "a", count: 64),
        errorCode: String? = nil,
        responseID: String = "coderouter-handoff-arm",
        responseMutation: CLICoderouterMockResponseMutation = .none
    ) throws {
        let shortID = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        let path = "/tmp/cli-\(name.prefix(8))-\(shortID).sock"
        let listenerFD = try Self.bindUnixSocket(at: path)
        self.path = path
        self.teamBinding = teamBinding
        let capabilityNonce = Data(repeating: 0x41, count: 32)
        let capabilityTag = Data(repeating: 0x42, count: 32)
        guard let capabilityNonceText = SocketClientCapabilityProof()
            .encodeBase64URL32(capabilityNonce),
              let capabilityTagText = SocketClientCapabilityProof()
                  .encodeBase64URL32(capabilityTag) else {
            throw NSError(domain: "cmux.tests", code: 1)
        }
        self.capability = "v1.\(capabilityNonceText).\(capabilityTagText)"
        self.listenerFD = listenerFD
        self.state = State()

        let state = self.state
        let capability = self.capability
        CLIMockAcceptLoopRegistry.shared.start(
            listenerFD: listenerFD,
            onConnection: { clientFD in
                defer {
                    Darwin.close(clientFD)
                    state.handled.signal()
                }
                guard let line = Self.readSingleRequest(from: clientFD) else {
                    return
                }
                state.lock.lock()
                state.commands.append(line)
                state.lock.unlock()
                let response = Self.response(
                    for: line,
                    capability: capability,
                    teamBinding: teamBinding,
                    errorCode: errorCode,
                    responseID: responseID,
                    responseMutation: responseMutation
                )
                _ = cliMockWriteAll(
                    Self.responseFrame(
                        response,
                        mutation: responseMutation
                    ),
                    to: clientFD
                )
            },
            onListenerClosed: {
                state.handled.signal()
            }
        )
    }

    func waitForRequest(timeout: TimeInterval = 5) -> Bool {
        state.handled.wait(timeout: .now() + timeout) == .success
    }

    func commandSnapshot() -> [String] {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.commands
    }

    func stop() {
        lifecycleLock.lock()
        guard !stopped else {
            lifecycleLock.unlock()
            return
        }
        stopped = true
        lifecycleLock.unlock()
        CLIMockAcceptLoopRegistry.shared.stop(listenerFD: listenerFD)
        Darwin.close(listenerFD)
        unlink(path)
    }

    deinit { stop() }

    var capabilityEnvironment: [String: String] {
        ["CMUX_SOCKET_CAPABILITY": capability]
    }

    private static func readSingleRequest(from fileDescriptor: Int32) -> String? {
        var data = Data()
        while data.count <= 4_096 {
            var byte: UInt8 = 0
            let count = Darwin.read(fileDescriptor, &byte, 1)
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if count == 0 { return nil }
            data.append(byte)
            if byte == 0x0A {
                guard data.count <= 4_096 else { return nil }
                return String(data: Data(data.dropLast()), encoding: .utf8)
            }
        }
        return nil
    }

    private static func responseFrame(
        _ response: String,
        mutation: CLICoderouterMockResponseMutation
    ) -> String {
        switch mutation {
        case .missingNewline:
            response
        case .oversizedFrame:
            String(repeating: "x", count: 4_096) + "\n"
        case .secondFrame:
            response + "\n" + response + "\n"
        case .trailingWhitespace:
            response + "\n "
        default:
            response + "\n"
        }
    }

    private static func response(
        for requestLine: String,
        capability: String,
        teamBinding: String,
        errorCode: String?,
        responseID: String,
        responseMutation: CLICoderouterMockResponseMutation
    ) -> String {
        guard let data = requestLine.data(using: .utf8),
              let request = try? JSONSerialization.jsonObject(with: data)
                  as? [String: Any],
              request["id"] as? String
                  == SocketClientCapabilityProof.requestID,
              request["method"] as? String
                  == SocketClientCapabilityProof.method,
              let params = request["params"] as? [String: Any],
              let nonceText = params["capabilityNonce"] as? String,
              let nonce = SocketClientCapabilityProof().decodeBase64URL32(
                  nonceText
              ),
              let challengeText = params["clientChallenge"] as? String,
              let challenge = SocketClientCapabilityProof().decodeBase64URL32(
                  challengeText
              ),
              let processIDNumber = params["clientProcessID"] as? NSNumber,
              let processStartText = params[
                  "clientProcessStartAbsoluteTime"
              ] as? String,
              let processStart = SocketClientCapabilityProof()
                  .decodeProcessStartTime(processStartText),
              let clientProof = params["clientProof"] as? String,
              SocketClientCapabilityProof().verifiesClientProof(
                  clientProof,
                  capability: capability,
                  nonce: nonce,
                  challenge: challenge,
                  processID: pid_t(processIDNumber.int32Value),
                  processStartAbsoluteTime: processStart
              ) else {
            return #"{"id":"\#(responseID)","ok":false,"error":{"code":"invalid_proof","message":"invalid"}}"#
        }
        if let errorCode {
            let generatedProof = SocketClientCapabilityProof().serverErrorProof(
                capability: capability,
                nonce: nonce,
                challenge: challenge,
                processID: pid_t(processIDNumber.int32Value),
                processStartAbsoluteTime: processStart,
                code: errorCode
            ) ?? String(repeating: "0", count: 64)
            let serverProof = responseMutation == .tamperProof
                ? String(repeating: "f", count: 64)
                : generatedProof
            if responseMutation == .unsignedError {
                return #"{"id":"\#(responseID)","ok":false,"error":{"code":"\#(errorCode)","message":"raw-arm-secret-must-not-leak"}}"#
            }
            let payloadExtra = responseMutation == .addPayloadKey
                ? #","unexpected":true"#
                : ""
            let envelopeExtra = responseMutation == .addEnvelopeKey
                ? #","unexpected":true"#
                : ""
            return #"{"id":"\#(responseID)","ok":false,"error":{"code":"\#(errorCode)","message":"raw-arm-secret-must-not-leak","data":{"serverProof":"\#(serverProof)"}\#(payloadExtra)}\#(envelopeExtra)}"#
        }
        let generatedProof = SocketClientCapabilityProof().serverProof(
            capability: capability,
            nonce: nonce,
            challenge: challenge,
            processID: pid_t(processIDNumber.int32Value),
            processStartAbsoluteTime: processStart,
            teamBinding: teamBinding
        ) ?? String(repeating: "0", count: 64)
        let serverProof = responseMutation == .tamperProof
            ? String(repeating: "f", count: 64)
            : generatedProof
        let payloadExtra = responseMutation == .addPayloadKey
            ? #", "unexpected":true"#
            : ""
        let envelopeExtra = responseMutation == .addEnvelopeKey
            ? #", "unexpected":true"#
            : ""
        return #"{"id":"\#(responseID)","ok":true,"result":{"armed":true,"protocolVersion":2,"teamBinding":"\#(teamBinding)","serverProof":"\#(serverProof)"\#(payloadExtra)}\#(envelopeExtra)}"#
    }

    private static func bindUnixSocket(at path: String) throws -> Int32 {
        unlink(path)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "cmux.tests", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "failed to create handoff socket",
            ])
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else {
            Darwin.close(fd)
            throw NSError(domain: "cmux.tests", code: Int(ENAMETOOLONG), userInfo: nil)
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { buffer in
                for (index, byte) in bytes.enumerated() {
                    buffer[index] = CChar(bitPattern: byte)
                }
                buffer[bytes.count] = 0
            }
        }
#if os(macOS)
        address.sun_len = UInt8(min(MemoryLayout<sockaddr_un>.size, 255))
#endif
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0, Darwin.listen(fd, 1) == 0 else {
            let bindError = errno
            Darwin.close(fd)
            throw NSError(domain: "cmux.tests", code: Int(bindError), userInfo: nil)
        }
        _ = chmod(path, 0o600)
        return fd
    }
}

extension CLINotifyProcessIntegrationRegressionTests {
    func testTopLevelLoginAliasesAuthLogin() throws {
        let cliPath = try bundledCLIPath()
        let socketPath = makeSocketPath("auth-login")
        let listenerFD = try bindUnixSocket(at: socketPath)
        let state = MockSocketServerState()

        defer {
            Darwin.close(listenerFD)
            unlink(socketPath)
        }

        let serverHandled = startMockServer(listenerFD: listenerFD, state: state) { line in
            guard let payload = self.jsonObject(line),
                  let id = payload["id"] as? String,
                  let method = payload["method"] as? String else {
                return self.malformedRequestResponse(raw: line)
            }

            switch method {
            case "auth.status":
                return self.v2Response(id: id, ok: true, result: ["signed_in": false])
            case "auth.begin_sign_in":
                return self.v2Response(
                    id: id,
                    ok: true,
                    result: [
                        "signed_in": true,
                        "user": ["email": "dev@example.com"],
                    ]
                )
            default:
                return self.v2Response(
                    id: id,
                    ok: false,
                    error: ["code": "unexpected", "message": "Unexpected method \(method)"]
                )
            }
        }

        var environment = ProcessInfo.processInfo.environment
        environment["CMUX_SOCKET_PATH"] = socketPath
        environment["CMUX_CLI_SENTRY_DISABLED"] = "1"

        let result = runProcess(
            executablePath: cliPath,
            arguments: ["login"],
            environment: environment,
            timeout: 5
        )

        wait(for: [serverHandled], timeout: 5)
        XCTAssertFalse(result.timedOut, result.stderr)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(result.stdout, "Opening sign-in popup on the cmux web app.\nSigned in as dev@example.com.\n")
        XCTAssertTrue(
            state.commands.contains { $0.contains(#""method":"auth.begin_sign_in""#) },
            "Expected login alias to call auth.begin_sign_in, saw \(state.commands)"
        )
    }

    func testTopLevelLogoutAliasesAuthLogout() throws {
        let cliPath = try bundledCLIPath()
        let socketPath = makeSocketPath("auth-logout")
        let listenerFD = try bindUnixSocket(at: socketPath)
        let state = MockSocketServerState()

        defer {
            Darwin.close(listenerFD)
            unlink(socketPath)
        }

        let serverHandled = startMockServer(listenerFD: listenerFD, state: state) { line in
            guard let payload = self.jsonObject(line),
                  let id = payload["id"] as? String,
                  let method = payload["method"] as? String else {
                return self.malformedRequestResponse(raw: line)
            }

            switch method {
            case "auth.status":
                return self.v2Response(
                    id: id,
                    ok: true,
                    result: [
                        "signed_in": true,
                        "user": ["email": "dev@example.com"],
                    ]
                )
            case "auth.sign_out":
                return self.v2Response(id: id, ok: true, result: ["signed_in": false])
            default:
                return self.v2Response(
                    id: id,
                    ok: false,
                    error: ["code": "unexpected", "message": "Unexpected method \(method)"]
                )
            }
        }

        var environment = ProcessInfo.processInfo.environment
        environment["CMUX_SOCKET_PATH"] = socketPath
        environment["CMUX_CLI_SENTRY_DISABLED"] = "1"

        let result = runProcess(
            executablePath: cliPath,
            arguments: ["logout"],
            environment: environment,
            timeout: 5
        )

        wait(for: [serverHandled], timeout: 5)
        XCTAssertFalse(result.timedOut, result.stderr)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(result.stdout, "Signed out.\n")
        XCTAssertTrue(
            state.commands.contains { $0.contains(#""method":"auth.sign_out""#) },
            "Expected logout alias to call auth.sign_out, saw \(state.commands)"
        )
    }

}

@Suite("CodeRouter CLI aliases")
struct CLICoderouterAliasTests {
    private let protocolCodec = CodeRouterHandoffProtocol()
    private let launchPolicy = CodeRouterLaunchPolicy()
    private let debugIdentityPolicy = CodeRouterDebugServerIdentityPolicy()

    private struct ProcessResult {
        let status: Int32
        let stdout: String
        let stderr: String
        let timedOut: Bool
    }

    #if DEBUG
    @Test("allows only the matching company-signed tagged Debug server")
    func validatesTaggedDebugServerSigningFields() {
        let bundleIdentifier = "pro.shellx.desktop.debug.coderouter-dogfood"
        #expect(
            debugIdentityPolicy.isAllowed(
                identifier: bundleIdentifier,
                teamIdentifier: "W4RF3W4VTZ",
                expectedBundleIdentifier: bundleIdentifier
            )
        )
        #expect(
            !debugIdentityPolicy.isAllowed(
                identifier: bundleIdentifier,
                teamIdentifier: "WRONGTEAM",
                expectedBundleIdentifier: bundleIdentifier
            )
        )
        #expect(
            !debugIdentityPolicy.isAllowed(
                identifier: "pro.shellx.desktop.debug.other",
                teamIdentifier: "W4RF3W4VTZ",
                expectedBundleIdentifier: bundleIdentifier
            )
        )
        #expect(
            !debugIdentityPolicy.isAllowed(
                identifier: "pro.shellx.desktop",
                teamIdentifier: "W4RF3W4VTZ",
                expectedBundleIdentifier: "pro.shellx.desktop"
            )
        )
    }
    #endif

    @Test("validates the exact Darwin handoff socket path limit")
    func validatesHandoffSocketPathLimit() {
        let pathWith103Bytes = "/" + String(repeating: "a", count: 102)
        let pathWith104Bytes = "/" + String(repeating: "a", count: 103)
        #expect(pathWith103Bytes.utf8.count == 103)
        #expect(pathWith104Bytes.utf8.count == 104)
        #expect(protocolCodec.socketPathIsValid(pathWith103Bytes))
        #expect(!protocolCodec.socketPathIsValid(pathWith104Bytes))
        #expect(!protocolCodec.socketPathIsValid("relative.sock"))
        #expect(!protocolCodec.socketPathIsValid("/tmp/cmux\n.sock"))
        #expect(!protocolCodec.socketPathIsValid("/tmp/cmux\u{200B}.sock"))
        #expect(protocolCodec.socketPathIsValid("/tmp/cmux\u{E0101}.sock"))
    }

    @Test("validates the exact raw arm response schema")
    func validatesExactRawArmResponseSchema() {
        let binding = String(repeating: "a", count: 64)
        let proof = String(repeating: "b", count: 64)
        let validSuccess = #"{"id":"coderouter-handoff-arm","ok":true,"result":{"armed":true,"protocolVersion":2,"teamBinding":"\#(binding)","serverProof":"\#(proof)"}}"#
        let validError = #"{"id":"coderouter-handoff-arm","ok":false,"error":{"code":"team_required","message":"ignored","data":{"serverProof":"\#(proof)"}}}"#
        #expect(protocolCodec.responseRawShapeIsValid(validSuccess))
        #expect(protocolCodec.responseRawShapeIsValid(validError))
        #expect(!protocolCodec.responseRawShapeIsValid(" \(validSuccess)"))
        #expect(!protocolCodec.responseRawShapeIsValid("\(validError)\u{00a0}"))

        let numericOK = validSuccess.replacingOccurrences(
            of: #""ok":true"#,
            with: #""ok":1"#
        )
        let numericArmed = validSuccess.replacingOccurrences(
            of: #""armed":true"#,
            with: #""armed":1"#
        )
        let floatVersion = validSuccess.replacingOccurrences(
            of: #""protocolVersion":2"#,
            with: #""protocolVersion":2.0"#
        )
        let exponentVersion = validSuccess.replacingOccurrences(
            of: #""protocolVersion":2"#,
            with: #""protocolVersion":2e0"#
        )
        let duplicateResultKey = validSuccess.replacingOccurrences(
            of: #""armed":true"#,
            with: #""armed":true,"armed":true"#
        )
        let escapedDuplicateResultKey = validSuccess.replacingOccurrences(
            of: #""armed":true"#,
            with: #""\u0061rmed":false,"armed":true"#
        )
        let duplicateTopLevelKey = validSuccess.replacingOccurrences(
            of: #""ok":true"#,
            with: #""ok":true,"ok":true"#
        )
        let unknownResultKey = validSuccess.replacingOccurrences(
            of: #""armed":true"#,
            with: #""armed":true,"unexpected":true"#
        )
        let duplicateErrorKey = validError.replacingOccurrences(
            of: #""code":"team_required""#,
            with: #""code":"team_required","code":"team_required""#
        )
        let unknownDataKey = validError.replacingOccurrences(
            of: #""serverProof":"\#(proof)""#,
            with: #""serverProof":"\#(proof)","unexpected":true"#
        )

        #expect(!protocolCodec.responseRawShapeIsValid(numericOK))
        #expect(!protocolCodec.responseRawShapeIsValid(numericArmed))
        #expect(!protocolCodec.responseRawShapeIsValid(floatVersion))
        #expect(!protocolCodec.responseRawShapeIsValid(exponentVersion))
        #expect(!protocolCodec.responseRawShapeIsValid(duplicateTopLevelKey))
        #expect(!protocolCodec.responseRawShapeIsValid(duplicateResultKey))
        #expect(!protocolCodec.responseRawShapeIsValid(escapedDuplicateResultKey))
        #expect(!protocolCodec.responseRawShapeIsValid(unknownResultKey))
        #expect(!protocolCodec.responseRawShapeIsValid(duplicateErrorKey))
        #expect(!protocolCodec.responseRawShapeIsValid(unknownDataKey))
    }

    /// ShellX never runs CodeRouter (a Manaflow service): `cmux cr` and every
    /// passthrough `cmux coderouter` verb, management or routed, stop with exit
    /// 127 before any CodeRouter on PATH runs, before a capability probe, and
    /// before a handoff is armed on the socket. This replaces upstream's exec,
    /// descriptor, signal, capability-probe and arm tests, which needed a
    /// CodeRouter to run (CLICoderouterBootstrapTests covers the install
    /// locations).
    @Test("ShellX refuses every CodeRouter alias before exec, probe, or arm")
    func everyAliasIsRefusedBeforeExecProbeOrArm() throws {
        let cliPath = try BundledCLITestSupport.bundledCLIPath(
            for: BundledCLILinkageTests.self
        )
        let handoffServer = try CLICoderouterMockHandoffServer(name: "refused")
        defer { handoffServer.stop() }
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("cmux-coderouter-refused-\(UUID().uuidString)", isDirectory: true)
        let markerURL = root.appendingPathComponent("coderouter-ran.txt", isDirectory: false)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["coderouter", "cr"] {
            try writeExecutable(
                """
                #!/bin/sh
                printf '%s:%s\\n' "$0" "$*" >> "$CODEROUTER_MARKER_FILE"
                if [ "${1-}" = "capabilities" ]; then
                  printf '%s\\n' '{"product":"coderouter","protocolVersion":2,"authModes":["cmux-socket-v1"]}'
                  exit 0
                fi
                printf 'must-not-run\\n'
                exit 41
                """,
                at: root.appendingPathComponent(name, isDirectory: false)
            )
        }

        let cases: [[String]] = [
            ["cr", "--version"],
            ["coderouter", "--version"],
            ["coderouter", "capabilities", "--json"],
            ["cr", "login", "--device-auth"],
            ["coderouter", "launch"],
            ["coderouter", "codex"],
            ["cr", "pi"],
        ]
        for arguments in cases {
            let result = runCLI(
                cliPath: cliPath,
                arguments: arguments,
                environment: [
                    "PATH": root.path,
                    "CODEROUTER_MARKER_FILE": markerURL.path,
                    "CMUX_SOCKET_PATH": handoffServer.path,
                    "CMUX_CLI_SENTRY_DISABLED": "1",
                ]
            )
            let label = Comment(rawValue: "\(arguments): \(result.stderr)")
            #expect(!result.timedOut, label)
            #expect(result.status == 127, label)
            #expect(result.stdout.isEmpty, label)
            #expect(result.stderr.contains("CodeRouter is not available in ShellX."), label)
            #expect(!result.stderr.contains(root.path), label)
        }
        #expect(!fileManager.fileExists(atPath: markerURL.path), "No CodeRouter executable may run")
        #expect(!handoffServer.waitForRequest(timeout: 0.2), "No alias may arm a handoff")
    }

    @Test("only exact top-level agent names use socket handoff")
    func routedCommandClassificationIsExact() {
        #expect(launchPolicy.commandRequiresHandoff(["codex"]))
        #expect(!launchPolicy.commandRequiresHandoff(["add", "codex"]))
        #expect(launchPolicy.commandRequiresHandoff(["opencode", "--help"]))
        #expect(launchPolicy.commandRequiresHandoff(["pi", "arg"]))
        #expect(!launchPolicy.commandRequiresHandoff([]))
        #expect(!launchPolicy.commandRequiresHandoff(["login"]))
        #expect(!launchPolicy.commandRequiresHandoff(["capabilities", "--json"]))
        #expect(!launchPolicy.commandRequiresHandoff(["codex-helper"]))
        #expect(!launchPolicy.commandRequiresHandoff(["Codex"]))
        #expect(!launchPolicy.commandRequiresHandoff(["--", "codex"]))
    }

    @Test("localizes the alias help entry")
    func aliasHelpUsesRequestedLocalization() throws {
        let cliPath = try BundledCLITestSupport.bundledCLIPath(
            for: BundledCLILinkageTests.self
        )
        let result = runCLI(
            cliPath: cliPath,
            arguments: ["--help"],
            environment: [
                "AppleLanguages": "(ja)",
                "AppleLocale": "ja_JP",
            ]
        )

        #expect(!result.timedOut, Comment(rawValue: result.stderr))
        #expect(result.status == 0, Comment(rawValue: result.stderr))
        #expect(
            result.stdout.contains("CodeRouter CLI のエイリアス。未インストール時はインストールを提案"),
            Comment(rawValue: result.stdout)
        )
        #expect(
            !result.stdout.contains("aliases for the CodeRouter CLI"),
            Comment(rawValue: result.stdout)
        )
    }

    @Test("the launch policy keeps cmux control values out of a child environment")
    func childEnvironmentExcludesCmuxControlValues() {
        let routedEnvironment = launchPolicy.childEnvironment(
            [
                "PATH": "/usr/bin",
                "CODEROUTER_API_URL": "https://must-not-cross.example",
                "CODEROUTER_DATA_DIR": "/tmp/must-not-cross",
                "CODEROUTER_HANDOFF_FD": "3",
                "CODEROUTER_CMUX_HANDOFF_SOCKET": "/tmp/stale.sock",
                "AWS_REGION": "us-west-2",
                "AWS_PROFILE": "dev-profile",
                "GOOGLE_CLOUD_PROJECT": "project-config",
                "SSH_AUTH_SOCK": "/tmp/ssh-agent.sock",
                "HTTP_PROXY": "http://proxy-secret.example",
                "HTTPS_PROXY": "https://proxy-secret.example",
                "https_proxy": "https://lowercase-proxy-secret.example",
                "ALL_PROXY": "socks5://proxy-secret.example",
                "NO_PROXY": "internal-secret.example",
                "SSL_CERT_FILE": "/tmp/custom-ca-secret.pem",
                "SSL_CERT_DIR": "/tmp/custom-ca-secret-dir",
                "SSLKEYLOGFILE": "/tmp/ssl-key-log-secret",
                "CURL_CA_BUNDLE": "/tmp/curl-ca-secret.pem",
                "REQUESTS_CA_BUNDLE": "/tmp/requests-ca-secret.pem",
            ],
            forHandoff: true
        )
        #expect(routedEnvironment["PATH"] == "/usr/bin")
        #expect(routedEnvironment["CODEROUTER_API_URL"] == nil)
        #expect(routedEnvironment["CODEROUTER_DATA_DIR"] == nil)
        #expect(routedEnvironment["CODEROUTER_HANDOFF_FD"] == nil)
        #expect(routedEnvironment["CODEROUTER_CMUX_HANDOFF_SOCKET"] == nil)
        #expect(routedEnvironment["AWS_REGION"] == "us-west-2")
        #expect(routedEnvironment["AWS_PROFILE"] == "dev-profile")
        #expect(routedEnvironment["GOOGLE_CLOUD_PROJECT"] == "project-config")
        #expect(routedEnvironment["SSH_AUTH_SOCK"] == "/tmp/ssh-agent.sock")
        #expect(routedEnvironment["HTTP_PROXY"] == nil)
        #expect(routedEnvironment["HTTPS_PROXY"] == nil)
        #expect(routedEnvironment["https_proxy"] == nil)
        #expect(routedEnvironment["ALL_PROXY"] == nil)
        #expect(routedEnvironment["NO_PROXY"] == nil)
        #expect(routedEnvironment["SSL_CERT_FILE"] == nil)
        #expect(routedEnvironment["SSL_CERT_DIR"] == nil)
        #expect(routedEnvironment["SSLKEYLOGFILE"] == nil)
        #expect(routedEnvironment["CURL_CA_BUNDLE"] == nil)
        #expect(routedEnvironment["REQUESTS_CA_BUNDLE"] == nil)
        let managementEnvironment = launchPolicy.childEnvironment(
            ["HTTPS_PROXY": "https://proxy-preserved.example"],
            forHandoff: false
        )
        #expect(
            managementEnvironment["HTTPS_PROXY"]
                == "https://proxy-preserved.example"
        )
        let nakedEnvironment = launchPolicy.childEnvironment(
            [
                "OPENAI_API_KEY": "provider-key",
                "GITHUB_TOKEN": "tool-token",
                "AWS_ACCESS_KEY_ID": "aws-key",
                "CUSTOM_SECRET_TOKEN": "tool-secret",
                "CMUX_SOCKET_CAPABILITY": "cmux-secret",
                "CODEROUTER_HANDOFF_FD": "3",
                "DYLD_LIBRARY_PATH": "/tmp/injected",
            ],
            forHandoff: false,
            preserveProviderCredentials: true
        )
        #expect(nakedEnvironment["OPENAI_API_KEY"] == "provider-key")
        #expect(nakedEnvironment["GITHUB_TOKEN"] == "tool-token")
        #expect(nakedEnvironment["AWS_ACCESS_KEY_ID"] == "aws-key")
        #expect(nakedEnvironment["CUSTOM_SECRET_TOKEN"] == "tool-secret")
        #expect(nakedEnvironment["CMUX_SOCKET_CAPABILITY"] == nil)
        #expect(nakedEnvironment["CODEROUTER_HANDOFF_FD"] == nil)
        #expect(nakedEnvironment["DYLD_LIBRARY_PATH"] == nil)
    }

    private func runCLI(
        cliPath: String,
        arguments: [String],
        environment: [String: String],
        standardInput: String? = nil,
        allowUnsignedCoderouter: Bool = true,
        timeout: TimeInterval = 5
    ) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments
        var childEnvironment = ProcessInfo.processInfo.environment
        for key in childEnvironment.keys where key.hasPrefix("CMUX_") || key.hasPrefix("CMUXD_") {
            childEnvironment.removeValue(forKey: key)
        }
        childEnvironment.merge(environment) { _, newValue in newValue }
        if allowUnsignedCoderouter {
            childEnvironment["CMUX_CODEROUTER_TEST_ALLOW_UNSIGNED"] = "1"
        }
        childEnvironment["AppleLanguages"] = childEnvironment["AppleLanguages"] ?? "(en)"
        childEnvironment["AppleLocale"] = childEnvironment["AppleLocale"] ?? "en_US"
        process.environment = childEnvironment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let stdinPipe: Pipe?
        if standardInput != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            stdinPipe = pipe
        } else {
            process.standardInput = FileHandle.nullDevice
            stdinPipe = nil
        }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return ProcessResult(
                status: 127,
                stdout: "",
                stderr: error.localizedDescription,
                timedOut: false
            )
        }
        if let standardInput, let stdinPipe,
           let data = standardInput.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
            try? stdinPipe.fileHandleForWriting.close()
        }
        let timedOut: Bool
        switch finished.wait(timeout: .now() + timeout) {
        case .success:
            timedOut = false
        case .timedOut:
            timedOut = true
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
        }

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return ProcessResult(
            status: timedOut ? 124 : process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            timedOut: timedOut
        )
    }

    private func writeExecutable(_ contents: String, at url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}
