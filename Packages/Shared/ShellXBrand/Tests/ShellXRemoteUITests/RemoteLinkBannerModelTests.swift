import Foundation
import Testing
import ShellXRemoteCore
@testable import ShellXRemoteUI

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func machine(
    _ link: LinkState,
    name: String = "Mac mini",
    id: String = "m1"
) -> RemoteMachine {
    RemoteMachine(
        id: id, name: name, platform: .macos, online: true, lastSeen: now,
        fingerprint: "a1b2c3d4e5f60718", isThisMachine: false, access: .granted, link: link
    )
}

private let vi = RemoteLinkBannerLabels(
    reconnecting: "Đang kết nối lại tới %@…",
    offline: "%@ đang ngoại tuyến. Phiên tiếp tục khi ShellX được mở trên máy đó.",
    failed: "Không kết nối được tới %@ (%@)",
    retryIn: "thử lại sau %llds"
)

@Suite struct RemoteLinkBannerModelTests {
    // MARK: - The brief's cases

    @Test func connectedShowsNoBanner() {
        let connected = RemoteLinkBannerModel(machine: machine(.connected(localSocket: "/tmp/s.sock")), now: now)
        #expect(connected.text == nil)
        #expect(!connected.showsSpinner)
        let idle = RemoteLinkBannerModel(machine: machine(.idle), now: now)
        #expect(idle.text == nil)
        #expect(!idle.showsSpinner)
    }

    @Test func reconnectingShowsCountdown() {
        let link = LinkState.reconnecting(attempt: 2, retryAt: now.addingTimeInterval(3.2))
        let m = RemoteLinkBannerModel(machine: machine(link), now: now)
        #expect(m.text?.hasSuffix("retry in 4s") == true)
        #expect(m.text == "Reconnecting to Mac mini… · retry in 4s")
        #expect(m.tone == .muted)
        #expect(m.showsSpinner)
    }

    @Test func offlineExplainsResume() {
        let m = RemoteLinkBannerModel(machine: machine(.offline(lastSeen: now)), now: now)
        #expect(m.text == "Mac mini is offline. The session resumes when ShellX opens there.")
        #expect(m.tone == .muted)
        #expect(!m.showsSpinner)
    }

    @Test func failedShowsCodeInErrorTone() {
        let m = RemoteLinkBannerModel(machine: machine(.failed(code: "network")), now: now)
        #expect(m.text == "Can't connect to Mac mini (network)")
        #expect(m.tone == .error)
        #expect(!m.showsSpinner)
    }

    @Test func bannerHeightIsFixed() {
        #expect(RemoteLinkBannerModel.height == 28)
        #expect(RemoteLinkBannerModel.borderWidth == 1)
        // The height does not depend on the state or on the text.
        let long = String(repeating: "Máy tính văn phòng tầng 3 ", count: 8)
        for link in [LinkState.connecting, .offline(lastSeen: nil), .failed(code: "x"), .idle] {
            let m = RemoteLinkBannerModel(machine: machine(link, name: long), now: now)
            #expect(type(of: m).height == 28)
            #expect(m.lineLimit == 1)
        }
    }

    // MARK: - Countdown edges

    @Test func retryAtInThePastCountsDownToZero() {
        let link = LinkState.reconnecting(attempt: 1, retryAt: now.addingTimeInterval(-5))
        let m = RemoteLinkBannerModel(machine: machine(link), now: now)
        #expect(m.text == "Reconnecting to Mac mini… · retry in 0s")
        #expect(m.refreshDates.isEmpty)
    }

    @Test func retryAtExactlyNowShowsZero() {
        let link = LinkState.reconnecting(attempt: 1, retryAt: now)
        let m = RemoteLinkBannerModel(machine: machine(link), now: now)
        #expect(m.text?.hasSuffix("retry in 0s") == true)
    }

