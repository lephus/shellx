import SwiftUI

/// The "Demo · Exit" banner over the demo account's signed-in screens.
struct DemoBanner: View {
    let exit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(LocalizedStringResource("demo.banner.title"))
                .font(.headline)
                .accessibilityLabel(Text(LocalizedStringResource("demo.banner.label")))
            Text(verbatim: "·").accessibilityHidden(true)
            Button(action: exit) {
                Text(LocalizedStringResource("demo.banner.exit"))
                    .font(.headline)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 8)
            }
            .accessibilityIdentifier("demo.exit")
        }
        .foregroundStyle(Color("AccentText"))
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color("AccentText").opacity(0.14))
        .accessibilityIdentifier("demo.banner")
    }
}
