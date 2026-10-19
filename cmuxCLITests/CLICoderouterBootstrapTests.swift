import Darwin
import Foundation
import Testing

/// ShellX never downloads, installs or runs CodeRouter (a Manaflow service):
/// `cmux cr` and the `cmux coderouter` passthrough print a neutral message and
/// exit 127 whether or not a CodeRouter CLI is installed.
///
/// Every test isolates HOME and PATH so the developer's own CodeRouter install,
/// `~/.coderouter`, and `~/.cmux` never take part. The fake installs below would
/// record their arguments if anything exec'd them.
@Suite("CodeRouter is not available in ShellX")
struct CLICoderouterBootstrapTests {
    static let notAvailable = "CodeRouter is not available in ShellX."

    enum InstallRoot: CustomStringConvertible {
        case path
        case installerDefault
        case explicitCoderouterInstall

        var description: String {
            switch self {
            case .path: return "PATH"
            case .installerDefault: return "~/.coderouter"
            case .explicitCoderouterInstall: return "$CODEROUTER_INSTALL"
            }
        }
    }

    @Test("non-interactive: neutral message, exit 127, no install command, touches nothing")
    func nonInteractiveIsRefused() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let result = fixture.runCLI(
            arguments: ["cr", "--version"],
            extraEnvironment: [
                "CMUX_SOCKET_CAPABILITY": "missing-capability",
                "CMUX_SOCKET_PASSWORD": "missing-password",
            ]
        )

