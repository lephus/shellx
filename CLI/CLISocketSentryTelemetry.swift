import CmuxFoundation
import CmuxSettings
import Darwin
import Foundation

enum CLISocketEnvironment {
    static func socketPath(in environment: [String: String]) throws -> String? {
        let socketPath = normalized(environment["CMUX_SOCKET_PATH"])
        let legacySocketPath = normalized(environment["CMUX_SOCKET"])
        if let socketPath, let legacySocketPath, socketPath != legacySocketPath {
            throw CLIError(message: String(
                localized: "cli.socket.error.conflictingEnvironment",
                defaultValue: "Refusing to choose socket: CMUX_SOCKET_PATH and CMUX_SOCKET differ. Use CMUX_SOCKET_PATH or unset CMUX_SOCKET."
            ))
        }
        return socketPath ?? legacySocketPath
    }

    static func socketPathForTelemetry(in environment: [String: String]) -> String? {
        normalized(environment["CMUX_SOCKET_PATH"]) ?? normalized(environment["CMUX_SOCKET"])
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// ShellX links no Sentry SDK: failures are still classified (tests and the
/// capture probe rely on it), but nothing is ever sent.
final class CLISocketSentryTelemetry {
    private typealias CLIErrorMetadata = (
        code: String?,
        socketPathMissing: Bool,
        legacyMessage: String?,
        isStructuredProtocolResponse: Bool
    )

    private typealias ErrorClassification = (
        errorDescription: String,
        metadata: CLIErrorMetadata,
        isExpected: Bool
    )

    private let command: String
    private let subcommand: String
    private let socketPath: String
    private let envSocketPath: String?
    private let processEnv: [String: String]
    private let workspaceId: String?
    private let surfaceId: String?
    private let disabledByEnv: Bool
    private let noiseFilter: SentryNoiseFilter
    private let sentryPolicy: CLISocketSentryPolicy
    private let buildIdentityPolicy: SentryBuildIdentityPolicy


    private static func currentSentryBundleIdentifier(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let bundleIdentifier = environment["CMUX_BUNDLE_ID"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }

        if let bundleIdentifier = currentSentryBundle()?.bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }

        return nil
    }

    private static func currentBundleVersionValue(forKey key: String) -> String? {
        guard let value = currentSentryBundle()?.infoDictionary?[key] as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return nil
        }
        return trimmed
    }

    private static func currentSentryBundle() -> Bundle? {
        if Bundle.main.bundleIdentifier?.isEmpty == false {
            return Bundle.main
        }

        if let bundle = CLIExecutableLocator.enclosingAppBundle() {
            return bundle
        }

        return Bundle.main
    }

    init(command: String, commandArgs: [String], socketPath: String, processEnv: [String: String]) {
        self.command = command.lowercased()
        self.subcommand = commandArgs.first?.lowercased() ?? "help"
        self.socketPath = socketPath
        self.envSocketPath = CLISocketEnvironment.socketPathForTelemetry(in: processEnv)
        self.processEnv = processEnv
        self.workspaceId = processEnv["CMUX_WORKSPACE_ID"]
        self.surfaceId = processEnv["CMUX_SURFACE_ID"]
        self.disabledByEnv =
            processEnv["CMUX_CLI_SENTRY_DISABLED"] == "1" ||
            processEnv["CMUX_CLAUDE_HOOK_SENTRY_DISABLED"] == "1" ||
            Self.isFailOpenAgentHookAdmission(
                command: command.lowercased(),
                subcommand: commandArgs.first?.lowercased() ?? "help"
            )
        self.noiseFilter = SentryNoiseFilter()
        self.sentryPolicy = CLISocketSentryPolicy(environment: processEnv)
        // The cmux repo is public; rebranded forks have shipped with this
        // CLI's hardcoded DSN intact. Only a build that identifies as cmux
        // may report to it (Sentry issue CMUXTERM-MACOS-1RZF).
        self.buildIdentityPolicy = SentryBuildIdentityPolicy(
            bundleIdentifier: Self.currentSentryBundleIdentifier(environment: processEnv),
            trustedBaseBundleIdentifier: SocketPathMarkerFiles.stableBundleIdentifier
        )
    }

    /// `cmux hooks enqueue` fails open by design: every failure becomes the
    /// agent's neutral response, and failures are expected while the app is
    /// busy or quitting. Starting Sentry there is unbounded work inside the
    /// agent's hook budget.
    static func isFailOpenAgentHookAdmission(command: String, subcommand: String) -> Bool {
        command == "hooks" && subcommand == "enqueue"
    }

    func breadcrumb(_ message: String, data: [String: Any] = [:]) {
        guard shouldEmit else { return }
    }

