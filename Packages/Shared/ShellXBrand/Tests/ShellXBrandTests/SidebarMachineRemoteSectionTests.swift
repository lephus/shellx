import Foundation
import Testing
@testable import ShellXBrand

@Suite struct SidebarMachineRemoteSectionTests {
    let mac = LocalMachineInfo(name: "MacBook Pro", isLaptop: true)

    private func descriptor(_ id: String, showsRows: Bool = true, action: SidebarMachineHeaderAction? = .open) -> SidebarRemoteSectionDescriptor {
        SidebarRemoteSectionDescriptor(
            machineID: id,
            header: SidebarMachineHeaderModel(
                key: .remote(machineID: id), title: id, note: "", coolicon: "Laptop",
                isOnline: showsRows, isDimmed: !showsRows, action: action
            ),
            showsRows: showsRows
        )
    }

    @Test func remoteSectionsKeepDescriptorOrderBetweenLocalAndSSH() {
        let s = SidebarMachineGrouping.sections(
            for: [
                .init(workspaceID: 1, sshTarget: "u@vm", sshConnected: true),
                .init(workspaceID: 2, sshTarget: nil, sshConnected: false, remoteMachineID: "b"),
            ],
            local: mac,
            remote: [descriptor("b"), descriptor("a")]
        )
        #expect(s.map(\.header.key) == [.local, .remote(machineID: "b"), .remote(machineID: "a"), .ssh(target: "u@vm")])
        #expect(s[1].workspaceIDs == [2])
        #expect(s[1].header.action == .open)
    }

    @Test func hiddenRowsAreDroppedNotMovedElsewhere() {
        let s = SidebarMachineGrouping.sections(
            for: [.init(workspaceID: 2, sshTarget: "u@vm", sshConnected: true, remoteMachineID: "a")],
            local: mac,
            remote: [descriptor("a", showsRows: false)]
        )
        #expect(s.map(\.header.key) == [.local, .remote(machineID: "a")])
        #expect(s.allSatisfy { $0.workspaceIDs.isEmpty })
        #expect(s[1].header.isDimmed)
    }

    @Test func duplicateDescriptorsCollapseToTheFirst() {
        let s = SidebarMachineGrouping.sections(
            for: [SidebarMachineInput<Int>](),
            local: mac,
            remote: [descriptor("a"), descriptor("a", showsRows: false)]
        )
        #expect(s.map(\.header.key) == [.local, .remote(machineID: "a")])
        #expect(s[1].header.isDimmed == false)
    }

    @Test func remoteKeysHaveDistinctStableIDs() {
        let ids = [
            SidebarMachineKey.local, .ssh(target: "m1"), .remote(machineID: "m1"), .remote(machineID: "m2"),
        ].map(\.stableID)
        #expect(Set(ids).count == 4)
        #expect(SidebarMachineKey.remote(machineID: "m1").stableID == SidebarMachineKey.remote(machineID: "m1").stableID)
    }

    @Test func localAndSSHHeadersHaveNoActionAndAreNotDimmed() {
        let s = SidebarMachineGrouping.sections(
            for: [.init(workspaceID: 1, sshTarget: "u@vm", sshConnected: false)], local: mac
        )
        #expect(s.allSatisfy { $0.header.action == nil && !$0.header.isDimmed })
        #expect(s[1].header.isOnline == false)
    }
}
