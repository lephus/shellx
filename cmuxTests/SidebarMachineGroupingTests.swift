import CmuxCore
import CmuxSettings
import CmuxWorkspaces
import Foundation
import ShellXBrand
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// ShellX W1 Task 10: machine-grouped sidebar rows. Grouping rules themselves
/// are covered by `Packages/Shared/ShellXBrand` tests; these cover the app's
/// row identities, which NSTableView diffing requires to be unique.
@Suite @MainActor struct SidebarMachineGroupingTests {
    @Test func repeatedGroupHeaderHasItsOwnRowIdPerSection() {
        let groupId = UUID()
        let local = SidebarMachineKey.local.stableID
        let vm01 = SidebarMachineKey.ssh(target: "ubuntu@vm01").stableID
        let primary = SidebarWorkspaceRenderItemID.group(groupId)
        let repeatedOnVM = SidebarWorkspaceRenderItemID.group(groupId, repeatedInMachineSection: vm01)
        let repeatedLocally = SidebarWorkspaceRenderItemID.group(groupId, repeatedInMachineSection: local)
        #expect(Set([primary, repeatedOnVM, repeatedLocally]).count == 3)
        #expect(repeatedOnVM == .group(groupId, repeatedInMachineSection: vm01))
        #expect(repeatedOnVM.groupId == groupId)
    }

    @Test func headerRowIdsDoNotCollideWithWorkspaceRows() {
        let header = SidebarMachineHeaderModel(
            key: .ssh(target: "ubuntu@vm01"),
            title: "ubuntu@vm01",
            note: "SSH",
            coolicon: "Data",
            isOnline: true
        )
        let machineRow = ShellXSidebarHeaderRow.machine(header)
        let brandRow = ShellXSidebarHeaderRow.brand
        let ids: Set<SidebarWorkspaceRenderItemID> = [
            machineRow.rowId,
            brandRow.rowId,
            .workspace(machineRow.placeholderWorkspaceId),
            .group(machineRow.placeholderWorkspaceId),
        ]
        #expect(ids.count == 4)
        #expect(SidebarWorkspaceRenderItem.machineHeader(header).id == machineRow.rowId)
        #expect(machineRow.rowHeight == SidebarMachineHeaderLayout.height)
    }

    // MARK: App-side grouping over real workspaces

    private let mac = LocalMachineInfo(name: "MacBook Pro", isLaptop: true)

