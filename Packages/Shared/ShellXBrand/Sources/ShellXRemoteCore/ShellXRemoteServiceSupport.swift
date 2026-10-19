import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - K3 replies (shellx-core `machines.rs`, `tickets.rs`, `pairing.rs`, `auth.rs`; D5 fields)

struct EmptyReply: Decodable, Sendable {}

/// `auth.login` → `{user_id, device_id, device_public_key_b64, fingerprint}` (never the token).
struct LoginReply: Decodable, Sendable {
    let user_id: String
    let device_id: String
}

/// `machines.register` → `{machine_id, slot}`.
struct RegisterReply: Decodable, Sendable {
    let machine_id: String
    let slot: String
}

/// `tickets.mint {write_to}` → `{path, expires_at_unix, relay_url}` (the ticket stays in the file).
struct MintReply: Decodable, Sendable {
    let path: String
    let relay_url: String
}

/// `machines.list` → `{machines: [{is_this_machine, machine_id, name, platform, online, last_seen_unix, fingerprint}]}`.
struct MachineListReply: Decodable, Sendable {
    struct Item: Decodable, Equatable, Sendable {
        let is_this_machine: Bool?
        let machine_id: String
        let name: String
        let platform: String
        let online: Bool
        let last_seen_unix: Double?
        let fingerprint: String?

        var isThisMachine: Bool { is_this_machine ?? false }
        /// `last_seen_unix` is 0 when the server never saw the machine.
        var lastSeen: Date? { last_seen_unix.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil } }
    }

    let machines: [Item]
}

/// `pair.pending` → `{pairings: [{pairing_id, from_machine_id, code, fingerprint, server_fingerprint, suspicious}]}`.
struct PendingReply: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        let pairing_id: String
        let from_machine_id: String
        let code: String
        /// Computed locally by the core from the requester key; "" when the server sent no usable key.
        let fingerprint: String?
        let suspicious: Bool?
    }

    let pairings: [Item]
}

/// `pair.request` → `{pairing_id, code, fingerprint}` (`fingerprint` = this Mac's device key, D1).
struct RequestReply: Decodable, Sendable {
    let pairing_id: String
    let code: String
    let fingerprint: String
}

/// `pair.poll {write_invite_to}` → `{status}`, or when approved
/// `{status, invite_path, relay_route, relay_slot, daemon_fingerprint}` (the invite stays in the file).
struct PollReply: Decodable, Sendable {
    let status: String
    let invite_path: String?
    let relay_route: String?
    let relay_slot: String?
    let daemon_fingerprint: String?
}

// MARK: - Off-main work

extension ShellXRemoteService {
    /// Runs blocking work (core calls, file and socket syscalls) on a global queue: never on the main
    /// thread, never on the cooperative pool.
    nonisolated static func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(with: Result { try work() }) }
        }
    }

    /// `links.json` reads and writes, in order on one serial queue (a removal never overtakes a later upsert).
    nonisolated static let linkStoreQueue = DispatchQueue(label: "pro.shellx.remote-service.links", qos: .utility)

    nonisolated static func onLinkStore<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            linkStoreQueue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    /// One K3 call through the core (blocks on HTTP and disk inside, so always off main).
    func call<R: Decodable & Sendable>(_ method: String, _ params: [String: JSONValue] = [:], as type: R.Type) async throws -> R {
        let core = env.core
        return try await Self.offMain { try core.call(method, params, as: R.self) }
    }

    /// A short-lived cmux-tui run, detached from the main actor. argv carries flags, ids and file paths only.
    func run(_ args: [String]) async throws -> (status: Int32, stdout: Data) {
        let launcher = env.launcher, cmuxTui = env.cmuxTui
        return try await Task.detached { try await launcher.run(cmuxTui, args, env: [:]) }.value
    }

    // MARK: Codes and parsing

    /// The session is gone: 401-class answers and a core without `session.json`.
    nonisolated static func isSignedOutCode(_ code: String) -> Bool {
        ["not_logged_in", "unauthorized", "http_401"].contains(code)
    }

    /// `pair.poll` failures that will not heal by polling again.
    nonisolated static func endsPoll(_ code: String) -> Bool {
        LinkFailure.isFatal(code) || ["not_found", "invite_invalid", "bad_response"].contains(code)
    }

    /// An id cmux-tui printed that is safe as one argv word: 1–256 of `[A-Za-z0-9._:-]`, not an option.
    nonisolated static func isSafeID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && !value.hasPrefix("-")
            && value.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5a) || ($0 >= 0x61 && $0 <= 0x7a)
                || $0 == 0x2e || $0 == 0x5f || $0 == 0x3a || $0 == 0x2d }
    }

    /// `remote enroll pending --json` prints the daemon's `PendingEnrollment` list
    /// (`cmux-remote/src/identity.rs`: `{invitation_id, device_name, device_fingerprint, requested_at_unix}`).
    nonisolated static func pendingInvitationIDs(_ stdout: Data) -> [String] {
        guard let items = try? JSONSerialization.jsonObject(with: stdout) as? [[String: Any]] else { return [] }
        return items.compactMap { $0["invitation_id"] as? String }
    }

    /// The first terminal id of `terminal list --json` (an array of public terminal snapshots).
    nonisolated static func firstTerminalID(_ stdout: Data) -> String? {
        guard let items = try? JSONSerialization.jsonObject(with: stdout) as? [[String: Any]] else { return nil }
        return items.lazy.compactMap { $0["id"] as? String }.first { isSafeID($0) }
    }
}

// MARK: - Stale invites

/// Launch-time cleanup of `<coreStateDir>/tickets/` (Task 12 note): `invite-*.uri` (sealed-invite files from
/// `pair.poll`) and `invite-connect.ticket` (the ticket of the last `approve`) are stale after a restart, and so is
/// any other `invite-*` older than the 300 s invite lifetime. Only regular files and symlinks are removed, by
/// name inside the directory opened `O_NOFOLLOW` (a symlink is unlinked itself, never followed).
enum RemoteInviteSweep {
    static let maxAge: TimeInterval = 300

    /// Number of files removed. `now` is wall-clock time (file mtimes are).
    static func sweep(ticketsDir: URL, now: Date) -> Int {
        let fd = open(ticketsDir.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return 0 }
        guard let dir = fdopendir(fd) else { close(fd); return 0 }
        defer { closedir(dir) }
        let dfd = dirfd(dir)
        var names: [String] = []
        while let entry = readdir(dir) {
            let length = Int(entry.pointee.d_namlen)
            let name = withUnsafeBytes(of: &entry.pointee.d_name) { String(decoding: $0.prefix(length), as: UTF8.self) }
            if name.hasPrefix("invite-") { names.append(name) }
        }
        var removed = 0
        for name in names {
            var st = stat()
            guard fstatat(dfd, name, &st, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
            let kind = st.st_mode & S_IFMT
            guard kind == S_IFREG || kind == S_IFLNK else { continue }
            let age = now.timeIntervalSince1970 - Double(st.st_mtimespec.tv_sec)
            guard name.hasSuffix(".uri") || name == ShellXRemoteService.inviteTicketName || age > maxAge else { continue }
            if unlinkat(dfd, name, 0) == 0 { removed += 1 }
        }
        return removed
    }
}
