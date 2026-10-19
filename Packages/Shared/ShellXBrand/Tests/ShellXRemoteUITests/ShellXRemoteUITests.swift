import Foundation
import Testing
import ShellXBrand
import ShellXRemoteCore
@testable import ShellXRemoteUI

private let utc = TimeZone(identifier: "UTC")!
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// 2026-10-19 at `hhmm` in UTC.
private func date(_ hhmm: String) -> Date {
    let parts = hhmm.split(separator: ":").compactMap { Int($0) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: parts[0], minute: parts[1]))!
}

private func rm(
    _ id: String,
    _ name: String,
    online: Bool,
    platform: RemoteMachine.Platform = .macos,
    access: RemoteMachine.Access = .granted,
    link: LinkState = .idle,
    last: Date? = nil,
    isThisMachine: Bool = false
) -> RemoteMachine {
    RemoteMachine(
        id: id, name: name, platform: platform, online: online, lastSeen: last,
        fingerprint: "abcd1234", isThisMachine: isThisMachine, access: access, link: link
    )
}

@Suite struct ShellXRemoteUITests {
    let mac = LocalMachineInfo(name: "MacBook Pro", isLaptop: true)

    @Test func remoteMachinesSitBetweenLocalAndSSH() {
        let s = SidebarMachineGrouping.sections(
            for: [.init(workspaceID: 1, sshTarget: "u@vm", sshConnected: true, remoteMachineID: nil)],
            local: mac,
            remote: [rm("m1", "Mac mini", online: true)],
            now: t0
        )
        #expect(s.map(\.header.key) == [.local, .remote(machineID: "m1"), .ssh(target: "u@vm")])
        #expect(s[2].workspaceIDs == [1])
        #expect(s[1].workspaceIDs.isEmpty)
    }