        #expect(!result.timedOut, Comment(rawValue: result.stderr))
        #expect(result.status == 127, Comment(rawValue: result.stderr))
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains(Self.notAvailable), Comment(rawValue: result.stderr))
        Self.expectNoInstallOffer(result.stderr)
        #expect(!result.stderr.contains(fixture.root.path))
        #expect(!result.stderr.contains(fixture.socketPath))
        #expect(!result.stderr.contains("missing-capability"))
        #expect(!result.stderr.contains("missing-password"))
        #expect(!fixture.fileManager.fileExists(atPath: fixture.installerDefaultRoot.path))
    }

    @Test("terminal: no offer and no prompt even with `y` typed, exit 127")
    func terminalIsRefusedWithoutPrompt() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let result = try fixture.runCLIUnderPTY(arguments: ["cr", "--version"], input: "y\n")

        #expect(!result.timedOut, Comment(rawValue: result.transcript))
        #expect(result.status == 127, Comment(rawValue: result.transcript))
        #expect(result.transcript.contains(Self.notAvailable), Comment(rawValue: result.transcript))
        Self.expectNoInstallOffer(result.transcript)
        #expect(!fixture.fileManager.fileExists(atPath: fixture.installerDefaultRoot.path))
    }

    @Test(
        "an installed CodeRouter is never exec'd",
        arguments: [InstallRoot.path, InstallRoot.installerDefault, InstallRoot.explicitCoderouterInstall]
    )
    func installedCoderouterIsNeverRun(installRoot: InstallRoot) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let binary: URL
        var extraEnvironment: [String: String] = [:]
        switch installRoot {
        case .path:
            let directory = fixture.root.appendingPathComponent("path-bin", isDirectory: true)
            binary = directory.appendingPathComponent("coderouter", isDirectory: false)
            extraEnvironment["PATH"] = directory.path
        case .installerDefault:
            binary = fixture.installerDefaultRoot.appendingPathComponent("bin/coderouter", isDirectory: false)
        case .explicitCoderouterInstall:
            let root = fixture.root.appendingPathComponent("custom-install-root", isDirectory: true)
            binary = root.appendingPathComponent("bin/coderouter", isDirectory: false)
            extraEnvironment["CODEROUTER_INSTALL"] = root.path
        }
        try fixture.writeExecutable(
            """
            #!/bin/sh
            printf '<%s>\\n' "$@" > "$HOME/coderouter-args"
            printf 'installed coderouter ran\\n'
            exit 41
            """,
            at: binary
        )

        let result = fixture.runCLI(arguments: ["cr", "login", "--device-auth"], extraEnvironment: extraEnvironment)

        #expect(!result.timedOut, Comment(rawValue: result.stderr))
        #expect(result.status == 127, Comment(rawValue: result.stderr))
        #expect(result.stdout.isEmpty, Comment(rawValue: result.stdout))
        #expect(result.stderr.contains(Self.notAvailable), Comment(rawValue: result.stderr))
        #expect(!fixture.homeFileExists("coderouter-args"))
    }

    @Test("`cmux coderouter` verbs cmux does not own are refused the same way")
    func coderouterPassthroughIsRefused() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let pathDirectory = fixture.root.appendingPathComponent("path-bin", isDirectory: true)
        try fixture.writeExecutable(
            """
            #!/bin/sh
            printf '<%s>\\n' "$@" > "$HOME/coderouter-args"
            exit 41
            """,
            at: pathDirectory.appendingPathComponent("coderouter", isDirectory: false)
        )

        let result = fixture.runCLI(
            arguments: ["coderouter", "login"],
            extraEnvironment: ["PATH": pathDirectory.path]
        )

        #expect(!result.timedOut, Comment(rawValue: result.stderr))
        #expect(result.status == 127, Comment(rawValue: result.stderr))
        #expect(result.stderr.contains(Self.notAvailable), Comment(rawValue: result.stderr))
        #expect(!fixture.homeFileExists("coderouter-args"))
    }

    /// Nothing points the user at an installer: no cmux.com URL, no curl
    /// command, no install question.
    static func expectNoInstallOffer(_ output: String) {
        #expect(!output.contains("[y/N]"), Comment(rawValue: output))
        #expect(!output.contains("curl"), Comment(rawValue: output))
        #expect(!output.contains("install.sh"), Comment(rawValue: output))
        #expect(!output.contains("cmux.com"), Comment(rawValue: output))
    }

    // MARK: - Fixture

    struct ProcessResult {
        let status: Int32
        let stdout: String
        let stderr: String
        let timedOut: Bool
    }

    struct PTYResult {
        let status: Int32
        let transcript: String
        let timedOut: Bool
    }

    private final class TranscriptBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ bytes: [UInt8], count: Int) {
            lock.lock()
            data.append(contentsOf: bytes[0..<count])
            lock.unlock()
        }

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }
    }

    struct Fixture {
        let fileManager = FileManager.default
        let cliPath: String
        /// Holds an isolated HOME, an empty PATH directory, and every marker file.
        let root: URL
        let home: URL
        let emptyPathDirectory: URL
        let socketPath: String

        init() throws {
            cliPath = try BundledCLITestSupport.bundledCLIPath(for: CLITestBundleAnchor.self)
            root = fileManager.temporaryDirectory
                .appendingPathComponent("cmux-coderouter-bootstrap-\(UUID().uuidString)", isDirectory: true)
            home = root.appendingPathComponent("home", isDirectory: true)
            emptyPathDirectory = root.appendingPathComponent("empty-path", isDirectory: true)
            try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: emptyPathDirectory, withIntermediateDirectories: true)
            let shortID = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
            socketPath = "/tmp/cli-crb-\(shortID).sock"
        }

        /// Where CodeRouter's installer puts the binary when `CODEROUTER_INSTALL` is unset.
        var installerDefaultRoot: URL {
            home.appendingPathComponent(".coderouter", isDirectory: true)
        }

        func cleanUp() {
            try? fileManager.removeItem(at: root)
        }

        func homeFileExists(_ name: String) -> Bool {
            fileManager.fileExists(atPath: home.appendingPathComponent(name, isDirectory: false).path)
        }

        /// The CLI's environment: the test host's, minus every cmux control value,
        /// with HOME and PATH pointed at this fixture and the socket at a path that
        /// does not exist, so nothing here can reach a running cmux.
        func environment(merging extra: [String: String]) -> [String: String] {
            var environment = ProcessInfo.processInfo.environment
            for key in environment.keys where key.hasPrefix("CMUX_") || key.hasPrefix("CMUXD_") {
                environment.removeValue(forKey: key)
            }
            environment.removeValue(forKey: "CODEROUTER_INSTALL")
            environment["HOME"] = home.path
            environment["CFFIXED_USER_HOME"] = home.path
            environment["PATH"] = emptyPathDirectory.path
            environment["AppleLanguages"] = "(en)"
            environment["AppleLocale"] = "en_US"
            environment["CMUX_SOCKET_PATH"] = socketPath
            environment["CMUX_CLI_SENTRY_DISABLED"] = "1"
            environment.merge(extra) { _, newValue in newValue }
            return environment
        }

        func writeExecutable(_ contents: String, at url: URL) throws {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        /// Runs the CLI with piped stdio and stdin at /dev/null: the non-interactive case.
        func runCLI(arguments: [String], extraEnvironment: [String: String] = [:]) -> ProcessResult {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cliPath)
            process.arguments = arguments
            process.environment = environment(merging: extraEnvironment)
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            do {
                try process.run()
            } catch {
                return ProcessResult(status: 127, stdout: "", stderr: error.localizedDescription, timedOut: false)
            }
            let timedOut = Self.waitOrKill(process, finished: finished, timeout: 10)
            let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return ProcessResult(
                status: timedOut ? 124 : process.terminationStatus,
                stdout: stdout,
                stderr: stderr,
                timedOut: timedOut
            )
        }

        /// Runs the CLI with all three stdio fds on a pseudo-terminal, the way a
        /// person at a terminal would, and answers the prompt with `input`.
        func runCLIUnderPTY(
            arguments: [String],
            input: String,
            extraEnvironment: [String: String] = [:]
        ) throws -> PTYResult {
            var masterFD: Int32 = -1
            var slaveFD: Int32 = -1
            guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            func slaveHandle() throws -> FileHandle {
                let fd = dup(slaveFD)
                guard fd >= 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            }
            let stdinHandle: FileHandle
            let stdoutHandle: FileHandle
            let stderrHandle: FileHandle
            do {
                stdinHandle = try slaveHandle()
                stdoutHandle = try slaveHandle()
                stderrHandle = try slaveHandle()
            } catch {
                Darwin.close(slaveFD)
                Darwin.close(masterFD)
                throw error
            }
            Darwin.close(slaveFD)
            let master = masterFD

            let process = Process()
            process.executableURL = URL(fileURLWithPath: cliPath)
            process.arguments = arguments
            process.environment = environment(merging: extraEnvironment)
            process.standardInput = stdinHandle
            process.standardOutput = stdoutHandle
            process.standardError = stderrHandle
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            do {
                try process.run()
            } catch {
                Darwin.close(master)
                throw error
            }
            // Only the CLI holds the slave now; when it (or what it exec'd) exits,
            // the master read below reports end of file.
            stdinHandle.closeFile()
            stdoutHandle.closeFile()
            stderrHandle.closeFile()

            // The line discipline queues the answer until the CLI reads stdin, so
            // it can be written before the prompt appears.
            let inputBytes = Array(input.utf8)
            var written = 0
            while written < inputBytes.count {
                let count = inputBytes[written...].withUnsafeBufferPointer { buffer in
                    Darwin.write(master, buffer.baseAddress, buffer.count)
                }
                if count < 0 {
                    if errno == EINTR { continue }
                    break
                }
                written += count
            }

            let transcript = TranscriptBuffer()
            let drained = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                var buffer = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = Darwin.read(master, &buffer, buffer.count)
                    if count > 0 {
                        transcript.append(buffer, count: count)
                        continue
                    }
                    if count < 0, errno == EINTR {
                        continue
                    }
                    break
                }
                drained.signal()
            }

            let timedOut = Self.waitOrKill(process, finished: finished, timeout: 10)
            _ = drained.wait(timeout: .now() + 2)
            Darwin.close(master)
            return PTYResult(
                status: timedOut ? 124 : process.terminationStatus,
                transcript: transcript.text,
                timedOut: timedOut
            )
        }

        private static func waitOrKill(_ process: Process, finished: DispatchSemaphore, timeout: TimeInterval) -> Bool {
            if finished.wait(timeout: .now() + timeout) == .success {
                return false
            }
            Darwin.kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + 2)
            return true
        }
    }
}
