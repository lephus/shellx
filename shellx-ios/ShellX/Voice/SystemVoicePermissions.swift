import AVFoundation
import ShellXAppCore
import Speech

/// The mic's permissions from iOS: the microphone (`NSMicrophoneUsageDescription`) and speech
/// recognition (`NSSpeechRecognitionUsageDescription`). Each asks once, the first time it is needed.
struct SystemVoicePermissions: VoicePermissionChecking {
    func microphone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .undetermined: return await AVAudioApplication.requestRecordPermission()
        default: return false
        }
    }

    func speech() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status == .authorized) }
            }
        default:
            return false
        }
    }
}
