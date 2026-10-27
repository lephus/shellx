import Speech

/// A running `SFSpeechRecognizer` recognition, as `LegacyTranscriber` needs it: something it can
/// cancel. Tests stand in for the system's task.
protocol RecognitionTask: AnyObject {
    func cancel()
}

extension SFSpeechRecognitionTask: RecognitionTask {}
