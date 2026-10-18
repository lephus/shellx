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
}