    /// Captures an actionable CLI failure while preserving the original error
    /// for classification when the emitted Sentry error is deliberately
    /// privacy-reduced (for example, agent-hook summaries).
    func captureError(
        stage: String,
        error: Error,
        data: [String: Any] = [:],
        classificationError: Error? = nil
    ) {
        guard shouldEmit,
              let classification = classify(
            stage: stage,
            error: error,
            data: data,
            classificationError: classificationError
        ) else {
            return
        }
        let errorDescription = classification.errorDescription
        let cliErrorMetadata = classification.metadata
        guard !classification.isExpected else { return }
        let fingerprintKind = Self.fingerprintKind(
            for: classificationError ?? error,
            message: errorDescription,
            structuredCode: cliErrorMetadata.code
        )
        if let fingerprintKind,
           CLISentryErrorFingerprint.throttledKinds.contains(fingerprintKind),
           !claimThrottledCaptureSlot(stage: stage, kind: fingerprintKind) {
            return
        }
#if DEBUG
        recordCaptureProbe(stage: stage, error: error)
#endif
    }

    private var shouldEmit: Bool {
        !disabledByEnv && buildIdentityPolicy.allowsTelemetry
    }

    /// Returns whether a failure is expected and should skip telemetry work.
    /// This read-only preflight lets agent-hook throttles classify before they
    /// reserve a durable report slot.
    func isExpectedFailure(
        stage: String,
        error: Error,
        data: [String: Any] = [:],
        classificationError: Error? = nil
    ) -> Bool {
        guard shouldEmit,
              let classification = classify(
            stage: stage,
            error: error,
            data: data,
            classificationError: classificationError
        ) else {
            return false
        }
        return classification.isExpected
    }

    private func classify(
        stage: String,
        error: Error,
        data: [String: Any],
        classificationError: Error?
    ) -> ErrorClassification? {
        guard shouldEmit else { return nil }
        let errorDescription = String(describing: error)
        let classificationCandidate = classificationError ?? error
        let cliErrorMetadata = metadata(for: classificationCandidate)
        let classificationMessage = cliErrorMetadata.legacyMessage
            ?? String(describing: classificationCandidate)
        let dataKeys = Set(data.keys)
        let isAgentHookStage = stage.hasPrefix("agent-hook-")
        let hasStructuredCLIErrorCode = cliErrorMetadata.code?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let isExpectedAgentHookCLIError =
            isAgentHookStage &&
            (noiseFilter.isExpectedCLIAppLifecycleError(
                code: cliErrorMetadata.code,
                message: classificationMessage
            ) ||
                cliErrorMetadata.socketPathMissing)
        let isExpectedLegacyCLIError: Bool
        if !hasStructuredCLIErrorCode {
            isExpectedLegacyCLIError =
                noiseFilter.isExpectedCLISocketTransportFailure(
                    stage: stage,
                    message: classificationMessage,
                    dataKeys: dataKeys,
                    allowSandboxPolicyDenial: sentryPolicy.allowsSandboxPolicyDenial
                ) ||
                (isAgentHookStage &&
                    noiseFilter.isExpectedLegacyCLIAppLifecycleMessage(classificationMessage))
        } else {
            isExpectedLegacyCLIError = false
        }
        let isExpectedTransportFailure = noiseFilter.isExpectedCLISocketTransportFailure(
            stage: stage,
            message: errorDescription,
            dataKeys: dataKeys,
            allowSandboxPolicyDenial: sentryPolicy.allowsSandboxPolicyDenial,
            cliErrorCode: cliErrorMetadata.code,
            socketPathMissing: cliErrorMetadata.socketPathMissing
        )
        let isExpectedProtocolOutcome =
            cliErrorMetadata.isStructuredProtocolResponse &&
            noiseFilter.isExpectedCLIProtocolOutcomeCode(cliErrorMetadata.code)
        return (
            errorDescription: errorDescription,
            metadata: cliErrorMetadata,
            isExpected: isExpectedAgentHookCLIError ||
                isExpectedLegacyCLIError ||
                isExpectedTransportFailure ||
                isExpectedProtocolOutcome
        )
    }

    /// Chooses the stable fingerprint kind for a CLI failure: the structured
    /// v2 protocol error code when the app replied with one, else the known
    /// transport failure class of the rendered message, else `nil` so the
    /// event keeps Sentry's default grouping within its stage.
    private static func fingerprintKind(
        for error: Error,
        message: String,
        structuredCode: String? = nil
    ) -> String? {
        if let v2Code = (structuredCode ?? (error as? CLIError)?.v2Code)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !v2Code.isEmpty {
            return "v2-\(v2Code)"
        }
        return CLISentryErrorFingerprint().kind(forMessage: message)
    }

    /// One durable capture per (stage, kind) per throttle interval for
    /// expected-but-reportable volume states like command timeouts, which
    /// otherwise fire once per agent hook invocation while the app is wedged.
    /// Backed by the same locked state file the agent hook failure reporter
    /// uses; a claim error fails closed (skips the capture) like that reporter.
    private func claimThrottledCaptureSlot(stage: String, kind: String) -> Bool {
        let store = ClaudeHookSessionStore(processEnv: processEnv)
        // Bounded lock wait: the CLI is already on an error path, so a
        // contended/stuck state lock must skip the capture (fail closed)
        // instead of blocking the command's exit.
        return (try? store.claimAgentHookFailureReport(
            agentName: "cli-sentry",
            stage: stage,
            sessionId: kind,
            deadline: Date.now.addingTimeInterval(0.25)
        )) == true
    }

