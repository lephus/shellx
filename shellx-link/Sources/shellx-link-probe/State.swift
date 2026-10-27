import Darwin
import Foundation
import ShellXLinkAccount
import ShellXLinkCore

/// The phone's sign-in, as `session.json` keeps it. The token is a bearer secret: never printed.
struct StoredSession: Codable {
    var api: String
    var userID: String
    var deviceID: String
    var token: String

    private enum CodingKeys: String, CodingKey {
        case api
        case userID = "user_id"
        case deviceID = "device_id"
        case token
    }

    func relayAPI() throws -> RelayAPI {
        guard let url = URL(string: api) else { throw ProbeError("session.json holds a bad api URL; log in again") }
        return try RelayAPI(baseURL: url, clientVersion: Probe.clientVersion)
    }
}

/// `--state <dir>`: `phone.key`, `session.json` and `machines.json`, all owner-only.
struct ProbeState {
    let directory: String

    static let keyFile = "phone.key"
    static let sessionFile = "session.json"
    static let machinesFile = "machines.json"

    /// Opens `--state`, creating it 0700 when missing. Refuses a directory others can enter.
    static func open(_ args: Arguments) throws -> ProbeState {
        let path = try args.required("state")
        var info = stat()
        if stat(path, &info) != 0 {
            guard errno == ENOENT else { throw ProbeError("cannot read the --state directory: \(PrivateFile.errnoText())") }
            guard mkdir(path, 0o700) == 0 else {
                throw ProbeError("cannot create the --state directory: \(PrivateFile.errnoText())")
            }
            return ProbeState(directory: path)
        }
        guard info.st_mode & S_IFMT == S_IFDIR else { throw ProbeError("--state is not a directory") }
        guard info.st_uid == getuid() else { throw ProbeError("the --state directory belongs to another user") }
        guard info.st_mode & 0o077 == 0 else { throw ProbeError("the --state directory is open to others; chmod 700 it") }
        return ProbeState(directory: path)
    }

    private func path(_ name: String) -> String { (directory as NSString).appendingPathComponent(name) }

    // MARK: Key

    /// The phone's Link static key, created on first use.
    func loadOrCreateKey() throws -> NoiseStaticKey {
        if FileManager.default.fileExists(atPath: path(Self.keyFile)) { return try loadKey() }
        let key = NoiseStaticKey()
        try PrivateFile.create(path(Self.keyFile), contents: key.rawPrivate)
        return key
    }

    func loadKey() throws -> NoiseStaticKey {
        let data = try PrivateFile.read(path(Self.keyFile), what: Self.keyFile, hint: "run login first")
        guard data.count == 32, let key = try? NoiseStaticKey(rawPrivate: data) else {
            throw ProbeError("\(Self.keyFile) is not a key file written by shellx-link-probe")
        }
        return key
    }

    // MARK: Session

    func saveSession(_ session: StoredSession) throws {
        try PrivateFile.replace(path(Self.sessionFile), contents: try JSONEncoder().encode(session))
    }

    func loadSession() throws -> StoredSession {
        let data = try PrivateFile.read(path(Self.sessionFile), what: Self.sessionFile, hint: "run login first")
        guard let session = try? JSONDecoder().decode(StoredSession.self, from: data) else {
            throw ProbeError("\(Self.sessionFile) is damaged; log in again")
        }
        return session
    }

    func removeSession() {
        unlink(path(Self.sessionFile))
    }

    // MARK: Machines

    func loadMachines() throws -> [PairedMachine] {
        guard FileManager.default.fileExists(atPath: path(Self.machinesFile)) else { return [] }
        let data = try PrivateFile.read(path(Self.machinesFile), what: Self.machinesFile, hint: "")
        guard let machines = try? JSONDecoder().decode([PairedMachine].self, from: data) else {
            throw ProbeError("\(Self.machinesFile) is damaged; pair again")
        }
        return machines
    }

    func saveMachines(_ machines: [PairedMachine]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try PrivateFile.replace(path(Self.machinesFile), contents: try encoder.encode(machines))
    }

