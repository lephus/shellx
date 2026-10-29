import SwiftUI

/// "120 / 4096 bytes" under a field whose text has a byte limit on the wire; "Too long: …" in the
/// error colour past it.
struct ByteCounter: View {
    let used: Int
    let limit: Int

    var body: some View {
        let over = used > limit
        Text(
            verbatim: over
                ? String(localized: "pending.tooLong \(used) \(limit)")
                : String(localized: "pending.bytes \(used) \(limit)")
        )
        .font(.caption.monospacedDigit())
        .foregroundStyle(over ? Color("StatusError") : Color.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
