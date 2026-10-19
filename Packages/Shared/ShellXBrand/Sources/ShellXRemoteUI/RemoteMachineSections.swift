import Foundation
import ShellXBrand
import ShellXRemoteCore

/// Localized remote header notes, injected so this module needs no bundle.
public struct RemoteMachineLabels: Equatable, Sendable {
    /// Format with one `%@`, the last-seen time: "offline · last seen %@".
    public let offlineLastSeen: String
    /// Stands in for the time when the machine was never seen.
    public let neverSeen: String

    public init(offlineLastSeen: String, neverSeen: String) {
        self.offlineLastSeen = offlineLastSeen
        self.neverSeen = neverSeen
    }

    public static let english = RemoteMachineLabels(offlineLastSeen: "offline · last seen %@", neverSeen: "—")
}

/// Maps the account's remote machines onto sidebar machine headers.
public enum RemoteMachineSections {
    /// Online machines first, then offline ones, each by name in Finder order
    /// (then id, so equal names stay stable). This Mac is never listed.
    public static func ordered(_ machines: [RemoteMachine]) -> [RemoteMachine] {
        machines.filter { !$0.isThisMachine }.sorted { lhs, rhs in
            if lhs.online != rhs.online { return lhs.online }
            switch lhs.name.localizedStandardCompare(rhs.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return lhs.id < rhs.id
            }
        }
    }

    public static func coolicon(for platform: RemoteMachine.Platform) -> String {
        switch platform {
        case .macos: return SidebarMachineGrouping.localCoolicon
        case .windows: return SidebarMachineGrouping.desktopCoolicon
        }
    }

    /// The header's trailing control. An offline machine offers nothing to
    /// request or open; a pending request keeps showing its code.
    public static func action(for machine: RemoteMachine) -> SidebarMachineHeaderAction? {
        switch machine.access {
        case .requested(_, let code):
            return .waiting(code: PairingDisplay.code(code))
        case .none:
            return machine.online ? .requestAccess : nil
        case .granted:
            guard machine.online else { return nil }
            switch machine.link {
            case .connecting:
                return .connecting
            case .reconnecting:
                return .reconnecting
            case .idle, .connected, .offline, .failed:
                // `.failed`/`.offline` on an online machine: clicking retries.
                return .open
            }
        }
    }

    /// "HH:mm" (24 h) in `timeZone`, or `labels.neverSeen`.
    public static func lastSeenText(_ date: Date?, labels: RemoteMachineLabels, timeZone: TimeZone) -> String {
        guard let date else { return labels.neverSeen }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    public static func header(
        for machine: RemoteMachine,
        labels: RemoteMachineLabels,
        timeZone: TimeZone
    ) -> SidebarMachineHeaderModel {
        let note = machine.online
            ? ""
            : String(format: labels.offlineLastSeen, lastSeenText(machine.lastSeen, labels: labels, timeZone: timeZone))
        return SidebarMachineHeaderModel(
            key: .remote(machineID: machine.id),
            title: machine.name,
            note: note,
            coolicon: coolicon(for: machine.platform),
            isOnline: machine.online,
            isDimmed: !machine.online,
            action: action(for: machine)
        )
    }

    /// Section descriptors in display order; offline machines show no rows.
    public static func descriptors(
        for machines: [RemoteMachine],
        labels: RemoteMachineLabels,
        timeZone: TimeZone
    ) -> [SidebarRemoteSectionDescriptor] {
        ordered(machines).map { machine in
            SidebarRemoteSectionDescriptor(
                machineID: machine.id,
                header: header(for: machine, labels: labels, timeZone: timeZone),
                showsRows: machine.online
            )
        }
    }
}

extension SidebarMachineGrouping {
    /// Local, then the account's remote machines (online first, then offline,
    /// each by name), then SSH machines. `now` is the render time; the
    /// last-seen note is a plain clock time today, so it is not read yet.
    public static func sections<ID: Hashable & Sendable>(
        for inputs: [SidebarMachineInput<ID>],
        local: LocalMachineInfo,
        remote: [RemoteMachine],
        now: Date,
        labels: SidebarMachineLabels = .english,
        remoteLabels: RemoteMachineLabels = .english,
        timeZone: TimeZone = .current
    ) -> [SidebarMachineSection<ID>] {
        _ = now
        return sections(
            for: inputs,
            local: local,
            remote: RemoteMachineSections.descriptors(for: remote, labels: remoteLabels, timeZone: timeZone),
            labels: labels
        )
    }
}
