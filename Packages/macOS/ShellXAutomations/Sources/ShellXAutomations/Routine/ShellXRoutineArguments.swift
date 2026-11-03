/// Parses the arguments after `shellx routine`.
public struct ShellXRoutineArguments: Equatable, Sendable {
    /// The parsed command.
    public let command: ShellXRoutineCommand

    /// Parses `arguments` (subcommand first).
    public init(_ arguments: [String]) throws(ShellXRoutineArgumentsError) {
        guard let subcommand = arguments.first else { throw .usage }
        let rest = Array(arguments.dropFirst())
        switch subcommand.lowercased() {
        case "run": command = try Self.parseRun(rest)
        case "notify": command = try Self.parseNotify(rest)
        case "list": command = try Self.parseList(rest)
        default: throw .unknownSubcommand(subcommand)
        }
    }

    private static func parseRun(_ args: [String]) throws(ShellXRoutineArgumentsError) -> ShellXRoutineCommand {
        var id: String?
        var trigger = ShellXRunTrigger.manual
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "--trigger" {
                let value = try value(after: index, in: args, flag: arg)
                guard let parsed = ShellXRunTrigger(rawValue: value) else { throw .invalidTrigger(value) }
                trigger = parsed
                index += 2
            } else if id == nil, !arg.hasPrefix("-"), !arg.isEmpty {
                id = arg
                index += 1
            } else {
                throw .unexpectedArgument(arg)
            }
        }
        guard let id else { throw .missingID }
        return .run(id: id, trigger: trigger)
    }

    private static func parseNotify(_ args: [String]) throws(ShellXRoutineArgumentsError) -> ShellXRoutineCommand {
        var values: [String: String] = [:]
        var index = 0
        while index < args.count {
            let arg = args[index]
            guard ["--name", "--status", "--body"].contains(arg) else { throw .unexpectedArgument(arg) }
            values[arg] = try value(after: index, in: args, flag: arg)
            index += 2
        }
        guard let name = values["--name"], !name.isEmpty else { throw .missingValue(flag: "--name") }
        guard let rawStatus = values["--status"] else { throw .missingValue(flag: "--status") }
        guard let body = values["--body"] else { throw .missingValue(flag: "--body") }
        let status: ShellXNotifyEvent
        switch rawStatus {
        case "done": status = .done
        case "failed": status = .failed
        case "needs-you": status = .needsYou
        default: throw .invalidStatus(rawStatus)
        }
        return .notify(name: name, status: status, body: body)
    }

    private static func parseList(_ args: [String]) throws(ShellXRoutineArgumentsError) -> ShellXRoutineCommand {
        var json = false
        for arg in args {
            guard arg == "--json" else { throw .unexpectedArgument(arg) }
            json = true
        }
        return .list(json: json)
    }

    private static func value(after index: Int, in args: [String], flag: String) throws(ShellXRoutineArgumentsError) -> String {
        guard index + 1 < args.count else { throw .missingValue(flag: flag) }
        return args[index + 1]
    }
}
