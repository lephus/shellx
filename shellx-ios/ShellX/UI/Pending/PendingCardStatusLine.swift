import ShellXAppCore
import SwiftUI

/// The line on a card (and in its sheet) that says what became of the decision, or why the
/// buttons are off. Nothing when there is nothing to say.
struct PendingCardStatusLine: View {
    /// What the line says; also what VoiceOver announces when it changes.
    struct Line: Equatable {
        enum Mark: Equatable {
            case progress
            case symbol(String, colorName: String)
        }

        let text: String
        let mark: Mark
        /// "Try again" follows the text.
        var offersRetry = false
    }

    let status: DecisionStatus?
    let actionable: Bool
    let machineName: String
    /// A sheet's reason it cannot send (`PendingSheetModel.linkNote`); a card has none.
    var linkNote: PendingSheetModel.LinkNote?
    var retry: () -> Void = {}

    var body: some View {
        if let line = Self.line(status: status, actionable: actionable, machineName: machineName, linkNote: linkNote) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                switch line.mark {
                case .progress:
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                case let .symbol(name, colorName):
                    Image(systemName: name)
                        .foregroundStyle(Color(colorName))
                        .accessibilityHidden(true)
                }
                Text(verbatim: line.text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if line.offersRetry {
                    Button(action: retry) {
                        Text(LocalizedStringResource("pending.status.retry"))
                            .fontWeight(.semibold)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .tint(Color("AccentText"))
                    .accessibilityIdentifier("pending.retry")
                }
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    /// The line for a decision's status and the card's link. A failure says more than the link, so
    /// it wins; with no decision out, a card that cannot act says it is reconnecting, and a sheet says
    /// what `linkNote` gives (offline, or to be paired again: never "handled elsewhere").
    static func line(
        status: DecisionStatus?, actionable: Bool, machineName: String, linkNote: PendingSheetModel.LinkNote? = nil
    ) -> Line? {
        switch status {
        case .sending:
            return Line(text: String(localized: "pending.status.sending"), mark: .progress)
        case .handledElsewhere:
            return Line(
                text: String(localized: "pending.status.handledElsewhere"),
                mark: .symbol("checkmark.circle", colorName: "StatusIdle"))
        case .failed(.offline):
            return Line(
                text: String(localized: "pending.status.offline \(machineName)"),
                mark: .symbol("wifi.slash", colorName: "StatusIdle"))
        case .failed(.noAnswer):
            return Line(
                text: String(localized: "pending.status.noAnswer"),
                mark: .symbol("exclamationmark.circle", colorName: "StatusError"), offersRetry: actionable)
        case .failed(.rejected):
            return Line(
                text: String(localized: "pending.status.rejected"),
                mark: .symbol("xmark.octagon", colorName: "StatusError"))
        case .done, nil:
            guard !actionable else { return nil }
            switch linkNote {
            case .offline?:
                return Line(
                    text: String(localized: "pending.status.offline \(machineName)"),
                    mark: .symbol("wifi.slash", colorName: "StatusIdle"))
            case .needsPairing?:
                return Line(
                    text: String(localized: "pending.status.needsPairing \(machineName)"),
                    mark: .symbol("iphone.slash", colorName: "StatusIdle"))
            case .needsUpdate?:
                return Line(
                    text: String(localized: "machine.state.needsUpdate"),
                    mark: .symbol("arrow.down.circle", colorName: "StatusIdle"))
            case .reconnecting?, nil:
                return Line(text: String(localized: "pending.status.reconnecting"), mark: .progress)
            }
        }
    }
}