    /// The machine `--machine` names, or the only paired one when it is left out.
    func machine(_ args: Arguments) throws -> PairedMachine {
        let machines = try loadMachines()
        if let id = args.optional("machine") {
            guard let machine = machines.first(where: { $0.machineID == id }) else {
                throw ProbeError("no paired machine has that id; see `machines`")
            }
            return machine
        }
        switch machines.count {
        case 0: throw ProbeError("no machine is paired; run pair first")
        case 1: return machines[0]
        default: throw ProbeError("\(machines.count) machines are paired; choose one with --machine")
        }
    }
}

/// Owner-only files. Errors name the file's role, never its contents.
enum PrivateFile {
    /// Refuses a secret file that its group or others can read. Errors name `--<flag>`, not the path.
    static func checkOwnerOnly(_ path: String, flag: String) throws {
        var info = stat()
        guard stat(path, &info) == 0 else { throw ProbeError("cannot read the --\(flag) file: \(errnoText())") }
        guard info.st_mode & 0o077 == 0 else {
            throw ProbeError("the --\(flag) file is readable by others; chmod 600 it")
        }
    }

    static func read(_ path: String, what: String, hint: String) throws -> Data {
        var info = stat()
        guard stat(path, &info) == 0 else {
            throw ProbeError("cannot read \(what): \(errnoText())\(hint.isEmpty ? "" : " (\(hint))")")
        }
        guard info.st_mode & 0o077 == 0 else { throw ProbeError("\(what) is readable by others; chmod 600 it") }
        guard let data = FileManager.default.contents(atPath: path) else { throw ProbeError("cannot read \(what)") }
        return data
    }

    /// Creates `path` with mode 0600; refuses to overwrite. Removes a partly written file.
    static func create(_ path: String, contents: Data) throws {
        let fd = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw ProbeError("cannot create \((path as NSString).lastPathComponent): \(errnoText())") }
        let ok = writeAll(fd, contents) && fsync(fd) == 0
        close(fd)
        guard ok else {
            unlink(path)
            throw ProbeError("cannot write \((path as NSString).lastPathComponent): \(errnoText())")
        }
    }

    /// Replaces `path` atomically with a new 0600 file.
    static func replace(_ path: String, contents: Data) throws {
        let temporary = "\(path).tmp-\(getpid())"
        unlink(temporary)
        try create(temporary, contents: contents)
        guard rename(temporary, path) == 0 else {
            unlink(temporary)
            throw ProbeError("cannot save \((path as NSString).lastPathComponent): \(errnoText())")
        }
    }

    private static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
    }

    static func errnoText() -> String { String(cString: strerror(errno)) }
}

/// The pairing URI from `--offer-file`: the raw `shellx-link://pair?...` URI, or the JSON reply of
/// `shellx.link.debug_pairing_offer` (bare or in the socket envelope). Never printed.
enum OfferFile {
    static func read(_ path: String) throws -> String {
        try PrivateFile.checkOwnerOnly(path, flag: "offer-file")
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8)
        else { throw ProbeError("cannot read the --offer-file file") }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("shellx-link://") { return trimmed }
        guard var object = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any] else {
            throw ProbeError("the --offer-file holds neither a shellx-link:// URI nor a JSON object")
        }
        if let result = object["result"] as? [String: Any] { object = result }
        guard let uri = object["offer_uri"] as? String else { throw ProbeError("the --offer-file JSON has no offer_uri") }
        return uri
    }
}

/// Reads one line from stdin without echo when stdin is a terminal.
enum PasswordInput {
    static func read() throws -> String {
        if isatty(STDIN_FILENO) != 0 {
            var buffer = [CChar](repeating: 0, count: 1024)
            defer { _ = buffer.withUnsafeMutableBufferPointer { memset_s($0.baseAddress, $0.count, 0, $0.count) } }
            guard let line = readpassphrase("password: ", &buffer, buffer.count, RPP_ECHO_OFF | RPP_REQUIRE_TTY) else {
                throw ProbeError("cannot read the password")
            }
            return String(cString: line)
        }
        guard let line = readLine(strippingNewline: true), !line.isEmpty else {
            throw ProbeError("--password-stdin found no password on stdin")
        }
        return line
    }
}
