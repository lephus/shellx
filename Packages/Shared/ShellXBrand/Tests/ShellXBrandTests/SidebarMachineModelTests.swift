import Foundation
import Testing
@testable import ShellXBrand

@Suite struct SidebarMachineModelTests {
    let mac = LocalMachineInfo(name: "MacBook Pro", isLaptop: true)

    @Test func localFirstThenSSHInOrder() {
        let s = SidebarMachineGrouping.sections(for: [
            .init(workspaceID: 1, sshTarget: "ubuntu@vm01", sshConnected: true),
            .init(workspaceID: 2, sshTarget: nil, sshConnected: false),
            .init(workspaceID: 3, sshTarget: "root@vm02", sshConnected: true)], local: mac)
        #expect(s.map(\.header.key) == [.local, .ssh(target: "ubuntu@vm01"), .ssh(target: "root@vm02")])
        #expect(s[0].workspaceIDs == [2])
        #expect(s[1].workspaceIDs == [1])
        #expect(s[2].workspaceIDs == [3])
        #expect(s[0].header.coolicon == "Laptop" && s[1].header.coolicon == "Data")
    }

    @Test func localSectionShownWhenEmpty() {
        let s = SidebarMachineGrouping.sections(for: [SidebarMachineInput<Int>](), local: mac)
        #expect(s.map(\.header.key) == [.local])
        #expect(s[0].workspaceIDs.isEmpty)
        #expect(s[0].header.isOnline)
    }

    @Test func disconnectedHostKeepsRowsAndShowsOffline() {
        let s = SidebarMachineGrouping.sections(for: [
            .init(workspaceID: 7, sshTarget: "ubuntu@vm01", sshConnected: false)], local: mac)
        #expect(s[1].header.isOnline == false && s[1].workspaceIDs == [7])
    }

    @Test func sshMachineIsOnlineWhenAnyWorkspaceIsConnected() {
        let s = SidebarMachineGrouping.sections(for: [
            .init(workspaceID: 1, sshTarget: "ubuntu@vm01", sshConnected: false),
            .init(workspaceID: 2, sshTarget: "ubuntu@vm01", sshConnected: true)], local: mac)
        #expect(s.count == 2)
        #expect(s[1].header.isOnline)
        #expect(s[1].workspaceIDs == [1, 2])
    }

    @Test func differentUsersSameHostAreDifferentMachines() {
        let s = SidebarMachineGrouping.sections(for: [
            .init(workspaceID: 1, sshTarget: "ubuntu@vm01", sshConnected: true),
            .init(workspaceID: 2, sshTarget: "root@vm01", sshConnected: true)], local: mac)
        #expect(s.count == 3)
    }

    @Test func workspacesKeepTheirOrderInsideEachMachine() {
        let s = SidebarMachineGrouping.sections(for: [
            .init(workspaceID: 5, sshTarget: nil, sshConnected: false),
            .init(workspaceID: 1, sshTarget: "ubuntu@vm01", sshConnected: true),
            .init(workspaceID: 3, sshTarget: nil, sshConnected: false),
            .init(workspaceID: 2, sshTarget: "ubuntu@vm01", sshConnected: true),
            .init(workspaceID: 4, sshTarget: nil, sshConnected: false)], local: mac)
        #expect(s[0].workspaceIDs == [5, 3, 4])
        #expect(s[1].workspaceIDs == [1, 2])
    }

    @Test func blankSSHTargetCountsAsLocal() {
        let s = SidebarMachineGrouping.sections(for: [
            .init(workspaceID: 1, sshTarget: "   ", sshConnected: false),
            .init(workspaceID: 2, sshTarget: " ubuntu@vm01 ", sshConnected: true)], local: mac)
        #expect(s.map(\.header.key) == [.local, .ssh(target: "ubuntu@vm01")])
        #expect(s[0].workspaceIDs == [1])
        #expect(s[1].header.title == "ubuntu@vm01")
    }

    @Test func localHeaderUsesMachineNameAndThisMacNote() {
        let header = SidebarMachineGrouping.sections(for: [SidebarMachineInput<Int>](), local: mac)[0].header
        #expect(header.title == "MacBook Pro")
        #expect(header.note == "this Mac")
        #expect(header.coolicon == "Laptop")
        #expect(header.isOnline)
    }

    @Test func desktopMacUsesDesktopIcon() {
        let studio = LocalMachineInfo(name: "Mac Studio", isLaptop: false)
        let header = SidebarMachineGrouping.sections(for: [SidebarMachineInput<Int>](), local: studio)[0].header
        #expect(header.coolicon == "Desktop")
        #expect(header.title == "Mac Studio")
    }

    @Test func sshHeaderUsesTargetSSHNoteAndDataIcon() {
        let header = SidebarMachineGrouping.sections(for: [
            .init(workspaceID: 1, sshTarget: "ubuntu@vm01", sshConnected: true)], local: mac)[1].header
        #expect(header.title == "ubuntu@vm01")
        #expect(header.note == "SSH")
        #expect(header.coolicon == "Data")
        #expect(header.isOnline)
    }

    @Test func labelsAreInjectable() {
        let labels = SidebarMachineLabels(thisMac: "máy này", ssh: "SSH")
        let s = SidebarMachineGrouping.sections(for: [
            .init(workspaceID: 1, sshTarget: "ubuntu@vm01", sshConnected: true)], local: mac, labels: labels)
        #expect(s[0].header.note == "máy này")
        #expect(s[1].header.note == "SSH")
    }

    @Test func machineStableIDsAreDeterministicAndDistinct() {
        let local = SidebarMachineKey.local.stableID
        let a = SidebarMachineKey.ssh(target: "ubuntu@vm01").stableID
        let b = SidebarMachineKey.ssh(target: "root@vm01").stableID
        #expect(local == SidebarMachineKey.local.stableID)
        #expect(a == SidebarMachineKey.ssh(target: "ubuntu@vm01").stableID)
        #expect(Set([local, a, b]).count == 3)
        // Pinned value: the id must not change between launches (row identity).
        #expect(local == SidebarMachineKey.local.stableID)
        #expect(local.uuidString != "00000000-0000-0000-0000-000000000000")
    }

    @Test func laptopDetection() {
        #expect(LocalMachineInfo.isLaptop(hardwareModel: "MacBookPro18,3", hasInternalBattery: false))
        #expect(LocalMachineInfo.isLaptop(hardwareModel: "Mac14,7", hasInternalBattery: true))
        #expect(!LocalMachineInfo.isLaptop(hardwareModel: "Mac14,13", hasInternalBattery: false))
        #expect(!LocalMachineInfo.isLaptop(hardwareModel: "Macmini9,1", hasInternalBattery: false))
    }

    @Test func currentMachineHasAName() {
        let current = LocalMachineInfo.current()
        #expect(!current.name.isEmpty)
        #expect(current == LocalMachineInfo.current())
    }
}