    /// Preserves structured CLI error provenance before Sentry bridges the
    /// value to an ``NSError``. The reporting policy must not infer lifecycle
    /// state from localized text when the protocol already supplied a code.
    private func metadata(for error: Error) -> CLIErrorMetadata {
        if let cliError = error as? CLIError {
            return (
                code: cliError.v2Code,
                socketPathMissing: cliError.socketFailureKind == .pathMissing,
                legacyMessage: String(describing: cliError),
                isStructuredProtocolResponse: cliError.isStructuredProtocolResponse
            )
        }

        // A few command helpers wrap failures in NSError. Walk the standard
        // underlying-error chain so the same policy applies after wrapping,
        // while keeping a hard bound against malformed cycles.
        var current: NSError? = error as NSError
        var remaining = 8
        while let candidate = current, remaining > 0 {
            if let underlying = candidate.userInfo[NSUnderlyingErrorKey] as? CLIError {
                return (
                    code: underlying.v2Code,
                    socketPathMissing: underlying.socketFailureKind == .pathMissing,
                    legacyMessage: String(describing: underlying),
                    isStructuredProtocolResponse: underlying.isStructuredProtocolResponse
                )
            }
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
            remaining -= 1
        }
        return (
            code: nil,
            socketPathMissing: false,
            legacyMessage: nil,
            isStructuredProtocolResponse: false
        )
    }

#if DEBUG
    private func recordCaptureProbe(stage: String, error: Error) {
        guard let path = processEnv["CMUX_CLI_SENTRY_CAPTURE_PROBE_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return
        }
        let payload = "stage=\(stage)\nerror=\(String(describing: error))\n"
        try? payload.write(toFile: NSString(string: path).expandingTildeInPath, atomically: true, encoding: .utf8)
    }

#endif


    private func baseContext() -> [String: Any] {
        var context: [String: Any] = [
            "command": command,
            "subcommand": subcommand,
            "requested_socket_path": socketPath,
            "env_socket_path": envSocketPath ?? "<unset>"
        ]
        if let workspaceId {
            context["workspace_id"] = workspaceId
        }
        if let surfaceId {
            context["surface_id"] = surfaceId
        }
        return context
    }

    private func socketDiagnostics() -> [String: Any] {
        var context: [String: Any] = [
            "cwd": FileManager.default.currentDirectoryPath,
            "uid": Int(getuid()),
            "euid": Int(geteuid())
        ]

        var st = stat()
        if lstat(socketPath, &st) == 0 {
            context["socket_exists"] = true
            context["socket_mode"] = String(format: "%o", Int(st.st_mode & 0o7777))
            context["socket_owner_uid"] = Int(st.st_uid)
            context["socket_owner_gid"] = Int(st.st_gid)
            context["socket_file_type"] = Self.fileTypeDescription(mode: st.st_mode)
        } else {
            let code = errno
            context["socket_exists"] = false
            context["socket_errno"] = Int(code)
            context["socket_errno_description"] = String(cString: strerror(code))
        }

        let tmpSockets = Self.discoverSockets(in: "/tmp", limit: 10)
        if !tmpSockets.isEmpty {
            context["tmp_cmux_sockets"] = tmpSockets
        }
        let taggedSockets = tmpSockets.filter { $0 != CLISocketPathResolver.legacyDefaultSocketPath }
        if CLISocketPathResolver.isImplicitDefaultPath(
            socketPath,
            bundleIdentifier: CLISocketPathResolver.currentAppBundleIdentifier(),
            environment: processEnv
        ),
           (envSocketPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
           !taggedSockets.isEmpty {
            context["possible_root_cause"] = "CMUX_SOCKET_PATH missing while tagged sockets exist"
        }

        return context
    }

    private static func fileTypeDescription(mode: mode_t) -> String {
        switch mode & mode_t(S_IFMT) {
        case mode_t(S_IFSOCK):
            return "socket"
        case mode_t(S_IFREG):
            return "regular"
        case mode_t(S_IFDIR):
            return "directory"
        case mode_t(S_IFLNK):
            return "symlink"
        default:
            return "other"
        }
    }

    private static func discoverSockets(in directory: String, limit: Int) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return []
        }
        var sockets: [String] = []
        for name in entries.sorted() {
            guard name.hasPrefix("cmux"), name.hasSuffix(".sock") else { continue }
            let fullPath = URL(fileURLWithPath: directory)
                .appendingPathComponent(name, isDirectory: false)
                .path
            var st = stat()
            guard lstat(fullPath, &st) == 0 else { continue }
            guard (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK) else { continue }
            sockets.append(fullPath)
            if sockets.count >= limit {
                break
            }
        }
        return sockets
    }

}
