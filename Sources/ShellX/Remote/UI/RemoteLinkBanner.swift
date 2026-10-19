import ShellXBrand
import ShellXRemoteCore
import ShellXRemoteUI
import SwiftUI

extension RemoteLinkBannerLabels {
    static var localized: RemoteLinkBannerLabels {
        RemoteLinkBannerLabels(
            reconnecting: String(localized: "remote.banner.reconnecting", defaultValue: "Reconnecting to %@…"),
            offline: String(
                localized: "remote.banner.offline",
                defaultValue: "%@ is offline. The session resumes when ShellX opens there."
            ),
            failed: String(localized: "remote.banner.failed", defaultValue: "Can't connect to %@ (%@)"),
            retryIn: String(localized: "remote.banner.retryIn", defaultValue: "retry in %llds")
        )
    }
}

/// One fixed-height line above a remote workspace's panes: the link is
/// reconnecting, the machine is offline, or the connection failed. Flat
/// `raise` fill, 1 px `line` bottom border, palette text. It only displays:
/// no hit testing and nothing focusable, so it never takes input from the
/// terminal below it.
struct RemoteLinkBanner: View {
    let model: RemoteLinkBannerModel

    var body: some View {
        if let text = model.text {
            HStack(spacing: 6) {
                if model.showsSpinner {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .scaleEffect(0.75)
                        .frame(width: 12, height: 12)
                }
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .lineLimit(model.lineLimit)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: CGFloat(RemoteLinkBannerModel.height))
            .background(ShellXPalette.raise.color)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ShellXPalette.line.color)
                    .frame(height: CGFloat(RemoteLinkBannerModel.borderWidth))
            }
            .environment(\.colorScheme, .dark)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(text))
        }
    }

    private var textColor: Color {
        switch model.tone {
        case .muted: return ShellXPalette.muted.color
        case .error: return ShellXPalette.error.color
        }
    }
}

extension View {
    /// Shows the link banner above this workspace's content when the
    /// workspace is a remote one. With the remote UI off this returns the
    /// view itself, so a local-only ShellX is unchanged.
    func shellXRemoteLinkBanner(workspaceID: UUID, isSelected: Bool) -> some View {
        modifier(ShellXRemoteLinkBannerModifier(workspaceID: workspaceID, isSelected: isSelected))
    }
}

struct ShellXRemoteLinkBannerModifier: ViewModifier {
    let workspaceID: UUID
    let isSelected: Bool

    /// The gate is fixed for the life of the process (the same read that decides
    /// whether `ShellXRemoteUIModel.shared` has a service), so it is read once.
    private static let remoteUIEnabled = ShellXRemoteUIGate.isEnabled

    @ViewBuilder
    func body(content: Content) -> some View {
        // Off: the content as it is, nothing observed.
        if Self.remoteUIEnabled {
            ShellXRemoteLinkBannerHost(workspaceID: workspaceID, isSelected: isSelected, content: content)
        } else {
            content
        }
    }
}

/// Decides, once per launch, whether the remote UI has a service at all.
/// Without one the content is shown as it is.
private struct ShellXRemoteLinkBannerHost<Content: View>: View {
    let workspaceID: UUID
    let isSelected: Bool
    let content: Content

    var body: some View {
        if ShellXRemoteUIModel.shared.service != nil {
            ShellXRemoteLinkBannerLayer(
                remote: ShellXRemoteUIModel.shared,
                workspaceID: workspaceID,
                isSelected: isSelected,
                content: content
            )
        } else {
            content
        }
    }
}

/// The banner (when this workspace's machine has something to say) stacked
/// above the content. The stack is always there, so the content keeps its
/// identity when a banner appears or goes away; it only moves down.
private struct ShellXRemoteLinkBannerLayer<Content: View>: View {
    @ObservedObject var remote: ShellXRemoteUIModel
    let workspaceID: UUID
    let isSelected: Bool
    let content: Content

    var body: some View {
        VStack(spacing: 0) {
            banner
            content
        }
    }

    @ViewBuilder
    private var banner: some View {
        if let machine = RemoteLinkBannerModel.machine(forWorkspace: workspaceID, in: remote.snapshot) {
            let labels = RemoteLinkBannerLabels.localized
            let now = Date()
            let model = RemoteLinkBannerModel(machine: machine, now: now, labels: labels)
            if model.text != nil {
                if isSelected, !model.refreshDates.isEmpty {
                    // Redraws on the whole seconds of the countdown only, and stops at 0.
                    // The first entry is `now` (every refresh date is later), so the first
                    // frame is the model above.
                    TimelineView(.explicit([now] + model.refreshDates)) { context in
                        RemoteLinkBanner(model: RemoteLinkBannerModel(machine: machine, now: context.date, labels: labels))
                    }
                } else {
                    RemoteLinkBanner(model: model)
                }
            }
        }
    }
}