    @Test func onlineBeforeOfflineThenByName() {
        let s = SidebarMachineGrouping.sections(
            for: [SidebarMachineInput<Int>](),
            local: mac,
            remote: [
                rm("a", "Zeta box", online: false),
                rm("b", "PC 10", online: true),
                rm("c", "alpha", online: false),
                rm("d", "PC 9", online: true),
            ],
            now: t0
        )
        // Online first ("PC 9" before "PC 10": localized-standard order), then offline.
        #expect(s.map(\.header.key) == [
            .local, .remote(machineID: "d"), .remote(machineID: "b"),
            .remote(machineID: "c"), .remote(machineID: "a"),
        ])
    }

    @Test func offlineRemoteIsDimmedWithLastSeenAndNoRows() {
        let s = SidebarMachineGrouping.sections(
            for: [.init(workspaceID: 9, sshTarget: nil, sshConnected: false, remoteMachineID: "m1")],
            local: mac,
            remote: [rm("m1", "Mac mini", online: false, last: date("14:05"))],
            now: t0,
            timeZone: utc
        )
        #expect(s[1].header.isDimmed && s[1].header.note == "offline · last seen 14:05" && s[1].workspaceIDs.isEmpty)
        #expect(s[1].header.isOnline == false)
        // The hidden workspace does not fall back into another section.
        #expect(s.allSatisfy { !$0.workspaceIDs.contains(9) })
    }

    @Test func offlineWithoutLastSeenShowsDashAndUsesInjectedLabels() {
        let labels = RemoteMachineLabels(offlineLastSeen: "ngoại tuyến · lần cuối %@", neverSeen: "—")
        let header = RemoteMachineSections.header(
            for: rm("m1", "Mac mini", online: false, last: nil), labels: labels, timeZone: utc
        )
        #expect(header.note == "ngoại tuyến · lần cuối —")
        let late = RemoteMachineSections.header(
            for: rm("m1", "Mac mini", online: false, last: date("23:59")), labels: labels, timeZone: utc
        )
        #expect(late.note == "ngoại tuyến · lần cuối 23:59")
        let shifted = RemoteMachineSections.header(
            for: rm("m1", "Mac mini", online: false, last: date("23:59")),
            labels: labels,
            timeZone: TimeZone(secondsFromGMT: 7 * 3600)!
        )
        #expect(shifted.note == "ngoại tuyến · lần cuối 06:59")
    }

    @Test func onlineRemoteHeaderHasEmptyNoteIconAndIsNotDimmed() {
        let s = SidebarMachineGrouping.sections(
            for: [SidebarMachineInput<Int>](),
            local: mac,
            remote: [
                rm("w", "PC Windows · văn phòng", online: true, platform: .windows),
                rm("m", "Mac mini", online: true, platform: .macos),
            ],
            now: t0
        )
        let mini = s[1].header
        let pc = s[2].header
        #expect(mini.title == "Mac mini" && mini.note == "" && mini.isOnline && !mini.isDimmed)
        #expect(mini.coolicon == "Laptop")
        #expect(pc.coolicon == "Desktop")
    }

    @Test func thisMachineIsNeverARemoteSection() {
        let s = SidebarMachineGrouping.sections(
            for: [.init(workspaceID: 3, sshTarget: nil, sshConnected: false, remoteMachineID: "self")],
            local: mac,
            remote: [rm("self", "MacBook Pro", online: true, isThisMachine: true), rm("m1", "Mac mini", online: true)],
            now: t0
        )
        #expect(s.map(\.header.key) == [.local, .remote(machineID: "m1")])
        // A workspace tagged with this machine stays local.
        #expect(s[0].workspaceIDs == [3])
    }

    @Test func headerActionFollowsAccessAndLink() {
        #expect(RemoteMachineSections.action(for: rm("m", "M", online: true, access: .none)) == .requestAccess)
        #expect(RemoteMachineSections.action(for: rm("m", "M", online: true,
            access: .requested(pairingID: "p1", code: "123456"))) == .waiting(code: "123 456"))
        #expect(RemoteMachineSections.action(for: rm("m", "M", online: true, link: .idle)) == .open)
        #expect(RemoteMachineSections.action(for: rm("m", "M", online: true,
            link: .connected(localSocket: "/tmp/s"))) == .open)
        #expect(RemoteMachineSections.action(for: rm("m", "M", online: true, link: .connecting)) == .connecting)
        #expect(RemoteMachineSections.action(for: rm("m", "M", online: true,
            link: .reconnecting(attempt: 2, retryAt: t0))) == .reconnecting)
        #expect(RemoteMachineSections.action(for: rm("m", "M", online: true,
            link: .failed(code: "network"))) == .open)
        // Offline: nothing to request or open, but a pending request still shows its code.
        #expect(RemoteMachineSections.action(for: rm("m", "M", online: false, access: .none)) == nil)
        #expect(RemoteMachineSections.action(for: rm("m", "M", online: false)) == nil)
        #expect(RemoteMachineSections.action(for: rm("m", "M", online: false,
            access: .requested(pairingID: "p1", code: "123456"))) == .waiting(code: "123 456"))
        // The header carries the action.
        let s = SidebarMachineGrouping.sections(
            for: [SidebarMachineInput<Int>](), local: mac,
            remote: [rm("m", "M", online: true, access: .none)], now: t0
        )
        #expect(s[1].header.action == .requestAccess)
        #expect(s[0].header.action == nil && !s[0].header.isDimmed)
    }

    @Test func remoteWorkspaceRowsGroupUnderTheirMachine() {
        let s = SidebarMachineGrouping.sections(
            for: [
                .init(workspaceID: 1, sshTarget: nil, sshConnected: false, remoteMachineID: "m2"),
                .init(workspaceID: 2, sshTarget: nil, sshConnected: false),
                .init(workspaceID: 3, sshTarget: nil, sshConnected: false, remoteMachineID: "m1"),
                .init(workspaceID: 4, sshTarget: nil, sshConnected: false, remoteMachineID: "m2"),
                .init(workspaceID: 5, sshTarget: "u@vm", sshConnected: true),
            ],
            local: mac,
            remote: [rm("m1", "Alpha", online: true), rm("m2", "Beta", online: true)],
            now: t0
        )
        #expect(s.map(\.header.key) == [.local, .remote(machineID: "m1"), .remote(machineID: "m2"), .ssh(target: "u@vm")])
        #expect(s[0].workspaceIDs == [2])
        #expect(s[1].workspaceIDs == [3])
        #expect(s[2].workspaceIDs == [1, 4])
        #expect(s[3].workspaceIDs == [5])
    }

    @Test func workspaceTaggedWithUnknownMachineStaysVisible() {
        let s = SidebarMachineGrouping.sections(
            for: [.init(workspaceID: 7, sshTarget: nil, sshConnected: false, remoteMachineID: "gone")],
            local: mac, remote: [RemoteMachine](), now: t0
        )
        #expect(s.map(\.header.key) == [.local])
        #expect(s[0].workspaceIDs == [7])
    }

    @Test func snapshotLooksUpRemoteWorkspaces() {
        let ws = UUID()
        let snapshot = RemoteUISnapshot(
            machines: [rm("m1", "Mac mini", online: true)],
            isSignedIn: true,
            remoteWorkspaces: [ws: "m1"]
        )
        #expect(snapshot.remoteMachineID(forWorkspace: ws) == "m1")
        #expect(snapshot.remoteMachineID(forWorkspace: UUID()) == nil)
        #expect(RemoteUISnapshot.signedOut.isSignedIn == false && RemoteUISnapshot.signedOut.machines.isEmpty)
        #expect(snapshot.pendingApprovals.isEmpty && snapshot.outgoing.isEmpty)
    }

    @Test func longRemoteNameKeepsHeaderHeight() {
        let long = String(repeating: "Máy tính văn phòng tầng 3 ", count: 6)
        let s = SidebarMachineGrouping.sections(
            for: [SidebarMachineInput<Int>](), local: mac,
            remote: [rm("m1", long, online: true, platform: .windows)], now: t0
        )
        #expect(s[1].header.title == long)
        #expect(SidebarMachineHeaderLayout.height(forTitle: s[1].header.title) == SidebarMachineHeaderLayout.height)
        #expect(SidebarMachineHeaderLayout.height(forTitle: s[1].header.title)
            == SidebarMachineHeaderLayout.height(forTitle: "PC"))
    }

    @Test func signInErrorMapping() {
        let labels = SignInErrorLabels(credentials: "Email or password is incorrect", network: "Can't reach relay.shellx.pro")
        #expect(SignInErrorMessage.text(for: ShellXCoreError(code: "invalid_credentials", message: "x"), labels: labels)
            == "Email or password is incorrect")
        #expect(SignInErrorMessage.text(for: ShellXCoreError(code: "network", message: "x"), labels: labels)
            == "Can't reach relay.shellx.pro")
        #expect(SignInErrorMessage.text(for: ShellXCoreError(code: "rate_limited", message: "slow down"), labels: labels)
            == "rate_limited")
        #expect(SignInErrorMessage.text(forCode: "network", labels: .english) == "Can't reach relay.shellx.pro")
    }
}
