import ShellXAppCore
import SwiftUI

/// The one-time banner over the home of a password session (S1 §6.3b).
struct SwitchToGoogleBanner: View {
    /// Only for a password session, until "Not Now" or a switch.
    static func isShown(authMethod: AccountAuthMethod?, dismissed: Bool) -> Bool {
        authMethod == .password && !dismissed
    }

    var switching = false
    var error: String? = nil
    let switchNow: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringResource("settings.account.switchToGoogle"))
                .font(.headline)
            Text(LocalizedStringResource("settings.account.switchToGoogle.detail"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(Color("StatusError"))
                    .accessibilityIdentifier("switchBanner.error")
            }
            HStack(spacing: 12) {
                Button(action: switchNow) {
                    HStack {
                        if switching { ProgressView() }
                        Text(LocalizedStringResource("switchToGoogle.banner.switch"))
                            .font(.headline)
                    }
                    .frame(minHeight: 44)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(switching)
                .accessibilityIdentifier("switchBanner.switch")
                Button(action: dismiss) {
                    Text(LocalizedStringResource("switchToGoogle.banner.later"))
                        .frame(minHeight: 44)
                        .padding(.horizontal, 12)
                }
                .disabled(switching)
                .accessibilityIdentifier("switchBanner.later")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface)
    }
}