    @Test func countdownRoundsUp() {
        func text(_ seconds: TimeInterval) -> String? {
            let link = LinkState.reconnecting(attempt: 1, retryAt: now.addingTimeInterval(seconds))
            return RemoteLinkBannerModel(machine: machine(link), now: now).text
        }
        #expect(text(0.01)?.hasSuffix("retry in 1s") == true)
        #expect(text(1)?.hasSuffix("retry in 1s") == true)
        #expect(text(1.01)?.hasSuffix("retry in 2s") == true)
        #expect(text(29.5)?.hasSuffix("retry in 30s") == true)
    }

    @Test func connectingHasSpinnerButNoCountdown() {
        let m = RemoteLinkBannerModel(machine: machine(.connecting), now: now)
        #expect(m.text == "Reconnecting to Mac mini…")
        #expect(m.tone == .muted)
        #expect(m.showsSpinner)
        #expect(m.refreshDates.isEmpty)
    }

    @Test func hugeOrNonFiniteRetryAtIsBounded() {
        let far = LinkState.reconnecting(attempt: 1, retryAt: .distantFuture)
        let m = RemoteLinkBannerModel(machine: machine(far), now: now)
        #expect(m.text?.hasSuffix("retry in 86400s") == true)
        #expect(m.refreshDates.count == RemoteLinkBannerModel.maxRefreshes)
        let inf = LinkState.reconnecting(attempt: 1, retryAt: Date(timeIntervalSinceReferenceDate: .infinity))
        let n = RemoteLinkBannerModel(machine: machine(inf), now: now)
        #expect(n.text == "Reconnecting to Mac mini…")
        #expect(n.refreshDates.isEmpty)
    }

    // MARK: - Refresh schedule

    @Test func refreshDatesStepOneSecondAlignedToTheDeadline() {
        let retryAt = now.addingTimeInterval(3.2)
        let link = LinkState.reconnecting(attempt: 1, retryAt: retryAt)
        let m = RemoteLinkBannerModel(machine: machine(link), now: now)
        #expect(m.refreshDates == [
            retryAt.addingTimeInterval(-3), retryAt.addingTimeInterval(-2),
            retryAt.addingTimeInterval(-1), retryAt
        ])
        // Each refresh shows the next whole second.
        let texts = m.refreshDates.map { date -> String? in
            RemoteLinkBannerModel(machine: machine(link), now: date).text
        }
        #expect(texts == [
            "Reconnecting to Mac mini… · retry in 3s",
            "Reconnecting to Mac mini… · retry in 2s",
            "Reconnecting to Mac mini… · retry in 1s",
            "Reconnecting to Mac mini… · retry in 0s"
        ])
        #expect(m.refreshDates.allSatisfy { $0 > now })
    }

    @Test func refreshDatesAreEmptyWithoutACountdown() {
        for link in [
            LinkState.idle, .connecting, .connected(localSocket: "/tmp/s"),
            .offline(lastSeen: now), .failed(code: "x")
        ] {
            #expect(RemoteLinkBannerModel(machine: machine(link), now: now).refreshDates.isEmpty)
        }
    }

    @Test func refreshDatesAreBounded() {
        let link = LinkState.reconnecting(attempt: 1, retryAt: now.addingTimeInterval(86_400))
        let m = RemoteLinkBannerModel(machine: machine(link), now: now)
        #expect(m.refreshDates.count == RemoteLinkBannerModel.maxRefreshes)
        #expect(m.refreshDates.last == now.addingTimeInterval(86_400))
        #expect(m.refreshDates == m.refreshDates.sorted())
    }

    // MARK: - Names, labels, equality

    @Test func machineNameIsTheMachinesName() {
        let m = RemoteLinkBannerModel(machine: machine(.offline(lastSeen: nil), name: "PC Windows · văn phòng"), now: now)
        #expect(m.text == "PC Windows · văn phòng is offline. The session resumes when ShellX opens there.")
    }

    @Test func blankNameFallsBackToTheMachineID() {
        let m = RemoteLinkBannerModel(machine: machine(.failed(code: "network"), name: "  \n", id: "dev-42"), now: now)
        #expect(m.text == "Can't connect to dev-42 (network)")
    }

    @Test func aNamePercentSignDoesNotBreakTheText() {
        let m = RemoteLinkBannerModel(machine: machine(.connecting, name: "100%d %@ box"), now: now)
        #expect(m.text == "Reconnecting to 100%d %@ box…")
    }

    @Test func vietnameseLabelsAreInjected() {
        let retry = LinkState.reconnecting(attempt: 1, retryAt: now.addingTimeInterval(7))
        #expect(RemoteLinkBannerModel(machine: machine(retry), now: now, labels: vi).text
            == "Đang kết nối lại tới Mac mini… · thử lại sau 7s")
        #expect(RemoteLinkBannerModel(machine: machine(.offline(lastSeen: nil)), now: now, labels: vi).text
            == "Mac mini đang ngoại tuyến. Phiên tiếp tục khi ShellX được mở trên máy đó.")
        #expect(RemoteLinkBannerModel(machine: machine(.failed(code: "network")), now: now, labels: vi).text
            == "Không kết nối được tới Mac mini (network)")
    }

    @Test func failedShowsTheCodeVerbatim() {
        let m = RemoteLinkBannerModel(machine: machine(.failed(code: "pairing_not_pending")), now: now)
        #expect(m.text == "Can't connect to Mac mini (pairing_not_pending)")
    }

    @Test func sameInputsGiveEqualModels() {
        let link = LinkState.reconnecting(attempt: 1, retryAt: now.addingTimeInterval(5))
        #expect(RemoteLinkBannerModel(machine: machine(link), now: now)
            == RemoteLinkBannerModel(machine: machine(link), now: now))
        #expect(RemoteLinkBannerModel(machine: machine(link), now: now)
            != RemoteLinkBannerModel(machine: machine(link), now: now.addingTimeInterval(1)))
    }

    @Test func englishLabelsMatchTheCatalog() {
        let l = RemoteLinkBannerLabels.english
        #expect(l.reconnecting == "Reconnecting to %@…")
        #expect(l.offline == "%@ is offline. The session resumes when ShellX opens there.")
        #expect(l.failed == "Can't connect to %@ (%@)")
        #expect(l.retryIn == "retry in %llds")
    }
}

