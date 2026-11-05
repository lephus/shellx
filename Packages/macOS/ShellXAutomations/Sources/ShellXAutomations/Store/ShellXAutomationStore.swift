public import Foundation

/// Reads and writes automations, skills and run history on disk.
///
/// Skills live in `skillsRoot/<name>/` (with a `.shellx.json` marker when ShellX made them);
/// cronjobs and workflows live in `automationsRoot/<id>/`. Every mutation ends by touching the change stamp.
public actor ShellXAutomationStore {
    /// Runs kept per automation.
    public static let retainedRuns = 30
    /// Reason reported for a `running` run whose process is gone.
    public static let interruptedReason = "The run was interrupted."

    private let environment: ShellXAutomationEnvironment
    private let fileManager: FileManager
    private let trasher: any ShellXTrashing
    private let now: @Sendable () -> Date
    private var heldLocks: [String: Int32] = [:]

    /// Creates a store over `environment`'s folders.
    public init(
        environment: ShellXAutomationEnvironment,
        fileManager: FileManager = .default,
        trasher: any ShellXTrashing,
        now: @escaping @Sendable () -> Date
    ) {
        self.environment = environment
        self.fileManager = fileManager
        self.trasher = trasher
        self.now = now
    }

    // MARK: - Reading

    /// Every automation and skill, sorted by name.
    public func list() throws -> [ShellXAutomation] {
        var result: [ShellXAutomation] = []
        for dir in subdirectories(of: environment.automationsRoot) {
            if let automation = try? loadAutomation(in: dir) { result.append(automation) }
        }
        for dir in subdirectories(of: environment.skillsRoot) {
            if let skill = loadSkill(in: dir) { result.append(skill) }
        }
        return result.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    /// The automation with `id`, if any.
    public func automation(id: String) throws -> ShellXAutomation? {
        guard let location = try locate(id: id) else { return nil }
        switch location {
        case .automation(let dir): return try loadAutomation(in: dir)
        case .skill(let dir, _): return loadSkill(in: dir)
        }
    }

    /// The automation or skill called `named`, if any.
    public func automation(named name: String) throws -> ShellXAutomation? {
        try list().first { $0.name == name }
    }

    // MARK: - Writing

    /// Saves `draft`, creating a new automation or replacing `id`. Does not validate; refuses names that would leave the roots.
    public func save(_ draft: ShellXAutomationDraft, replacing id: String?) throws -> ShellXAutomation {
        guard Self.isSafeName(draft.name) else { throw ShellXAutomationStoreError.invalidName(draft.name) }
        let existing = try id.map { id -> (Location, ShellXAutomation) in
            guard let location = try locate(id: id), let old = try automation(id: id) else {
                throw ShellXAutomationStoreError.notFound(id)
            }
            // A skill ShellX did not create stays a skill and stays theirs: only its SKILL.md changes.
            if old.origin == .external, draft.kind != .skill { throw ShellXAutomationStoreError.unsupported(id) }
            return (location, old)
        }
        let isExternal = existing?.1.origin == .external
        let stamp = now()
        let createdAt = existing?.1.createdAt ?? stamp
        let enabled = existing?.1.enabled ?? true
        let ownID = existing?.1.id ?? UUID().uuidString

        let target: URL
        if isExternal, let old = existing?.1, draft.name == old.name {
            // Its folder may be named apart from its frontmatter name; only a new name moves it.
            target = old.directory
        } else if draft.kind == .skill {
            target = environment.skillsRoot.appending(path: draft.name, directoryHint: .isDirectory)
        } else {
            target = environment.automationsRoot.appending(path: ownID, directoryHint: .isDirectory)
        }
        let newID = isExternal ? Self.externalPrefix + target.lastPathComponent : ownID
        let oldDirectory = existing?.1.directory
        let isSameFolder = oldDirectory?.standardizedFileURL == target.standardizedFileURL
        if !isSameFolder, fileManager.fileExists(atPath: target.path) {
            throw ShellXAutomationStoreError.alreadyExists(draft.name)
        }

        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if isSameFolder {
            try writeFiles(of: draft, into: target, id: newID, createdAt: createdAt, updatedAt: stamp, enabled: enabled, external: isExternal)
        } else {
            // The new content is complete in a hidden staging folder before anything old is touched;
            // on any failure the staging folder goes and the old folder stays as it was.
            let staging = target.deletingLastPathComponent()
                .appending(path: ".\(target.lastPathComponent).saving-\(UUID().uuidString)", directoryHint: .isDirectory)
            let sameStore = (existing?.1.kind == .skill) == (draft.kind == .skill)
            do {
                if let oldDirectory, sameStore {
                    // Same store: keep the folder's other files (references/, scripts/, assets/).
                    try fileManager.copyItem(at: oldDirectory, to: staging)
                } else {
                    try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
                }
                try writeFiles(
                    of: draft, into: staging, id: newID, createdAt: createdAt, updatedAt: stamp, enabled: enabled, external: isExternal
                )
                try fileManager.moveItem(at: staging, to: target)
            } catch {
                try? fileManager.removeItem(at: staging)
                throw error
            }
            if let oldDirectory {
                // A renamed folder was copied whole, so the old one goes; a folder of the other store is trashed.
                if sameStore {
                    try fileManager.removeItem(at: oldDirectory)
                } else {
                    try trasher.trash(oldDirectory)
                }
            }
        }
        try touchChangeStamp()
        guard let saved = try automation(id: newID) else { throw ShellXAutomationStoreError.notFound(newID) }
        return saved
    }

    /// Turns a cronjob or workflow on or off.
    public func setEnabled(id: String, _ enabled: Bool) throws -> ShellXAutomation {
        guard case .automation(let dir)? = try locate(id: id) else {
            if try locate(id: id) == nil { throw ShellXAutomationStoreError.notFound(id) }
            throw ShellXAutomationStoreError.unsupported(id)
        }
        var automation = try loadAutomation(in: dir)
        automation.enabled = enabled
        automation.updatedAt = now()
        try encoder().encode(automation).write(to: dir.appending(path: "automation.json"), options: .atomic)
        try touchChangeStamp()
        return try loadAutomation(in: dir)
    }

    /// Moves the automation's (or skill's) folder to the Trash.
    public func delete(id: String) throws {
        guard let location = try locate(id: id) else { throw ShellXAutomationStoreError.notFound(id) }
        switch location {
        case .automation(let dir), .skill(let dir, _): try trasher.trash(dir)
        }
        try removeFlow(id: id)
        try touchChangeStamp()
    }

    // MARK: - Flows

    /// The cached flow for an automation or skill, or `nil` when none is stored or the file is unreadable.
    public func flowRecord(id: String) throws -> ShellXFlowRecord? {
        let url = flowURL(id: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder().decode(ShellXFlowRecord.self, from: data)
    }

    /// Stores a flow under `automationsRoot/.flows`, never inside a skill folder.
    public func saveFlow(_ record: ShellXFlowRecord, id: String) throws {
        let url = flowURL(id: id)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder().encode(record).write(to: url, options: .atomic)
    }

    /// Removes a stored flow; a missing file is not an error.
    public func removeFlow(id: String) throws {
        let url = flowURL(id: id)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    /// Classifies a stored flow against the current `SKILL.md`; the flow is returned only when current.
    public nonisolated static func flowStatus(
        kind: ShellXAutomationKind, record: ShellXFlowRecord?, skillMarkdown: String
    ) -> (status: ShellXFlowStatus, flow: ShellXAutomationFlow?) {
        if kind == .workflow { return (.derived, nil) }
        guard let record, record.flow.isUsable else { return (.missing, nil) }
        guard record.sourceHash == ShellXFlowFingerprint.of(skillMarkdown) else { return (.stale, nil) }
        return (.current, record.flow)
    }

    /// `<id>.json` for a safe id, otherwise `_` plus the hex of the id's UTF-8 bytes (`_` is never in a safe id).
    func flowURL(id: String) -> URL {
        let name = Self.isSafeID(id) ? id : "_" + id.utf8.map { String(format: "%02x", $0) }.joined()
        return environment.automationsRoot.appending(path: ".flows/\(name).json")
    }

    // MARK: - Runs

    /// Starts a run: takes an exclusive `flock` on `run.lock` and creates a `running` run directory.
    /// Returns `nil` when another open file description (this or another process) holds the lock.
    /// The kernel drops the lock when the holder exits, so a crashed run never blocks the next one.
    public func beginRun(id: String, trigger: ShellXRunTrigger, pid: Int32) throws -> URL? {
        let dir = try automationDirectory(id: id)
        let lockPath = dir.appending(path: "run.lock").path
        let fd = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let reason = errno
            close(fd)
            if reason == EWOULDBLOCK { return nil }
            throw CocoaError(.fileLocking)
        }
        let runDirectory: URL
        do {
            let bytes = Array("\(pid)\n".utf8)
            guard ftruncate(fd, 0) == 0,
                  bytes.withUnsafeBufferPointer({ write(fd, $0.baseAddress, $0.count) }) == bytes.count else {
                throw CocoaError(.fileWriteUnknown)
            }
            let started = now()
            let runs = dir.appending(path: "runs", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: runs, withIntermediateDirectories: true)
            runDirectory = try makeRunDirectory(in: runs, at: started)
            let record = ShellXRunRecord(status: .running, trigger: trigger, startedAt: started, unread: false)
            try encoder().encode(record).write(to: runDirectory.appending(path: "result.json"), options: .atomic)
        } catch {
            flock(fd, LOCK_UN)
            close(fd)
            throw error
        }
        heldLocks[id] = fd
        // Watchers show the run as running right away.
        try? touchChangeStamp()
        return runDirectory
    }

    /// The lock descriptor held for `id`, for tests.
    func heldLockDescriptor(for id: String) -> Int32? { heldLocks[id] }

    /// Records the final `record` for a run, releases the lock this store holds for `id` and prunes old runs.
    /// `pid` identifies the run for the caller; the lock itself is tied to the open file, never to the pid.
    public func finishRun(id: String, runDirectory: URL, record: ShellXRunRecord, pid: Int32) throws {
        defer {
            if let fd = heldLocks.removeValue(forKey: id) {
                flock(fd, LOCK_UN)
                close(fd)
            }
        }
        let dir = try automationDirectory(id: id)
        let runs = dir.appending(path: "runs", directoryHint: .isDirectory)
        guard Self.isPlainRunName(runDirectory.lastPathComponent),
              runDirectory.deletingLastPathComponent().standardizedFileURL == runs.standardizedFileURL else {
            throw ShellXAutomationStoreError.foreignRunDirectory
        }
        try encoder().encode(record).write(to: runDirectory.appending(path: "result.json"), options: .atomic)
        let names = runDirectoryNames(in: runs)
        for name in names.dropFirst(Self.retainedRuns) {
            try? fileManager.removeItem(at: runs.appending(path: name))
        }
        try touchChangeStamp()
    }

    /// Rewrites a running run's `result.json` with its workflow progress; the status stays as recorded.
    /// Uses the same run-directory validation as ``finishRun(id:runDirectory:record:pid:)``.
    public func updateRunProgress(id: String, runDirectory: URL, currentStep: Int, totalSteps: Int) throws {
        let dir = try automationDirectory(id: id)
        let runs = dir.appending(path: "runs", directoryHint: .isDirectory)
        guard Self.isPlainRunName(runDirectory.lastPathComponent),
              runDirectory.deletingLastPathComponent().standardizedFileURL == runs.standardizedFileURL else {
            throw ShellXAutomationStoreError.foreignRunDirectory
        }
        let file = runDirectory.appending(path: "result.json")
        var record = try decoder().decode(ShellXRunRecord.self, from: Data(contentsOf: file))
        record.currentStep = currentStep
        record.totalSteps = totalSteps
        try encoder().encode(record).write(to: file, options: .atomic)
        try touchChangeStamp()
    }

    /// Recorded runs, newest first.
    public func runs(id: String, limit: Int) throws -> [ShellXRunRecord] {
        guard case .automation(let dir)? = try locate(id: id) else { return [] }
        return recordedRuns(in: dir, limit: limit)
    }

    /// Marks the newest run as seen.
    public func markRead(id: String) throws {
        guard case .automation(let dir)? = try locate(id: id) else { return }
        let runs = dir.appending(path: "runs", directoryHint: .isDirectory)
        guard let newest = runDirectoryNames(in: runs).first else { return }
        let file = runs.appending(path: newest).appending(path: "result.json")
        guard var record = try? decoder().decode(ShellXRunRecord.self, from: Data(contentsOf: file)), record.unread else { return }
        record.unread = false
        try encoder().encode(record).write(to: file, options: .atomic)
        try touchChangeStamp()
    }

    /// Replaces the change stamp so watchers notice a change.
    public func touchChangeStamp() throws {
        try fileManager.createDirectory(at: environment.automationsRoot, withIntermediateDirectories: true)
        let text = ISO8601DateFormatter().string(from: now()) + "\n"
        try Data(text.utf8).write(to: environment.changeStampURL, options: .atomic)
    }
}

// MARK: - Helpers

private extension ShellXAutomationStore {
    enum Location {
        case automation(URL)
        case skill(URL, external: Bool)
    }

    static let externalPrefix = "external:"

    static func isSafeName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64 else { return false }
        return name.split(separator: "-", omittingEmptySubsequences: false).allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { ($0.value >= 0x61 && $0.value <= 0x7A) || ($0.value >= 0x30 && $0.value <= 0x39) }
        }
    }

    static func isPlainRunName(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { ($0.value >= 0x30 && $0.value <= 0x39) || $0 == "-" }
    }

    static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func subdirectories(of root: URL) -> [URL] {
        let entries = (try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func locate(id: String) throws -> Location? {
        if id.hasPrefix(Self.externalPrefix) {
            let name = String(id.dropFirst(Self.externalPrefix.count))
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
                throw ShellXAutomationStoreError.invalidID(id)
            }
            let dir = environment.skillsRoot.appending(path: name, directoryHint: .isDirectory)
            guard fileManager.fileExists(atPath: dir.appending(path: "SKILL.md").path) else { return nil }
            return .skill(dir, external: true)
        }
        guard Self.isSafeID(id) else { throw ShellXAutomationStoreError.invalidID(id) }
        let dir = environment.automationsRoot.appending(path: id, directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: dir.appending(path: "automation.json").path) { return .automation(dir) }
        for skillDir in subdirectories(of: environment.skillsRoot) {
            if let marker = readMarker(in: skillDir), marker.id == id { return .skill(skillDir, external: false) }
        }
        return nil
    }

    func automationDirectory(id: String) throws -> URL {
        guard let location = try locate(id: id) else { throw ShellXAutomationStoreError.notFound(id) }
        guard case .automation(let dir) = location else { throw ShellXAutomationStoreError.unsupported(id) }
        return dir
    }

    /// Writes `SKILL.md` and the marker or `automation.json` for `draft` into `folder`.
    /// A skill ShellX did not create (`external`) gets only its `SKILL.md`, so it is not adopted.
    func writeFiles(
        of draft: ShellXAutomationDraft,
        into folder: URL,
        id: String,
        createdAt: Date,
        updatedAt: Date,
        enabled: Bool,
        external: Bool = false
    ) throws {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(draft.skillMarkdown.utf8).write(to: folder.appending(path: "SKILL.md"), options: .atomic)
        if external { return }
        if draft.kind == .skill {
            let marker = ShellXSkillMarker(
                id: id, notify: draft.notify, createdAt: createdAt, updatedAt: updatedAt,
                bundleIdentifier: environment.bundleIdentifier
            )
            try encoder().encode(marker).write(to: folder.appending(path: ".shellx.json"), options: .atomic)
            try? fileManager.removeItem(at: folder.appending(path: "automation.json"))
        } else {
            // `directory` is never encoded; the store assigns it when it reads the file.
            let automation = ShellXAutomation(
                id: id, kind: draft.kind, name: draft.name, description: draft.description,
                schedule: draft.schedule, workingDirectory: draft.workingDirectory, notify: draft.notify,
                allowedTools: draft.allowedTools, steps: draft.steps, enabled: enabled, origin: .shellx,
                createdAt: createdAt, updatedAt: updatedAt, directory: folder
            )
            try encoder().encode(automation).write(to: folder.appending(path: "automation.json"), options: .atomic)
            try? fileManager.removeItem(at: folder.appending(path: ".shellx.json"))
        }
    }

    func readMarker(in dir: URL) -> ShellXSkillMarker? {
        guard let data = try? Data(contentsOf: dir.appending(path: ".shellx.json")) else { return nil }
        return try? decoder().decode(ShellXSkillMarker.self, from: data)
    }

    func loadAutomation(in dir: URL) throws -> ShellXAutomation {
        var automation = try decoder().decode(ShellXAutomation.self, from: Data(contentsOf: dir.appending(path: "automation.json")))
        automation.directory = dir
        automation.lastRun = recordedRuns(in: dir, limit: 1).first
        return automation
    }

    func loadSkill(in dir: URL) -> ShellXAutomation? {
        guard let markdown = try? String(contentsOf: dir.appending(path: "SKILL.md"), encoding: .utf8) else { return nil }
        let folder = dir.lastPathComponent
        let frontmatter = try? ShellXSkillFrontmatter(markdown: markdown)
        let description = frontmatter?.description ?? ""
        if let marker = readMarker(in: dir) {
            return ShellXAutomation(
                id: marker.id, kind: .skill, name: folder, description: description, notify: marker.notify,
                origin: .shellx, createdAt: marker.createdAt, updatedAt: marker.updatedAt, directory: dir
            )
        }
        let modified = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now()
        return ShellXAutomation(
            id: Self.externalPrefix + folder, kind: .skill, name: frontmatter?.name ?? folder, description: description,
            notify: ShellXNotifySettings(on: [], targets: []), origin: .external,
            createdAt: modified, updatedAt: modified, directory: dir
        )
    }

    func runDirectoryNames(in runs: URL) -> [String] {
        ((try? fileManager.contentsOfDirectory(atPath: runs.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted(by: >)
    }

    /// Recorded runs in `dir`, newest first.
    ///
    /// A `running` record is reported as failed with ``interruptedReason`` when its run cannot still be going:
    /// it is not the newest run, or nobody holds `run.lock` (the CLI was killed after `beginRun`, for example by a
    /// logout or reboot). The record on disk is left as it is.
    func recordedRuns(in dir: URL, limit: Int) -> [ShellXRunRecord] {
        let runs = dir.appending(path: "runs", directoryHint: .isDirectory)
        var records: [ShellXRunRecord] = []
        for (index, name) in runDirectoryNames(in: runs).enumerated() {
            guard records.count < limit else { break }
            let file = runs.appending(path: name).appending(path: "result.json")
            if let data = try? Data(contentsOf: file), var record = try? decoder().decode(ShellXRunRecord.self, from: data) {
                if record.status == .running, index > 0 || !isRunLockHeld(in: dir) {
                    record.status = .failed
                    record.reason = Self.interruptedReason
                }
                records.append(record)
            }
        }
        return records
    }

    /// Whether a live run holds `dir/run.lock`: this store does, or another open file does.
    ///
    /// `flock` has no query, so the probe takes the lock without waiting and releases it at once. A run starting
    /// in that instant finds the lock taken and is skipped as if one were already going.
    func isRunLockHeld(in dir: URL) -> Bool {
        if heldLocks[dir.lastPathComponent] != nil { return true }
        let fd = open(dir.appending(path: "run.lock").path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return true }
        flock(fd, LOCK_UN)
        return false
    }

    func makeRunDirectory(in runs: URL, at date: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = formatter.string(from: date)
        var candidate = runs.appending(path: base, directoryHint: .isDirectory)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = runs.appending(path: "\(base)-\(suffix)", directoryHint: .isDirectory)
            suffix += 1
        }
        try fileManager.createDirectory(at: candidate, withIntermediateDirectories: false)
        return candidate
    }
}
