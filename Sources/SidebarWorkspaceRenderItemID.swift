import Foundation

/// Stable, allocation-free identity for a `SidebarWorkspaceRenderItem`.
///
/// `ForEach` gathers row identifiers on every list diff, so the id must be
/// cheap to create and hash. Keep the discriminator as a byte so SwiftUI's
/// per-scroll list diff avoids enum-payload hash/equality witnesses.
struct SidebarWorkspaceRenderItemID: Hashable {
    private let kind: UInt8
    private let uuid: UUID
    // ShellX: set only on a group header repeated in a second machine section (W1 Task 10).
    private var machineSection: UUID? = nil

    static func group(_ uuid: UUID) -> Self {
        Self(kind: 1, uuid: uuid)
    }

    static func workspace(_ uuid: UUID) -> Self {
        Self(kind: 2, uuid: uuid)
    }

    // ShellX: machine-grouped sidebar rows (W1 Task 10).
    /// A machine section header row; `uuid` is `SidebarMachineKey.stableID`.
    static func machine(_ uuid: UUID) -> Self {
        Self(kind: 3, uuid: uuid)
    }

    /// The same group header shown again inside another machine section. The
    /// first appearance keeps `.group(_:)`; each repeat is keyed by its section
    /// so NSTableView diffing never sees duplicate row ids.
    static func group(_ uuid: UUID, repeatedInMachineSection section: UUID) -> Self {
        Self(kind: 1, uuid: uuid, machineSection: section)
    }

    static let shellXBrandHeaderUUID = UUID(uuid: (
        0x53, 0x68, 0x65, 0x6C, 0x6C, 0x58, 0x80, 0x00,
        0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
    ))

    /// The ShellX brand header row at the top of the sidebar.
    static let shellXBrandHeader = Self(kind: 4, uuid: shellXBrandHeaderUUID)

    // ShellX: the remote sign-in row under "YOUR MACHINES" (W2 Task U1).
    static let shellXSignInRowUUID = UUID(uuid: (
        0x53, 0x68, 0x65, 0x6C, 0x6C, 0x58, 0x80, 0x00,
        0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02
    ))

    static let shellXSignInRow = Self(kind: 5, uuid: shellXSignInRowUUID)

    /// Returns the durable group identifier when this row represents a group.
    /// Workspace rows return `nil`; callers should use their row-specific
    /// fallback identity for those rows.
    var groupId: UUID? {
        kind == 1 ? uuid : nil
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.uuid == rhs.uuid
            && lhs.machineSection == rhs.machineSection // ShellX
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(uuid)
        if let machineSection { hasher.combine(machineSection) } // ShellX
    }
}
