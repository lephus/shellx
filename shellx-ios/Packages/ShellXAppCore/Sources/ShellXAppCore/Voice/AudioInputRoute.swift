import Foundation

/// When an audio route change ends a dictation: only when the input it listened to went away. An
/// output-only device leaving (AirPods used for playback, a speaker) leaves the microphone in place.
public enum AudioInputRoute {
    /// `previousInputs` and `currentInputs` name the route's input ports (their unique ids), before and
    /// after the change; `inputAvailable` is whether any input is left.
    public static func inputLost(previousInputs: Set<String>, currentInputs: Set<String>, inputAvailable: Bool) -> Bool {
        !inputAvailable || !previousInputs.subtracting(currentInputs).isEmpty
    }
}
