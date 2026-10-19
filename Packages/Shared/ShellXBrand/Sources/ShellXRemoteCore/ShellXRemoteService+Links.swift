import Foundation
import os

extension ShellXRemoteService {
    // MARK: - Remote sessions (viewer side)

    /// Starts (or waits for) the link to `machine`, ≤ 20 s, then opens a local workspace attached to the
    /// first remote terminal, creating a remote workspace when there is none.
    public func openSession(on machine: RemoteMachine.ID) async throws {
        guard isSignedIn else { throw ShellXCoreError(code: "not_logged_in", message: "sign in first") }
        guard cmuxTuiAvailable else { throw ShellXCoreError(code: "cmux_tui_missing", message: "cmux-tui is missing") }
        let gen = generation
        let client: ShellXClientLinkSupervisor
        if let existing = clients[machine] {
            client = existing
        } else if let record = records[machine] {
            client = makeClient(record)
        } else {
            throw ShellXCoreError(code: "not_granted", message: "this Mac has no access to that machine")
        }
        switch await client.state {
        case .idle, .failed: await client.start(inviteFile: nil)
        default: break
        }
        guard await waitUntilConnected(machine, timeout: Self.connectTimeout) else {
            throw ShellXCoreError(code: "offline", message: "the machine did not connect in time")
        }
        try checkCurrent(gen)
        let socket = env.paths.clientSocket(for: machine)
        var terminal = try await firstTerminal(socket)
        if terminal == nil {
            let created = try await run(RemoteCommandLine.workspaceCreate(clientSocket: socket, name: Self.sessionWorkspaceName))
            guard created.status == 0 else {
                throw ShellXCoreError(code: "workspace_create_failed", message: "workspace create exited \(created.status)")
            }
            terminal = try await firstTerminal(socket)
        }
        guard let terminal else { throw ShellXCoreError(code: "no_terminal", message: "the machine has no terminal") }
        try checkCurrent(gen)
        let command = RemoteCommandLine.attachShellCommand(clientPath: env.cmuxTui.path, socketPath: socket.path, terminalID: terminal)
        guard let workspace = env.workspaceOpener.openRemoteTerminal(title: machineName(machine), attachCommand: command) else {
            throw ShellXCoreError(code: "no_window", message: "no window can open the session")
        }
        remoteWorkspaces[workspace] = machine
        RemoteLog.service.info("opened \(terminal, privacy: .public) of \(machine, privacy: .public)")
    }

    /// The local workspace `id` was closed: it no longer shows a remote terminal. L3 calls this on workspace
    /// close; entries may also name a machine that is no longer in `machines`.
    public func forgetRemoteWorkspace(_ id: UUID) {
        remoteWorkspaces[id] = nil
    }

    func firstTerminal(_ socket: URL) async throws -> String? {
        let listed = try await run(RemoteCommandLine.terminalList(clientSocket: socket))
        guard listed.status == 0 else {
            throw ShellXCoreError(code: "terminal_list_failed", message: "terminal list exited \(listed.status)")
        }
        return Self.firstTerminalID(listed.stdout)
    }

    // MARK: - Client links

    @discardableResult
    func makeClient(_ record: RemoteLinkRecord) -> ShellXClientLinkSupervisor {
        let machine = record.machineID
        let client = ShellXClientLinkSupervisor(machine: machine, record: record, deviceName: env.device.machineName,
                                                paths: env.paths, cmuxTui: env.cmuxTui, refresher: refresher,
                                                launcher: env.launcher, clock: env.clock, store: env.store)
        clients[machine] = client
        linkStates[machine] = .idle
        let gen = generation
        // The stream never finishes; this consumer is cancelled with the session or when the link is replaced.
        setTask("link:" + machine, Task { [weak self] in
            for await state in client.stateStream { self?.linkChanged(machine, state, client: client, gen) }
        })
        return client
    }

