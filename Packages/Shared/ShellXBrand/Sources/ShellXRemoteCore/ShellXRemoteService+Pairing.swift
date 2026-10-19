import Foundation
import os
#if canImport(Darwin)
import Darwin
#endif

extension ShellXRemoteService {
    // MARK: - Requests to this Mac (target side)

    /// D9 first layer, then: connect ticket to this machine (D3) → 300 s invitation → `InviteURI.summary` →
    /// `pair.approve {pairing_id, invite_uri, fingerprint}` → the daemon admits that invitation id only.
    /// The invite URI is a secret: it goes to the core's JSON (which seals it) and nowhere else.
    public func approve(_ id: PairingRequest.ID) async throws {
        guard let request = pendingApprovals.first(where: { $0.id == id }) else {
            throw ShellXCoreError(code: "not_found", message: "no pending request with that id")
        }
        // The fingerprint changed while shown, or does not match the server's: never approved, nothing runs.
        guard !request.suspicious else {
            throw ShellXCoreError(code: "fingerprint_mismatch", message: "the requester's fingerprint does not match")
        }
        guard !approving.contains(id) else { throw ShellXCoreError(code: "in_progress", message: "already approving") }
        guard case .connected = hostState, let me = thisMachineID, let route = hostRoute, let slot = hostSlot else {
            throw ShellXCoreError(code: "host_not_ready", message: "this Mac is not serving yet")
        }
        let gen = generation
        approving.insert(id)
        defer { approving.remove(id) }

        let mint = try await call("tickets.mint", ["permission": .string("connect"), "target_machine_id": .string(me),
                                                   "write_to": .string(Self.inviteTicketName)], as: MintReply.self)
        let ticketFile = URL(fileURLWithPath: mint.path)
        guard ticketFile.lastPathComponent == Self.inviteTicketName else {
            throw ShellXCoreError(code: "bad_response", message: "tickets.mint wrote an unexpected file")
        }
        try checkCurrent(gen)
        let created = try await run(RemoteCommandLine.enrollCreate(paths: env.paths, route: route, slot: slot, ticketFile: ticketFile,
                                                                   ttlSeconds: Int(Self.pairingLifetime)))
        guard created.status == 0 else {
            throw ShellXCoreError(code: "enroll_create_failed", message: "remote enroll create exited \(created.status)")
        }
        let uri = String(decoding: created.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let invitation = try? InviteURI.summary(of: uri), Self.isSafeID(invitation.invitationID) else {
            throw ShellXCoreError(code: "invite_invalid", message: "remote enroll create printed no usable invitation")
        }
        // Expected before the invite can reach anyone, so a fast enrollment is never denied; revoked (and the
        // invitation denied at the daemon) when the approval does not go through.
        gate.expect(invitationID: invitation.invitationID, pairingID: id, now: env.clock.now)
        do {
            try checkCurrent(gen)
            _ = try await call("pair.approve", ["pairing_id": .string(id), "invite_uri": .string(uri),
                                                "fingerprint": .string(request.fingerprint)], as: EmptyReply.self)
        } catch {
            let code = RemoteLog.code(error)
            RemoteLog.service.error("approve \(id, privacy: .public) failed: \(code, privacy: .public)")
            if isCurrent(gen) { gate.revoke(invitationID: invitation.invitationID) }
            _ = try? await run(RemoteCommandLine.enrollDeny(paths: env.paths, invitationID: invitation.invitationID))
            if code == "fingerprint_mismatch", isCurrent(gen) { markSuspicious(id) }
            throw error
        }
        guard isCurrent(gen) else { return }
        RemoteLog.service.info("approved \(id, privacy: .public), invitation \(invitation.invitationID, privacy: .public)")
        handledPairings.insert(id)
        pendingApprovals.removeAll { $0.id == id }
        ensureEnrollPoller(gen)
    }

    /// `pair.deny`; the request leaves `pendingApprovals` whatever the server answers.
    public func deny(_ id: PairingRequest.ID) async {
        handledPairings.insert(id)
        pendingApprovals.removeAll { $0.id == id }
        do { _ = try await call("pair.deny", ["pairing_id": .string(id)], as: EmptyReply.self) } catch {
            RemoteLog.service.error("deny \(id, privacy: .public) failed: \(RemoteLog.code(error), privacy: .public)")
        }
    }

    func pendingTick(_ gen: Int) async {
        do {
            let reply = try await call("pair.pending", as: PendingReply.self)
            guard isCurrent(gen) else { return }
            applyPending(reply.pairings)
        } catch {
            guard isCurrent(gen) else { return }
            let code = RemoteLog.code(error)
            if Self.isSignedOutCode(code) { handleSignedOut(gen); return }
            applyPending(nil)
        }
    }

    /// `nil` keeps the shown list (API down) and only drops expired entries. A request whose code or
    /// fingerprint changes while shown is replaced by a sticky suspicious copy of what the person saw.
    func applyPending(_ items: [PendingReply.Item]?) {
        let now = env.clock.now
        var next: [PairingRequest] = []
        if let items {
            for item in items where !handledPairings.contains(item.pairing_id) && !next.contains(where: { $0.id == item.pairing_id }) {
                let fingerprint = item.fingerprint ?? ""
                let flagged = (item.suspicious ?? true) || fingerprint.isEmpty
                if let shown = pendingApprovals.first(where: { $0.id == item.pairing_id }) {
                    let changed = shown.fingerprint != fingerprint || shown.code != item.code
                    if (changed || flagged) && !shown.suspicious {
                        RemoteLog.service.error("pairing \(shown.id, privacy: .public) changed while shown; marked suspicious")
                        next.append(Self.suspicious(shown))
                    } else {
                        next.append(shown)
                    }
                } else {
                    next.append(PairingRequest(id: item.pairing_id, fromMachineID: item.from_machine_id,
                                               requesterName: machineName(item.from_machine_id), code: item.code,
                                               fingerprint: fingerprint, suspicious: flagged, firstSeen: now))
                }
            }
        } else {
            next = pendingApprovals
        }
        next.removeAll { now >= $0.expiresAt }
        if next != pendingApprovals { pendingApprovals = next }
    }

    func markSuspicious(_ id: PairingRequest.ID) {
        guard let index = pendingApprovals.firstIndex(where: { $0.id == id }), !pendingApprovals[index].suspicious else { return }
        pendingApprovals[index] = Self.suspicious(pendingApprovals[index])
    }

    nonisolated static func suspicious(_ request: PairingRequest) -> PairingRequest {
        PairingRequest(id: request.id, fromMachineID: request.fromMachineID, requesterName: request.requesterName,
                       code: request.code, fingerprint: request.fingerprint, suspicious: true, firstSeen: request.firstSeen)
    }

    /// Polls the daemon's pending enrollments every second while the gate expects an invitation.
    func ensureEnrollPoller(_ gen: Int) {
        guard tasks["enroll"] == nil, !gate.isEmpty else { return }
        let clock = env.clock
        setTask("enroll", Task { [weak self] in
            var deadline = clock.now.addingTimeInterval(ShellXRemoteService.enrollPollInterval)
            while !Task.isCancelled {
                do { try await clock.sleep(until: deadline) } catch { return }
                guard let self, self.isCurrent(gen) else { return }
                await self.enrollTick()
                deadline = Self.nextBeat(after: deadline, every: Self.enrollPollInterval, now: clock.now)
                guard self.isCurrent(gen) else { return }
                self.gate.pruneExpired(now: clock.now)
                if self.gate.isEmpty {
                    self.tasks["enroll"] = nil
                    return
                }
            }
        })
    }

    /// D9 second layer: approve only invitation ids the gate issued for an approved pairing (once, ≤ 300 s);
    /// deny every other pending enrollment.
    func enrollTick() async {
        let pending: (status: Int32, stdout: Data)
        do { pending = try await run(RemoteCommandLine.enrollPending(paths: env.paths)) } catch {
            RemoteLog.service.error("enroll pending failed: \(RemoteLog.code(error), privacy: .public)")
            return
        }
        guard pending.status == 0 else {
            RemoteLog.service.error("enroll pending exited \(pending.status)")
            return
        }
        for invitation in Self.pendingInvitationIDs(pending.stdout) {
            guard Self.isSafeID(invitation) else {
                RemoteLog.service.error("pending enrollment with an unusable invitation id (\(invitation.utf8.count) bytes) left alone")
                continue
            }
            switch gate.decide(pendingInvitationID: invitation, now: env.clock.now) {
            case .approve(let pairingID):
                let result = try? await run(RemoteCommandLine.enrollApprove(paths: env.paths, invitationID: invitation))
                RemoteLog.service.info("""
                    enrollment \(invitation, privacy: .public) for \(pairingID, privacy: .public) approved, \
                    exit \(result?.status ?? -1)
                    """)
            case .deny:
                let result = try? await run(RemoteCommandLine.enrollDeny(paths: env.paths, invitationID: invitation))
                RemoteLog.service.notice("enrollment \(invitation, privacy: .public) denied, exit \(result?.status ?? -1)")
            }
        }
    }

    // MARK: - Requests from this Mac (viewer side)

    /// `pair.request` → the 6-digit code to compare on both screens; then `pair.poll` every 2 s for 300 s.
    public func requestAccess(to machine: RemoteMachine.ID) async throws -> String {
        guard isSignedIn else { throw ShellXCoreError(code: "not_logged_in", message: "sign in first") }
        guard cmuxTuiAvailable else { throw ShellXCoreError(code: "cmux_tui_missing", message: "cmux-tui is missing") }
        if let waiting = outgoing.last(where: { $0.toMachineID == machine && $0.status == .waiting }) { return waiting.code }
        guard !requesting.contains(machine) else { throw ShellXCoreError(code: "in_progress", message: "already requesting") }
        let gen = generation
        requesting.insert(machine)
        defer { requesting.remove(machine) }
        let reply = try await call("pair.request", ["to_machine_id": .string(machine)], as: RequestReply.self)
        try checkCurrent(gen)
        let pairing = OutgoingPairing(id: reply.pairing_id, toMachineID: machine, code: reply.code,
                                      ownFingerprint: reply.fingerprint, status: .waiting, createdAt: env.clock.now)
        outgoing.removeAll { $0.toMachineID == machine }
        outgoing.append(pairing)
        rebuildMachines()
        RemoteLog.service.info("requested access to \(machine, privacy: .public), pairing \(pairing.id, privacy: .public)")
        setTask("poll:" + pairing.id, Task { [weak self] in await self?.pollOutgoing(pairing, gen) })
        return reply.code
    }

    func pollOutgoing(_ pairing: OutgoingPairing, _ gen: Int) async {
        let clock = env.clock
        let inviteName = "invite-\(SHA256Pure.hash8(pairing.id)).uri"
        var next = pairing.createdAt.addingTimeInterval(Self.pollInterval)
        while isCurrent(gen), !Task.isCancelled {
            do { try await clock.sleep(until: next) } catch { return }
            guard isCurrent(gen) else { return }
            if clock.now.timeIntervalSince(pairing.createdAt) >= Self.pairingLifetime {
                finishOutgoing(pairing.id, .expired)
                return
            }
            do {
                let reply = try await call("pair.poll", ["pairing_id": .string(pairing.id), "write_invite_to": .string(inviteName)],
                                           as: PollReply.self)
                guard isCurrent(gen) else {
                    if reply.invite_path != nil { removeInvite(inviteName) }
                    return
                }
                switch reply.status {
                case "pending": break
                case "approved": await outgoingApproved(pairing, reply, inviteName: inviteName, gen); return
                case "denied": finishOutgoing(pairing.id, .denied); return
                case "expired": finishOutgoing(pairing.id, .expired); return
                default: finishOutgoing(pairing.id, .failed(code: "bad_response")); return
                }
            } catch {
                guard isCurrent(gen) else { return }
                let code = RemoteLog.code(error)
                if Self.isSignedOutCode(code) { handleSignedOut(gen); return }
                if Self.endsPoll(code) { finishOutgoing(pairing.id, .failed(code: code)); return }
            }
            next = Self.nextBeat(after: next, every: Self.pollInterval, now: clock.now)
        }
    }

    /// Saves `{machineID, relay_route, relay_slot, daemon_fingerprint, enrolled: false}` and starts the link
    /// with the invite file (it deletes the file once enrolled or when the invite can no longer be used).
    func outgoingApproved(_ pairing: OutgoingPairing, _ reply: PollReply, inviteName: String, _ gen: Int) async {
        guard let path = reply.invite_path, URL(fileURLWithPath: path).lastPathComponent == inviteName,
              let route = reply.relay_route, let slot = reply.relay_slot, !slot.isEmpty,
              let fingerprint = reply.daemon_fingerprint, !fingerprint.isEmpty else {
            removeInvite(inviteName)
            finishOutgoing(pairing.id, .failed(code: "bad_response"))
            return
        }
        let machine = pairing.toMachineID
        let record = RemoteLinkRecord(machineID: machine, route: route, slot: slot, daemonFingerprint: fingerprint, enrolled: false)
        records[machine] = record
        let store = env.store
        do { try await Self.offMain { try store.upsert(record) } } catch {
            RemoteLog.service.error("link record not saved machine=\(machine, privacy: .public) error=\(RemoteLog.code(error), privacy: .public)")
        }
        guard isCurrent(gen) else { removeInvite(inviteName); return }
        finishOutgoing(pairing.id, .approved)
        await replaceClient(record, inviteFile: URL(fileURLWithPath: path), gen)
    }

    func finishOutgoing(_ id: String, _ status: OutgoingPairing.Status) {
        tasks["poll:" + id] = nil
        guard let index = outgoing.firstIndex(where: { $0.id == id }) else { return }
        outgoing[index].status = status
        RemoteLog.service.info("pairing \(id, privacy: .public) ended: \(String(describing: status), privacy: .public)")
        rebuildMachines()
    }

    /// Unlinks this Mac's own invite file by name (a symlink is removed, never followed).
    func removeInvite(_ name: String) {
        _ = unlink(env.paths.coreStateDir.appendingPathComponent("tickets/" + name).path)
    }
}
