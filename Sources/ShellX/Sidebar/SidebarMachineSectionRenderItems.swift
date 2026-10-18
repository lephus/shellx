import CmuxCore
import CmuxWorkspaces
import Foundation
import ShellXBrand
import ShellXRemoteUI

extension SidebarMachineInput where ID == UUID {
    @MainActor
    init(workspace: Workspace, remoteMachineID: String? = nil) {
        self.init(
            workspaceID: workspace.id,
            sshTarget: workspace.remoteDisplayTarget,
            sshConnected: workspace.remoteConnectionState == .connected,
            remoteMachineID: remoteMachineID
        )
    }
}

extension SidebarMachineLabels {
    static var localized: SidebarMachineLabels {
        SidebarMachineLabels(
            thisMac: String(localized: "sidebar.machine.thisMac", defaultValue: "this Mac"),
            ssh: String(localized: "sidebar.machine.ssh", defaultValue: "SSH")
        )
    }
}

/// The sidebar render items grouped by machine: for each machine section, its
/// `.machineHeader`, then the existing `renderItems(...)` over only that
/// machine's workspaces. A workspace group spanning machines shows its header
/// in every section holding one of its rows, with only that section's rows.
@MainActor
enum SidebarMachineSectionRenderItems {
    /// Reads the live remote snapshot (nil while the remote UI is off), so
    /// ⌘1–9 numbering agrees with what the sidebar shows.
    static func renderItems(
        tabs: [Workspace],
        groupsById: [UUID: WorkspaceGroup],
        orderedGroups: [WorkspaceGroup]? = nil,
        effectiveMembership: [UUID: UUID?]? = nil,
        local: LocalMachineInfo = .current()
    ) -> [SidebarWorkspaceRenderItem] {
        renderItems(
            tabs: tabs,
            groupsById: groupsById,
            orderedGroups: orderedGroups,
            effectiveMembership: effectiveMembership,
            local: local,
            remote: ShellXRemoteUIModel.shared.snapshot
        )
    }

    /// `remote` nil (remote UI off) or signed out gives exactly the W1
    /// local + SSH sections. Signed in, the account's machines sit between
    /// them; workspaces attached to an offline machine are not listed.
    static func renderItems(
        tabs: [Workspace],
        groupsById: [UUID: WorkspaceGroup],
        orderedGroups: [WorkspaceGroup]?,
        effectiveMembership: [UUID: UUID?]?,
        local: LocalMachineInfo = .current(),
        remote: RemoteUISnapshot?
    ) -> [SidebarWorkspaceRenderItem] {
        let membership = effectiveMembership
            ?? SidebarWorkspaceRenderItem.effectiveGroupIdByWorkspaceId(tabs: tabs, groupsById: groupsById)
        let sections: [SidebarMachineSection<UUID>]
        if let remote, remote.isSignedIn {
            sections = SidebarMachineGrouping.sections(
                for: tabs.map {
                    SidebarMachineInput<UUID>(workspace: $0, remoteMachineID: remote.remoteMachineID(forWorkspace: $0.id))
                },
                local: local,
                remote: remote.machines,
                now: Date(),
                labels: .localized,
                remoteLabels: .localized
            )
        } else {
            sections = SidebarMachineGrouping.sections(
                for: tabs.map { SidebarMachineInput<UUID>(workspace: $0) },
                local: local,
                labels: .localized
            )
        }
        let tabsById = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        // Groups no section references (durable empty groups) stay with the
        // local section, which always comes first.
        let referencedGroupIds = Set(membership.values.compactMap { $0 })
        var items: [SidebarWorkspaceRenderItem] = []
        items.reserveCapacity(tabs.count + groupsById.count + sections.count)
        for (index, section) in sections.enumerated() {
            let sectionTabs = section.workspaceIDs.compactMap { tabsById[$0] }
            let sectionMembership = Dictionary(uniqueKeysWithValues: sectionTabs.map {
                ($0.id, membership[$0.id] ?? nil)
            })
            let sectionGroupIds = Set(sectionMembership.values.compactMap { $0 })
            let ownsUnreferencedGroups = index == 0
            let belongsToSection: (WorkspaceGroup) -> Bool = { group in
                sectionGroupIds.contains(group.id)
                    || (ownsUnreferencedGroups && !referencedGroupIds.contains(group.id))
            }
            items.append(.machineHeader(section.header))
            items.append(contentsOf: SidebarWorkspaceRenderItem.renderItems(
                tabs: sectionTabs,
                groupsById: groupsById.filter { belongsToSection($0.value) },
                orderedGroups: orderedGroups?.filter(belongsToSection),
                effectiveMembership: sectionMembership
            ))
        }
        return items
    }

    /// The table row id for each item, in order. A group header keeps
    /// `.group(id)` the first time it appears; each repeat in a later machine
    /// section is keyed by that section, so NSTableView never sees duplicates.
    static func rowIds(for items: [SidebarWorkspaceRenderItem]) -> [SidebarWorkspaceRenderItemID] {
        var emittedGroupIds: Set<UUID> = []
        var currentSectionId: UUID?
        return items.map { item -> SidebarWorkspaceRenderItemID in
            switch item {
            case .machineHeader(let header):
                currentSectionId = header.key.stableID
                return item.id
            case .groupHeader(let groupId, _):
                guard !emittedGroupIds.insert(groupId).inserted,
                      let sectionId = currentSectionId else { return item.id }
                return .group(groupId, repeatedInMachineSection: sectionId)
            case .workspace:
                return item.id
            }
        }
    }
}