    /// A fresh approval replaces any older link to the same machine.
    func replaceClient(_ record: RemoteLinkRecord, inviteFile: URL, _ gen: Int) async {
        let machine = record.machineID
        if let old = clients.removeValue(forKey: machine) {
            tasks.removeValue(forKey: "link:" + machine)?.cancel()
            await old.stop()
        }
        guard isCurrent(gen) else {
            removeInvite(inviteFile.lastPathComponent)
            return
        }
        let client = makeClient(record)
        rebuildMachines()
        await client.start(inviteFile: inviteFile)
    }

    func linkChanged(_ machine: RemoteMachine.ID, _ state: LinkState, client: ShellXClientLinkSupervisor, _ gen: Int) {
        guard isCurrent(gen), clients[machine] === client else { return }
        linkStates[machine] = state
        switch state {
        case .connected:
            records[machine]?.enrolled = true
            resumeWaiters(machine, connected: true)
        case .failed(let code):
            RemoteLog.service.error("link to \(machine, privacy: .public) failed: \(code, privacy: .public)")
            if Self.isSignedOutCode(code) { handleSignedOut(gen); return }
            // R33: a grant that never enrolled cannot recover (its invite is gone): forget it, so the
            // machine offers "Request access" again.
            if records[machine]?.enrolled == false { forgetGrant(machine) }
        default:
            break
        }
        rebuildMachines()
    }

    /// Removes the link, its in-memory and stored record (R33).
    func forgetGrant(_ machine: RemoteMachine.ID) {
        RemoteLog.service.notice("grant to \(machine, privacy: .public) never enrolled; record removed")
        clients[machine] = nil
        tasks.removeValue(forKey: "link:" + machine)?.cancel()
        linkStates[machine] = nil
        records[machine] = nil
        let store = env.store
        Self.linkStoreQueue.async {
            do { try store.remove(machineID: machine) } catch {
                RemoteLog.service.error("link record not removed machine=\(machine, privacy: .public) error=\(RemoteLog.code(error), privacy: .public)")
            }
        }
    }

    /// From each `machines.list`: an idle link to an online machine starts; the others learn whether their
    /// machine is online (offline kills the link and stops minting; online starts it again).
    func applyAvailability(_ gen: Int) async {
        for (machine, client) in clients {
            guard isCurrent(gen) else { return }
            guard let item = listed.first(where: { $0.machine_id == machine }) else { continue }
            if item.online, await client.state == .idle {
                guard isCurrent(gen) else { return }
                await client.start(inviteFile: nil)
            } else {
                await client.machineAvailability(online: item.online, lastSeen: item.lastSeen)
            }
        }
    }

    // MARK: - Waiting for a link

    /// True once the link to `machine` is connected; false after `timeout` on the injected clock or when the
    /// session ends.
    func waitUntilConnected(_ machine: RemoteMachine.ID, timeout: TimeInterval) async -> Bool {
        if case .connected = linkStates[machine] { return true }
        let token = UUID()
        let clock = env.clock
        let deadline = clock.now.addingTimeInterval(timeout)
        let timer = Task { [weak self] in
            do { try await clock.sleep(until: deadline) } catch { return }
            self?.resumeWaiter(machine, token, connected: false)
        }
        defer { timer.cancel() }
        return await withCheckedContinuation { continuation in
            connectWaiters[machine, default: [:]][token] = continuation
        }
    }

    func resumeWaiter(_ machine: RemoteMachine.ID, _ token: UUID, connected: Bool) {
        connectWaiters[machine]?.removeValue(forKey: token)?.resume(returning: connected)
    }

    func resumeWaiters(_ machine: RemoteMachine.ID, connected: Bool) {
        let waiters = connectWaiters.removeValue(forKey: machine) ?? [:]
        for waiter in waiters.values { waiter.resume(returning: connected) }
    }

    func resumeAllWaiters(connected: Bool) {
        for machine in Array(connectWaiters.keys) { resumeWaiters(machine, connected: connected) }
    }
}
