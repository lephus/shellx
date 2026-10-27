import ShellXAppCore
import SwiftUI

/// The mic (spec section 4): a round #60a5fa button with a #0b1220 mic, held to talk. Lifting the
/// finger hands the words to `onText`; dragging left arms cancel (`VoiceInputModel.drag`); swiping
/// up before any word asks for the keyboard (the host watches `wantsKeyboard`). A light tap starts,
/// success sends, a warning cancels (haptics).
///
/// With VoiceOver on, the hold gesture is off and the button works by taps: the first starts
/// listening, the next one finishes. "Cancel" (while listening) and "Type instead" are actions of the
/// button, so neither needs a gesture.
struct MicButton: View {
    let model: VoiceInputModel
    /// What VoiceOver calls the button.
    let label: LocalizedStringResource
    var diameter: CGFloat = 58
    /// The words said, trimmed and not empty.
    let onText: (String) -> Void
    /// Opens the keyboard ("Type instead"); nil hides that action.
    var onKeyboard: (() -> Void)?

    @GestureState private var holding = false
    @State private var starts = 0
    @State private var sends = 0
    @State private var cancels = 0
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        let active = model.isActive
        Circle()
            .fill(PrimaryButtonStyle.fill)
            .frame(width: diameter, height: diameter)
            .overlay {
                Image(systemName: Self.symbol(for: model.phase))
                    .font(.system(size: diameter * 0.4, weight: .semibold))
                    .foregroundStyle(PrimaryButtonStyle.label)
            }
            .scaleEffect(active ? 1.1 : 1)
            .opacity(Self.isCancelArmed(model.phase) ? 0.55 : 1)
            .animation(.easeOut(duration: 0.15), value: active)
            .contentShape(Circle())
            .gesture(hold, including: voiceOver ? .subviews : .all)
            .onChange(of: holding) { _, isHolding in
                if isHolding { start() } else { finish() }
            }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(active ? LocalizedStringResource("voice.mic.stop") : label))
            .accessibilityHint(Text(LocalizedStringResource("voice.mic.hint")))
            .accessibilityAction { active ? finish() : start() }
            .accessibilityActions {
                if active {
                    // Dragging left is the touch way; this is the same cancel without the gesture.
                    Button(String(localized: "common.cancel")) {
                        model.drag(dx: -VoiceInputModel.cancelDistance, dy: 0)
                        finish()
                    }
                }
                if let onKeyboard {
                    Button(String(localized: "voice.keyboard"), action: onKeyboard)
                }
            }
            .accessibilityIdentifier("voice.mic")
            .sensoryFeedback(.impact(weight: .light), trigger: starts)
            .sensoryFeedback(.success, trigger: sends)
            .sensoryFeedback(.warning, trigger: cancels)
    }

    private var hold: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($holding) { _, state, _ in state = true }
            .onChanged { value in model.drag(dx: value.translation.width, dy: value.translation.height) }
    }

    private func start() {
        guard !model.isActive else { return }
        starts += 1
        Task { await model.press() }
    }

    private func finish() {
        let armed = Self.isCancelArmed(model.phase)
        Task {
            if let text = await model.release() {
                sends += 1
                onText(text)
            } else if armed {
                cancels += 1
            }
        }
    }

    static func symbol(for phase: VoiceInputModel.Phase) -> String {
        switch phase {
        case .idle, .finishing: return "mic.fill"
        case .listening: return "waveform"
        case .cancelArmed: return "xmark"
        case .denied, .unavailable: return "mic.slash.fill"
        }
    }

    private static func isCancelArmed(_ phase: VoiceInputModel.Phase) -> Bool {
        if case .cancelArmed = phase { return true }
        return false
    }
}
