import Foundation
import CmuxSettings

enum WorkspaceSetStoreError: Error, Equatable {
    case blankName
    case duplicateName(String)
    case notFound(String)
    case corruptFile(String)
}

/// Reads and writes `workspace-sets.json` next to the user config, with the
/// same rules as ``SavedLayoutStore``: names match case-insensitively, and a
/// file that does not decode is never overwritten.
@MainActor
final class WorkspaceSetStore {
    struct SetsFile: Codable, Sendable {
        var sets: [CmuxWorkspaceSet]
    }

    private struct CachedSetsFile: Sendable {
        var modificationDate: Date?
        var file: SetsFile
    }

    let fileURL: URL

    private let fileManager: FileManager
    private var corruptFileDescription: String?
    private static var sharedCacheByPath: [String: CachedSetsFile] = [:]

    init(
        fileURL: URL = CmuxConfigLocation().userConfigFile
            .deletingLastPathComponent()
            .appendingPathComponent("workspace-sets.json", isDirectory: false),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func list() throws -> [CmuxWorkspaceSet] {
        try load().sets
    }

    func set(named name: String) throws -> CmuxWorkspaceSet? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return nil }
        return try load().sets.first { $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame }
    }

    func save(_ workspaceSet: CmuxWorkspaceSet, overwrite: Bool) throws {
        let normalizedName = workspaceSet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw WorkspaceSetStoreError.blankName
        }

        var file = try load()
        let replacement = CmuxWorkspaceSet(name: normalizedName, workspaces: workspaceSet.workspaces)
        if let index = file.sets.firstIndex(where: { $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame }) {
            guard overwrite else {
                throw WorkspaceSetStoreError.duplicateName(normalizedName)
            }
            file.sets[index] = replacement
        } else {
            file.sets.append(replacement)
        }
        try write(file)
    }

    func delete(named name: String) throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw WorkspaceSetStoreError.blankName
        }
        var file = try load()
        guard let index = file.sets.firstIndex(where: { $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame }) else {
            throw WorkspaceSetStoreError.notFound(normalizedName)
        }
        file.sets.remove(at: index)
        try write(file)
    }

    private func load() throws -> SetsFile {
        // A missing file is the empty state, also after a corrupt file was
        // deleted, so check it before the corrupt short-circuit.
        guard fileManager.fileExists(atPath: fileURL.path) else {
            let empty = SetsFile(sets: [])
            Self.sharedCacheByPath[cacheKey] = CachedSetsFile(modificationDate: nil, file: empty)
            corruptFileDescription = nil
            return empty
        }

        let modificationDate = self.modificationDate()
        if let corruptFileDescription,
           Self.sharedCacheByPath[cacheKey]?.modificationDate == modificationDate {
            throw WorkspaceSetStoreError.corruptFile(corruptFileDescription)
        }

        if let cached = Self.sharedCacheByPath[cacheKey],
           cached.modificationDate == modificationDate {
            return cached.file
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(SetsFile.self, from: data)
            Self.sharedCacheByPath[cacheKey] = CachedSetsFile(modificationDate: modificationDate, file: decoded)
            corruptFileDescription = nil
            return decoded
        } catch {
            let description = error.localizedDescription
            corruptFileDescription = description
            throw WorkspaceSetStoreError.corruptFile(description)
        }
    }

    private func write(_ file: SetsFile) throws {
        if let corruptFileDescription {
            throw WorkspaceSetStoreError.corruptFile(corruptFileDescription)
        }

        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(file)
        let temporaryURL = directoryURL.appendingPathComponent(".\(fileURL.lastPathComponent).tmp-\(UUID().uuidString)", isDirectory: false)
        try data.write(to: temporaryURL, options: .atomic)
        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: fileURL)
        }

        Self.sharedCacheByPath[cacheKey] = CachedSetsFile(modificationDate: modificationDate(), file: file)
        corruptFileDescription = nil
    }

    private func modificationDate() -> Date? {
        (try? fileManager.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date
    }

    private var cacheKey: String {
        fileURL.standardizedFileURL.path
    }
}
