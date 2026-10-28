import ShellXAppCore
import SwiftUI

/// The mic (spec section 4): a round button held to talk, soft blue with a thin border and an outline
/// mic at rest; while listening it turns solid #60a5fa with a #0b1220 waveform, and two thin rings
/// grow with the voice (still under Reduce Motion). Lifting the
/// finger hands what was said to `onOutcome` (`VoiceInputModel.outcome(for:)`); dragging left arms
/// cancel (`VoiceInputModel.drag`); swiping up before any word asks for the keyboard (the host
/// watches `wantsKeyboard`). Only a lift sends: a hold taken away without one (a pager or a scroll
/// view claimed the touch) cancels (`MicHold`). Haptics: a light tap as listening starts, success when the words are
/// taken whole (not for words stopped at the byte limit, which go to a field to be read), a warning
/// on cancel.
///
/// With VoiceOver on, the hold gesture is off and the button works by taps: the first starts
/// listening, the next one finishes. "Cancel" (while listening) and "Type instead" are actions of the
/// button, so neither needs a gesture. The host's "Type instead" cancels a dictation in progress
/// (`VoiceInputModel.typeInstead()`).
struct MicButton: View {
    let model: VoiceInputModel
    /// What VoiceOver calls the button.
    let label: LocalizedStringResource
    var diameter: CGFloat = 58
    /// What was said (trimmed, not empty), whole or stopped at the limit.
    let onOutcome: (DictationOutcome) -> Void
    /// Opens the keyboard ("Type instead"); nil hides that action.
    var onKeyboard: (() -> Void)?
    /// Listening was asked for (a press, or VoiceOver's first tap), before the recognizer starts.
    var onPress: (() -> Void)?
    /// Released with nothing to send: nothing was said, the dictation was cancelled, or the mic
    /// could not listen.
    var onNothing: (() -> Void)?

    @GestureState private var holding = false
    /// What the hold's signals ask for.
    @State private var hold = MicHold()
    @State private var starts = 0
    @State private var sends = 0
    @State private var cancels = 0
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(VoiceService.self) private var voiceService: VoiceService?

    var body: some View {
        let active = model.isActive
        ZStack {
            if active { rings(level: voiceService?.meter.level ?? 0) }
            Circle()
                .fill(active ? PrimaryButtonStyle.fill : Color("AccentColor").opacity(0.15))
            Circle()
                .strokeBorder(Color("AccentColor").opacity(active ? 0 : 0.45), lineWidth: 1)
            Image(systemName: Self.symbol(for: model.phase))
                .font(.system(size: diameter * 0.4, weight: active ? .bold : .medium))
                .foregroundStyle(active ? PrimaryButtonStyle.label : Color("AccentText"))
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(active ? 1.06 : 1)
        .opacity(Self.isCancelArmed(model.phase) ? 0.55 : 1)
        .animation(.easeOut(duration: 0.15), value: active)
        .contentShape(Circle())
        .gesture(holdGesture, including: voiceOver ? .subviews : .all)
        .onChange(of: holding) { _, isHolding in
            perform(hold.holdingChanged(isHolding))
            guard !isHolding else { return }
            // `onEnded` and the reset state can come in either order: decide once both had their turn.
            Task { @MainActor in perform(hold.settle()) }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(active ? LocalizedStringResource("voice.mic.stop") : label))
        .accessibilityHint(Text(LocalizedStringResource("voice.mic.hint")))
        .accessibilityAction { active ? finish() : start() }
        .accessibilityActions {
            if active {
                // Dragging left is the touch way; this is the same cancel without the gesture.
                Button(String(localized: "common.cancel"), action: cancel)
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

    /// Two thin rings around the solid button, wider as the voice gets louder; still, at a middle
    /// size, under Reduce Motion.
    private func rings(level: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color("AccentColor").opacity(0.45), lineWidth: 1.5)
                .scaleEffect(reduceMotion ? 1.25 : 1.15 + level * 0.25)
            Circle()
                .stroke(Color("AccentColor").opacity(0.22), lineWidth: 1)
                .scaleEffect(reduceMotion ? 1.5 : 1.35 + level * 0.45)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($holding) { _, state, _ in state = true }
            .onChanged { value in model.drag(dx: value.translation.width, dy: value.translation.height) }
            .onEnded { _ in perform(hold.ended()) }
    }

    private func perform(_ step: MicHold.Step) {
        switch step {
        case .press: start()
        case .release: finish()
        case .cancel: cancel()
        case .none: break
        }
    }

    private func start() {
        guard !model.isActive else { return }
        starts += 1
        onPress?()
        Task { await model.press() }
    }

    /// Drops what was heard, as a drag to the left and a lift do.
    private func cancel() {
        model.drag(dx: -VoiceInputModel.cancelDistance, dy: 0)
        finish()
    }

    private func finish() {
        let armed = Self.isCancelArmed(model.phase)
        Task {
            if let text = await model.release() {
                let outcome = model.outcome(for: text)
                if case .complete = outcome { sends += 1 }
                onOutcome(outcome)
            } else {
                if armed { cancels += 1 }
                onNothing?()
            }
        }
    }

    static func symbol(for phase: VoiceInputModel.Phase) -> String {
        switch phase {
        case .idle, .finishing: return "mic"
        case .listening: return "waveform"
        case .cancelArmed: return "xmark"
        case .denied, .unavailable: return "mic.slash"
        }
    }

    private static func isCancelArmed(_ phase: VoiceInputModel.Phase) -> Bool {
        if case .cancelArmed = phase { return true }
        return false
    }
}
