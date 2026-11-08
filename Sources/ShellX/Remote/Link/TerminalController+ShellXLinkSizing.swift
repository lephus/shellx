import CmuxTerminalSharing
import CmuxTerminalSizing
import Foundation

/// ShellX: a ShellX Link phone viewing a terminal is its own counting participant in the terminal's shared sizing
/// (docs/shared-terminal-sizing.md, "ShellX Link phones").
@MainActor
extension TerminalController {
    static let shellXLinkSizingClientIDPrefix = "shellx-link-"

    /// A ShellX Link phone starts viewing `surfaceID` at columns x rows. It joins the shared sizing as its own counting
    /// participant (attach is its activity), and the terminal runs `latest` while any Link phone views it, unless someone
    /// chose a policy other than Fit everyone for it. Returns the grid the terminal is expected to take (the replay
    /// fence's value).
    @discardableResult
    func shellXLinkSizingAttach(
        surfaceID: UUID, clientID: String, columns: Int, rows: Int
    ) -> (columns: Int, rows: Int)? {
        if let host = localSizingHost(surfaceID: surfaceID, create: true),
           host.state.policy == .fitEveryone,
           shellXLinkSizingPolicyRestoreBySurfaceID[surfaceID] == nil {
            shellXLinkSizingPolicyRestoreBySurfaceID[surfaceID] = .fitEveryone
            _ = localSizingSetPolicy(surfaceID: surfaceID, policy: .latest)
        }
        var reports = mobileViewportReportsBySurfaceID[surfaceID] ?? [:]
        reports[clientID] = MobileViewportReport(columns: columns, rows: rows, updatedAt: Date(), sticky: true)
        mobileViewportReportsBySurfaceID[surfaceID] = reports
        return resolveSharedSizing(
            surfaceID: surfaceID, reports: reports,
            countsOverride: (clientID: clientID, value: true), reason: "shellx.link.attach"
        )
    }

    /// The phone's grid changed: a new report and the phone's activity.
    func shellXLinkSizingResize(surfaceID: UUID, clientID: String, columns: Int, rows: Int) {
        var reports = mobileViewportReportsBySurfaceID[surfaceID] ?? [:]
        guard reports[clientID] != nil else { return }
        reports[clientID]?.columns = columns
        reports[clientID]?.rows = rows
        reports[clientID]?.updatedAt = Date()
        mobileViewportReportsBySurfaceID[surfaceID] = reports
        _ = resolveSharedSizing(surfaceID: surfaceID, reports: reports, reason: "shellx.link.resize")
        noteMobileSizingActivity(surfaceID: surfaceID, clientID: clientID)
    }

    /// The phone stopped viewing: its report goes and the Mac's size returns at once. After the last Link phone leaves, a
    /// `latest` this code set goes back to the recorded policy (unless someone changed it meanwhile).
    func shellXLinkSizingDetach(surfaceID: UUID, clientID: String) {
        _ = clearMobileViewportReport(surfaceID: surfaceID, clientID: clientID, reason: "shellx.link.detach")
        if var host = localSizingHostsBySurfaceID[surfaceID] {
            host.forgetPhone(LocalTerminalSizingHost.phoneParticipantID(clientID: clientID))
            localSizingHostsBySurfaceID[surfaceID] = host
        }
        let othersRemain = (mobileViewportReportsBySurfaceID[surfaceID] ?? [:]).keys
            .contains { $0.hasPrefix(Self.shellXLinkSizingClientIDPrefix) }
        guard !othersRemain, let recorded = shellXLinkSizingPolicyRestoreBySurfaceID.removeValue(forKey: surfaceID) else { return }
        if localSizingHostsBySurfaceID[surfaceID]?.state.policy == .latest {
            _ = localSizingSetPolicy(surfaceID: surfaceID, policy: recorded)
        }
    }

    /// Runs one batch of a remote participant's input so the Mac pane's explicit-input hook does not count it as the Mac's
    /// activity, then counts it as that participant's.
    func performRemoteParticipantInput(surfaceID: UUID, clientID: String, _ body: () -> Void) {
        remoteParticipantInputDepthBySurfaceID[surfaceID, default: 0] += 1
        body()
        if let depth = remoteParticipantInputDepthBySurfaceID[surfaceID], depth > 1 {
            remoteParticipantInputDepthBySurfaceID[surfaceID] = depth - 1
        } else {
            remoteParticipantInputDepthBySurfaceID[surfaceID] = nil
        }
        noteMobileSizingActivity(surfaceID: surfaceID, clientID: clientID)
    }
}