@Suite struct RemoteLinkBannerLookupTests {
    private let workspace = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let other = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private func snapshot(machines: [RemoteMachine], tagged: [UUID: RemoteMachine.ID]) -> RemoteUISnapshot {
        RemoteUISnapshot(machines: machines, isSignedIn: true, remoteWorkspaces: tagged)
    }

    @Test func aTaggedWorkspaceGetsItsMachine() {
        let mini = machine(.offline(lastSeen: nil), id: "mini")
        let pc = machine(.idle, name: "PC", id: "pc")
        let s = snapshot(machines: [pc, mini], tagged: [workspace: "mini"])
        #expect(RemoteLinkBannerModel.machine(forWorkspace: workspace, in: s) == mini)
    }

    @Test func aLocalWorkspaceHasNoMachine() {
        let s = snapshot(machines: [machine(.idle, id: "mini")], tagged: [workspace: "mini"])
        #expect(RemoteLinkBannerModel.machine(forWorkspace: other, in: s) == nil)
    }

    @Test func aWorkspaceTaggedWithAnUnknownMachineHasNoBanner() {
        let s = snapshot(machines: [machine(.failed(code: "x"), id: "mini")], tagged: [workspace: "gone"])
        #expect(RemoteLinkBannerModel.machine(forWorkspace: workspace, in: s) == nil)
    }

    @Test func noSnapshotMeansNoMachine() {
        #expect(RemoteLinkBannerModel.machine(forWorkspace: workspace, in: nil) == nil)
        #expect(RemoteLinkBannerModel.machine(forWorkspace: workspace, in: .signedOut) == nil)
    }
}
