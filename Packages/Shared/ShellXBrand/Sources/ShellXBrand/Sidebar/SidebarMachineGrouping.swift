import Darwin
import Foundation
import IOKit.ps
import SystemConfiguration

/// Which machine a sidebar section stands for.
///
/// Wave 2 adds `case remote(machineID: String)` for devices paired through the
/// ShellX server; callers should not switch on this exhaustively from outside
/// the package without expecting that case.
public enum SidebarMachineKey: Hashable, Sendable {
    case local
    /// `target` is the workspace's `remoteDisplayTarget`, e.g. "ubuntu@vm01".
    case ssh(target: String)

    /// Deterministic identity for list diffing: the same key gives the same
    /// UUID in every launch, different keys give different UUIDs.
    public var stableID: UUID {
        let seed: String
        switch self {
        case .local:
            seed = "shellx.machine.local"
        case .ssh(let target):
            seed = "shellx.machine.ssh:" + target
        }
        let bytes = Array(seed.utf8)
        let high = Self.fnv1a64(bytes, basis: 0xcbf2_9ce4_8422_2325)
        let low = Self.fnv1a64(bytes, basis: 0x84222325_cbf29ce4)
        var uuid = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            uuid[index] = UInt8(truncatingIfNeeded: high >> (56 - 8 * UInt64(index)))
            uuid[8 + index] = UInt8(truncatingIfNeeded: low >> (56 - 8 * UInt64(index)))
        }
        // RFC 4122 version 8 (custom) / variant 1, so the value is a valid UUID.
        uuid[6] = (uuid[6] & 0x0F) | 0x80
        uuid[8] = (uuid[8] & 0x3F) | 0x80
        return UUID(uuid: (
            uuid[0], uuid[1], uuid[2], uuid[3], uuid[4], uuid[5], uuid[6], uuid[7],
            uuid[8], uuid[9], uuid[10], uuid[11], uuid[12], uuid[13], uuid[14], uuid[15]
        ))
    }

    private static func fnv1a64(_ bytes: [UInt8], basis: UInt64) -> UInt64 {
        var hash = basis
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}

/// The Mac ShellX runs on.
public struct LocalMachineInfo: Equatable, Sendable {
    public let name: String
    public let isLaptop: Bool

    public init(name: String, isLaptop: Bool) {
        self.name = name
        self.isLaptop = isLaptop
    }

    /// The current Mac, probed once per process. The name is the Sharing
    /// computer name (what `Host.current().localizedName` reports), read from
    /// SystemConfiguration first because `Host.current()` can block on name
    /// resolution.
    public static func current() -> LocalMachineInfo {
        cachedCurrent
    }

    /// `hw.model` names Intel laptops "MacBook…"; Apple silicon reports
    /// "Mac14,7" for a MacBook Pro too, so an internal battery also counts.
    public static func isLaptop(hardwareModel: String, hasInternalBattery: Bool) -> Bool {
        hardwareModel.contains("MacBook") || hasInternalBattery
    }

    private static let cachedCurrent: LocalMachineInfo = {
        let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String?
        let localized = (computerName ?? Host.current().localizedName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (localized?.isEmpty == false ? localized : nil)
            ?? ProcessInfo.processInfo.hostName
        return LocalMachineInfo(
            name: name.isEmpty ? "Mac" : name,
            isLaptop: isLaptop(
                hardwareModel: hardwareModel(),
                hasInternalBattery: hasInternalBattery()
            )
        )
    }()

    private static func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "" }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func hasInternalBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                return true
            }
        }
        return false
    }
}

/// One workspace as the machine grouping sees it.
public struct SidebarMachineInput<ID: Hashable & Sendable>: Equatable, Sendable {
    public let workspaceID: ID
    /// The workspace's SSH target; nil (or blank) for a local workspace.
    public let sshTarget: String?
    public let sshConnected: Bool

    public init(workspaceID: ID, sshTarget: String?, sshConnected: Bool) {
        self.workspaceID = workspaceID
        self.sshTarget = sshTarget
        self.sshConnected = sshConnected
    }
}

/// Localized header notes, injected so this model stays free of bundles.
public struct SidebarMachineLabels: Equatable, Sendable {
    public let thisMac: String
    public let ssh: String

    public init(thisMac: String, ssh: String) {
        self.thisMac = thisMac
        self.ssh = ssh
    }

    public static let english = SidebarMachineLabels(thisMac: "this Mac", ssh: "SSH")
}

/// What a machine section header shows: "MacBook Pro · this Mac".
public struct SidebarMachineHeaderModel: Hashable, Sendable {
    public let key: SidebarMachineKey
    public let title: String
    public let note: String
    /// coolicons name: "Laptop", "Desktop" or "Data".
    public let coolicon: String
    public let isOnline: Bool

    public init(key: SidebarMachineKey, title: String, note: String, coolicon: String, isOnline: Bool) {
        self.key = key
        self.title = title
        self.note = note
        self.coolicon = coolicon
        self.isOnline = isOnline
    }
}

public struct SidebarMachineSection<ID: Hashable & Sendable>: Equatable, Sendable {
    public let header: SidebarMachineHeaderModel
    /// Workspaces on this machine, in their sidebar order.
    public let workspaceIDs: [ID]

    public init(header: SidebarMachineHeaderModel, workspaceIDs: [ID]) {
        self.header = header
        self.workspaceIDs = workspaceIDs
    }
}

public enum SidebarMachineGrouping {
    public static let localCoolicon = "Laptop"
    public static let desktopCoolicon = "Desktop"
    public static let sshCoolicon = "Data"

    /// Splits workspaces by machine. The local section always comes first,
    /// even when it has no workspaces; SSH machines follow in the order their
    /// first workspace appears. `user@host` is the machine identity, so two
    /// users on one host are two machines. A disconnected SSH machine keeps
    /// its rows and reports `isOnline == false`.
    public static func sections<ID: Hashable & Sendable>(
        for inputs: [SidebarMachineInput<ID>],
        local: LocalMachineInfo,
        labels: SidebarMachineLabels = .english
    ) -> [SidebarMachineSection<ID>] {
        var localIDs: [ID] = []
        var sshOrder: [String] = []
        var sshIDs: [String: [ID]] = [:]
        var sshOnline: [String: Bool] = [:]
        for input in inputs {
            guard let target = normalizedTarget(input.sshTarget) else {
                localIDs.append(input.workspaceID)
                continue
            }
            if sshIDs[target] == nil {
                sshOrder.append(target)
            }
            sshIDs[target, default: []].append(input.workspaceID)
            sshOnline[target] = (sshOnline[target] ?? false) || input.sshConnected
        }
        let localHeader = SidebarMachineHeaderModel(
            key: .local,
            title: local.name,
            note: labels.thisMac,
            coolicon: local.isLaptop ? localCoolicon : desktopCoolicon,
            isOnline: true
        )
        var result = [SidebarMachineSection(header: localHeader, workspaceIDs: localIDs)]
        result.reserveCapacity(1 + sshOrder.count)
        for target in sshOrder {
            let header = SidebarMachineHeaderModel(
                key: .ssh(target: target),
                title: target,
                note: labels.ssh,
                coolicon: sshCoolicon,
                isOnline: sshOnline[target] ?? false
            )
            result.append(SidebarMachineSection(header: header, workspaceIDs: sshIDs[target] ?? []))
        }
        return result
    }

    private static func normalizedTarget(_ target: String?) -> String? {
        guard let trimmed = target?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
