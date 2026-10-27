import Foundation
import ShellXLinkAccount
import ShellXLinkCore

/// The account's secrets: the session, the phone's Link key and the paired Macs.
public actor AccountVault {
    private let store: any SecretStore

    public init(store: any SecretStore) {
        self.store = store
    }

    // MARK: Session

    public func session() throws -> StoredSession? {
        guard let data = try store.read(.session) else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    public func setSession(_ session: StoredSession) throws {
        try store.write(try JSONEncoder().encode(session), for: .session)
    }

    public func clearSession() throws {
        try store.delete(.session)
    }

    // MARK: Phone key

    /// The phone's Link static key, created on the first call and the same ever after. A store
    /// that cannot be read throws instead of getting a new key.
    public func phoneKey() throws -> NoiseStaticKey {
        if let data = try store.read(.phoneKey), let key = try? NoiseStaticKey(rawPrivate: data) {
            return key
        }
        let key = NoiseStaticKey()
        try store.write(key.rawPrivate, for: .phoneKey)
        return key
    }

    // MARK: Paired Macs

    private struct MachinesRecord: Codable {
        var version = 1
        var owner: String
        var machines: [PairedMachine]
    }

    public func machines() throws -> [PairedMachine] {
        try machinesRecord()?.machines ?? []
    }

    public func machinesOwner() throws -> String? {
        try machinesRecord()?.owner
    }

    public func setMachines(_ machines: [PairedMachine], owner: String) throws {
        let record = MachinesRecord(owner: owner, machines: machines)
        try store.write(try JSONEncoder().encode(record), for: .machines)
    }

    private func machinesRecord() throws -> MachinesRecord? {
        guard let data = try store.read(.machines) else { return nil }
        return try? JSONDecoder().decode(MachinesRecord.self, from: data)
    }

    // MARK: Wipe

    /// Deletes every item. Keeps going after a failure and rethrows the first one.
    public func wipe() throws {
        var first: Error?
        for item in SecretItem.allCases {
            do { try store.delete(item) } catch { first = first ?? error }
        }
        if let first { throw first }
    }
}
