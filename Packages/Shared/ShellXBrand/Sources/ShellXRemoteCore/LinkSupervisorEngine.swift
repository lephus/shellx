import Foundation

/// Mutable driver state shared by the daemon and client link supervisors (kept inside each actor).
struct LinkEngine: Sendable {
    var machine = LinkStateMachine()
    /// Bumped on every spawn and kill; events of an older process are ignored.
    var processGeneration = 0
    var processAlive = false
    var handle: (any SidecarHandle)?
    var processTask: Task<Void, Never>?
    /// Bumped on every schedule, cancel and fire; a retry timer only fires for its own generation,
    /// so a duplicate `retryDue` can never spawn twice.
    var retryGeneration = 0
    var retryTask: Task<Void, Never>?
    /// Bumped when a mint starts and on every kill; a mint that finishes after a stop, an offline
    /// or a newer attempt does not spawn.
    var attempt = 0
    /// Daemon only: the `enroll status` poll after a spawn.
    var probeTask: Task<Void, Never>?
}

enum SidecarEvent: Sendable { case line(String), exit(Int32) }

/// The driver for `LinkStateMachine`: performs its actions with a launcher, a clock and a ticket mint.
protocol LinkSupervising: Actor {
    var engine: LinkEngine { get set }
    var launcher: any SidecarLaunching { get }
    var clock: any RemoteClock { get }
    var cmuxTui: URL { get }
    var stateContinuation: AsyncStream<LinkState>.Continuation { get }

    /// Everything before a spawn (dirs, stale-daemon stop, ticket mint); returns a failure code or nil.
    func prepareAndMint() async -> String?
    func spawnCommand() -> (args: [String], env: [String: String])
    /// The link event a stdout line means, if any (never logged).
    func event(forLine line: String) -> LinkEvent?
    func didSpawn(generation: Int)
    func didPublish(_ state: LinkState) async
}

extension LinkSupervising {
    func feed(_ event: LinkEvent) async {
        let actions = engine.machine.handle(event, now: clock.now)
        await perform(actions)
    }

    private func perform(_ actions: [LinkAction]) async {
        for action in actions {
            switch action {
            case .publish(let state):
                stateContinuation.yield(state)
                await didPublish(state)
            case .kill:
                killProcess()
            case .scheduleRetry(let at):
                scheduleRetry(at: at)
            case .mintTicket:
                engine.attempt += 1
                let attempt = engine.attempt
                let failure = await prepareAndMint()
                guard attempt == engine.attempt else { return }   // stopped, offline or superseded meanwhile
                if let failure {
                    await feed(.mintFailed(code: failure))
                    return
                }
            case .spawn:
                await spawnProcess()
            }
        }
    }

    private func spawnProcess() async {
        engine.processGeneration += 1
        let generation = engine.processGeneration
        let (args, env) = spawnCommand()
        let (events, sink) = AsyncStream.makeStream(of: SidecarEvent.self)
        do {
            engine.handle = try launcher.launch(cmuxTui, args, env: env,
                                                onLine: { sink.yield(.line($0)) },
                                                onExit: { sink.yield(.exit($0)); sink.finish() })
            engine.processAlive = true
        } catch {
            sink.finish()
            engine.handle = nil
            engine.processAlive = false
            await feed(.exited(status: -1))
            return
        }
        // One ordered consumer per process: lines and the exit arrive in the order the launcher saw them.
        engine.processTask = Task { [weak self] in
            for await event in events { await self?.processEvent(event, generation: generation) }
        }
        didSpawn(generation: generation)
    }

    func isCurrentProcess(_ generation: Int) -> Bool {
        generation == engine.processGeneration && engine.processAlive
    }

    private func processEvent(_ event: SidecarEvent, generation: Int) async {
        guard isCurrentProcess(generation) else { return }
        switch event {
        case .line(let line):
            if let linkEvent = self.event(forLine: line) { await feed(linkEvent) }
        case .exit(let status):
            engine.processAlive = false
            engine.handle = nil
            engine.probeTask?.cancel()
            engine.probeTask = nil
            await feed(.exited(status: status))
        }
    }

    /// Terminates the current process (if any) and drops every pending timer and mint.
    func killProcess() {
        engine.attempt += 1
        engine.processGeneration += 1
        engine.processAlive = false
        engine.handle?.terminate()
        engine.handle = nil
        engine.probeTask?.cancel()
        engine.probeTask = nil
        cancelRetry()
    }

    /// The current process failed without exiting (e.g. the daemon never answered): end it and
    /// report an exit so the state machine schedules the retry.
    func abandonProcess(generation: Int, status: Int32) async {
        guard isCurrentProcess(generation) else { return }
        engine.processGeneration += 1
        engine.processAlive = false
        engine.handle?.terminate()
        engine.handle = nil
        engine.probeTask = nil
        await feed(.exited(status: status))
    }

    private func scheduleRetry(at deadline: Date) {
        cancelRetry()
        let generation = engine.retryGeneration
        let clock = self.clock
        engine.retryTask = Task { [weak self] in
            do { try await clock.sleep(until: deadline) } catch { return }
            await self?.retryFired(generation: generation)
        }
    }

    private func cancelRetry() {
        engine.retryGeneration += 1
        engine.retryTask?.cancel()
        engine.retryTask = nil
    }

    private func retryFired(generation: Int) async {
        guard generation == engine.retryGeneration else { return }
        engine.retryGeneration += 1
        engine.retryTask = nil
        await feed(.retryDue)
    }
}
