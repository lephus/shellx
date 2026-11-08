import SwiftUI

/// The confirmation of "Delete Account…": what is lost, one destructive button, and (for a password session) the way
/// to switch to Google first.
struct DeleteAccountSheet: View {
    enum Step: Equatable { case confirm, switchFirst, working, failed(String) }

    let step: Step
    var delete: () -> Void = {}
    var switchToGoogle: () -> Void = {}
    var close: () -> Void = {}

    private var isWorking: Bool { step == .working }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color("StatusError"))
                    .accessibilityHidden(true)
                Text(LocalizedStringResource("settings.account.delete.title"))
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(step == .switchFirst
                    ? LocalizedStringResource("settings.account.delete.switchFirst")
                    : LocalizedStringResource("settings.account.delete.message"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if case let .failed(message) = step {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(Color("StatusError"))
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("deleteAccount.error")
                }
                if isWorking {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(LocalizedStringResource("settings.account.delete.deleting"))
                    }
                    .accessibilityElement(children: .combine)
                }
                if step == .switchFirst {
                    Button(action: switchToGoogle) {
                        Text(LocalizedStringResource("settings.account.switchToGoogle"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isWorking)
                    .accessibilityIdentifier("deleteAccount.switch")
                } else {
                    Button(action: delete) {
                        Text(LocalizedStringResource("settings.account.delete.button"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(SecondaryButtonStyle(color: Color("StatusError")))
                    .disabled(isWorking)
                    .accessibilityIdentifier("deleteAccount.delete")
                }
                Button(action: close) {
                    Text(LocalizedStringResource("common.cancel"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(isWorking)
                .accessibilityIdentifier("deleteAccount.cancel")
            }
            .padding(20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
        .presentationDetents([.medium, .large])
    }
}