    private func makeTabManager() -> TabManager {
        let suiteName = "shellx.sidebar-machine-grouping-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let manager = TabManager(
            autoWelcomeIfNeeded: false,
            settings: UserDefaultsSettingsClient(defaults: defaults),
            closeTabWarningDefaults: defaults
        )
        manager.addWorkspace(autoWelcomeIfNeeded: false)
        return manager
    }

    /// Marks a workspace as SSH without connecting: only the published
    /// configuration the sidebar reads is set.
    private func makeSSH(_ workspace: Workspace, destination: String) {
        workspace.remoteConfiguration = WorkspaceRemoteConfiguration(
            destination: destination,
            port: nil,
            identityFile: nil,
            sshOptions: [],
            localProxyPort: nil,
            relayPort: nil,
            relayID: nil,
            relayToken: nil,
            localSocketPath: nil,
            terminalStartupCommand: nil
        )
    }

    /// Splits items into (machine key, items after its header) runs.
    private func sections(
        _ items: [SidebarWorkspaceRenderItem]
    ) -> [(key: SidebarMachineKey, items: [SidebarWorkspaceRenderItem])] {
        var result: [(key: SidebarMachineKey, items: [SidebarWorkspaceRenderItem])] = []
        for item in items {
            if case .machineHeader(let header) = item {
                result.append((key: header.key, items: []))
            } else if !result.isEmpty {
                result[result.count - 1].items.append(item)
            }
        }
        return result
    }

    private func workspaceIds(_ items: [SidebarWorkspaceRenderItem]) -> [UUID] {
        items.compactMap { item in
            guard case .workspace(let workspaceId) = item else { return nil }
            return workspaceId
        }
    }

    private func groupHeaderIds(_ items: [SidebarWorkspaceRenderItem]) -> [UUID] {
        items.compactMap { item in
            guard case .groupHeader(let groupId, _) = item else { return nil }
            return groupId
        }
    }

    @Test func machineInputReadsSSHTargetAndConnection() throws {
        let manager = makeTabManager()
        let workspace = try #require(manager.tabs.last)
        let local = SidebarMachineInput<UUID>(workspace: workspace)
        #expect(local.workspaceID == workspace.id)
        #expect(local.sshTarget == nil)
        #expect(local.sshConnected == false)

        makeSSH(workspace, destination: "ubuntu@vm01")
        workspace.remoteConnectionState = .disconnected
        let offline = SidebarMachineInput<UUID>(workspace: workspace)
        #expect(offline.sshTarget == "ubuntu@vm01")
        #expect(offline.sshConnected == false)

        workspace.remoteConnectionState = .connected
        #expect(SidebarMachineInput<UUID>(workspace: workspace).sshConnected)
    }

    @Test func localSectionComesFirstThenSSHMachines() throws {
        let manager = makeTabManager()
        manager.addWorkspace(autoWelcomeIfNeeded: false)
        let tabs = manager.tabs
        #expect(tabs.count == 3)
        makeSSH(tabs[0], destination: "ubuntu@vm01")
        let items = SidebarMachineSectionRenderItems.renderItems(
            tabs: tabs,
            groupsById: [:],
            local: mac
        )
        let split = sections(items)
        #expect(split.map { $0.key } == [.local, .ssh(target: "ubuntu@vm01")])
        #expect(workspaceIds(split[0].items) == [tabs[1].id, tabs[2].id])
        #expect(workspaceIds(split[1].items) == [tabs[0].id])
    }

    @Test func groupSpanningMachinesShowsItsHeaderInEachSectionWithOnlyThatSectionsRows() throws {
        let manager = makeTabManager()
        manager.addWorkspace(autoWelcomeIfNeeded: false)
        manager.addWorkspace(autoWelcomeIfNeeded: false)
        let originalIds = manager.tabs.map(\.id)
        #expect(originalIds.count == 4)
        let groupId = try #require(manager.createWorkspaceGroup(
            name: "Spanning",
            childWorkspaceIds: [originalIds[1], originalIds[2], originalIds[3]]
        ))
        let group = try #require(manager.workspaceGroups.first { $0.id == groupId })
        // The anchor (first child) stays local; one other member moves to SSH.
        let sshMemberId = try #require(originalIds.suffix(2).first { $0 != group.anchorWorkspaceId })
        let sshMember = try #require(manager.tabs.first { $0.id == sshMemberId })
        makeSSH(sshMember, destination: "ubuntu@vm01")

        let groupsById = Dictionary(uniqueKeysWithValues: manager.workspaceGroups.map { ($0.id, $0) })
        let items = SidebarMachineSectionRenderItems.renderItems(
            tabs: manager.tabs,
            groupsById: groupsById,
            orderedGroups: manager.workspaceGroups,
            local: mac
        )
        let split = sections(items)
        #expect(split.map { $0.key } == [.local, .ssh(target: "ubuntu@vm01")])
        #expect(groupHeaderIds(split[0].items) == [groupId])
        #expect(groupHeaderIds(split[1].items) == [groupId])
        #expect(workspaceIds(split[1].items) == [sshMemberId])
        #expect(!workspaceIds(split[0].items).contains(sshMemberId))
        // The anchor is represented by its header, never by a workspace row.
        #expect(!workspaceIds(items).contains(group.anchorWorkspaceId))

        // Row ids stay unique although the header shows twice.
        let rowIds = SidebarMachineSectionRenderItems.rowIds(for: items)
        #expect(rowIds.count == items.count)
        #expect(Set(rowIds).count == rowIds.count)
        #expect(rowIds.contains(.group(groupId)))
        #expect(rowIds.contains(.group(
            groupId,
            repeatedInMachineSection: SidebarMachineKey.ssh(target: "ubuntu@vm01").stableID
        )))
    }

    @Test func durableEmptyGroupStaysInTheLocalSection() throws {
        let manager = makeTabManager()
        let tabs = manager.tabs
        makeSSH(tabs[0], destination: "ubuntu@vm01")
        let emptyGroup = WorkspaceGroup(
            id: UUID(),
            name: "Empty",
            isCollapsed: false,
            isPinned: false,
            anchor: .empty(UUID()),
            customColor: nil,
            iconSymbol: nil
        )
        let items = SidebarMachineSectionRenderItems.renderItems(
            tabs: tabs,
            groupsById: [emptyGroup.id: emptyGroup],
            orderedGroups: [emptyGroup],
            local: mac
        )
        let split = sections(items)
        #expect(split.map { $0.key } == [.local, .ssh(target: "ubuntu@vm01")])
        #expect(groupHeaderIds(split[0].items) == [emptyGroup.id])
        #expect(groupHeaderIds(split[1].items).isEmpty)
    }

    @Test func rowIdsForSingleMachineMatchItemIds() throws {
        let manager = makeTabManager()
        let groupId = try #require(manager.createWorkspaceGroup(
            name: "Local",
            childWorkspaceIds: manager.tabs.map(\.id)
        ))
        let items = SidebarMachineSectionRenderItems.renderItems(
            tabs: manager.tabs,
            groupsById: Dictionary(uniqueKeysWithValues: manager.workspaceGroups.map { ($0.id, $0) }),
            local: mac
        )
        #expect(SidebarMachineSectionRenderItems.rowIds(for: items) == items.map(\.id))
        #expect(items.map(\.id).contains(.group(groupId)))
    }
}
