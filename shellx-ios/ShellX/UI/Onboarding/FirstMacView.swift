import SwiftUI

/// Shown after sign-in while no Mac is paired: what to do on the Mac, and the button that opens
/// the scanner.
struct FirstMacView: View {
    let pair: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 64

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: symbolSize))
                    .foregroundStyle(Color("AccentText"))
                    .accessibilityHidden(true)
                Text(LocalizedStringResource("pairing.title"))
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(LocalizedStringResource("firstMac.subtitle"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: "1.circle.fill")
                        .foregroundStyle(Color("AccentText"))
                        .accessibilityHidden(true)
                    Text(LocalizedStringResource("pairing.instructions"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: "2.circle.fill")
                        .foregroundStyle(Color("AccentText"))
                        .accessibilityHidden(true)
                    Text(LocalizedStringResource("firstMac.step2"))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: pair) {
                    Label(String(localized: "firstMac.scan"), systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
                .accessibilityIdentifier("firstMac.pair")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemBackground))
    }
}

#if DEBUG
#Preview {
    NavigationStack { FirstMacView(pair: {}) }
}
#endif
