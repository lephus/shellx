import ShellXAppCore
import SwiftUI
import UIKit

/// What the mic says above where it is used:
/// - while listening, the words as they come (the newest lines) with a simple level bar, "Listening…"
///   before the first word, "Release to cancel" once cancel is armed, and the byte limit once
///   reached;
/// - a denied permission, with "Open Settings"; no recognizer right now, with "You can still type".
/// Shows nothing when idle.
struct VoiceStatusView: View {
    let model: VoiceInputModel
    /// The microphone's level, 0 to 1.
    var level: Double = 0

    /// The last words shown, kept while the final text comes.
    @State private var lastText = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                EmptyView()
            case let .listening(text):
                panel(text: text, armed: false, finishing: false)
            case let .cancelArmed(text):
                panel(text: text, armed: true, finishing: false)
            case .finishing:
                panel(text: lastText, armed: false, finishing: true)
            case .denied:
                notice(LocalizedStringResource("voice.denied"), settings: true)
            case .unavailable:
                notice(LocalizedStringResource("settings.voice.unavailable"), settings: false)
            }
        }
        .onChange(of: model.phase) { _, phase in
            switch phase {
            case let .listening(text), let .cancelArmed(text): lastText = text
            case .idle: lastText = ""
            default: break
            }
        }
    }

    private func panel(text: String, armed: Bool, finishing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(LocalizedStringResource("voice.listening"))
                        .foregroundStyle(.secondary)
                } else {
                    Text(verbatim: Self.newest(text))
                        .foregroundStyle(armed ? Color.secondary : Color.primary)
                }
            }
            .font(.body)
            .lineLimit(4)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("voice.text")
            HStack(spacing: 8) {
                if finishing {
                    ProgressView().controlSize(.small)
                } else {
                    levelBar
                }
                if armed {
                    Label {
                        Text(LocalizedStringResource("voice.releaseToCancel"))
                    } icon: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color("StatusError"))
                    .accessibilityIdentifier("voice.releaseToCancel")
                }
            }
            if model.limitReached {
                let limit = ComposerValidation.byteCount(model.maxBytes)
                Text(verbatim: String(localized: "voice.limit \(limit)"))
                    .font(.footnote)
                    .foregroundStyle(Color("StatusError"))
                    .accessibilityIdentifier("voice.limit")
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(armed ? Color("StatusError") : PrimaryButtonStyle.fill, lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
    }

    /// The characters shown of a long dictation.
    static let shownCharacters = 160

    /// The end of `text` (the newest words), from a word boundary, after "…" when cut.
    static func newest(_ text: String) -> String {
        guard text.count > shownCharacters else { return text }
        let tail = text.suffix(shownCharacters)
        let start = tail.firstIndex(where: \.isWhitespace).map { tail.index(after: $0) } ?? tail.startIndex
        return "…" + tail[start...]
    }

    /// A capsule filled as loud as the microphone is.
    private var levelBar: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.2))
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(PrimaryButtonStyle.fill)
                        .frame(width: max(6, proxy.size.width * level))
                }
            }
            .frame(maxWidth: 160)
            .animation(.linear(duration: 0.08), value: level)
            .accessibilityHidden(true)
    }

    private func notice(_ text: LocalizedStringResource, settings: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "mic.slash")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                if settings {
                    Button(String(localized: "voice.openSettings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color("AccentText"))
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("voice.openSettings")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text(LocalizedStringResource("common.close")))
        }
        .padding(.leading, 12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("voice.notice")
    }
}
