import Foundation

public enum LinkState: Equatable, Sendable {
    case idle, connecting, connected(localSocket: String)
    case reconnecting(attempt: Int, retryAt: Date), offline(lastSeen: Date?), failed(code: String)
}

public struct RemoteMachine: Identifiable, Equatable, Sendable {
    public typealias ID = String
    public enum Platform: String, Sendable { case macos, windows }
    public enum Access: Equatable, Sendable { case none, requested(pairingID: String, code: String), granted }
    public let id: ID
    public var name: String
    public var platform: Platform
    public var online: Bool
    public var lastSeen: Date?
    public var fingerprint: String
    public var isThisMachine: Bool
    public var access: Access
    public var link: LinkState

    public init(id: ID, name: String, platform: Platform, online: Bool, lastSeen: Date?, fingerprint: String,
                isThisMachine: Bool, access: Access, link: LinkState) {
        self.id = id; self.name = name; self.platform = platform; self.online = online; self.lastSeen = lastSeen
        self.fingerprint = fingerprint; self.isThisMachine = isThisMachine; self.access = access; self.link = link
    }
}

/// Incoming pairing request, shown on the target side.
public struct PairingRequest: Identifiable, Equatable, Sendable {
    public typealias ID = String
    public let id: ID
    public let fromMachineID: RemoteMachine.ID
    public let requesterName: String
    public let code: String
    public let fingerprint: String
    public let suspicious: Bool
    public let firstSeen: Date
    public var expiresAt: Date { firstSeen.addingTimeInterval(300) }

    public init(id: ID, fromMachineID: RemoteMachine.ID, requesterName: String, code: String,
                fingerprint: String, suspicious: Bool, firstSeen: Date) {
        self.id = id; self.fromMachineID = fromMachineID; self.requesterName = requesterName; self.code = code
        self.fingerprint = fingerprint; self.suspicious = suspicious; self.firstSeen = firstSeen
    }
}

/// Pairing this machine asked for, shown on the requester side.
public struct OutgoingPairing: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable { case waiting, approved, denied, expired, failed(code: String) }
    public let id: String
    public let toMachineID: RemoteMachine.ID
    public let code: String
    public let ownFingerprint: String
    public var status: Status
    public let createdAt: Date

    public init(id: String, toMachineID: RemoteMachine.ID, code: String, ownFingerprint: String,
                status: Status, createdAt: Date) {
        self.id = id; self.toMachineID = toMachineID; self.code = code; self.ownFingerprint = ownFingerprint
        self.status = status; self.createdAt = createdAt
    }
}
