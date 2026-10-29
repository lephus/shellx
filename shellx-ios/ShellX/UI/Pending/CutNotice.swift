import SwiftUI

/// "This may be cut short. See all of it on the Mac." under a preview that hit the host's limit.
struct CutNotice: View {
    var body: some View {
        Label {
            Text(LocalizedStringResource("pending.mayBeCut"))
        } icon: {
            Image(systemName: "scissors")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
