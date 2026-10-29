import AVFoundation

/// Converts microphone buffers to the format `SpeechAnalyzer` wants. Used from the audio thread
/// only, one buffer at a time.
final class AudioBufferConverter: @unchecked Sendable {
    private let output: AVAudioFormat
    private var converter: AVAudioConverter?

    init(to output: AVAudioFormat) {
        self.output = output
    }

    /// `buffer` in the output format; the buffer itself when it already is; nil when it cannot be
    /// converted.
    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == output { return buffer }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: output)
            converter?.primeMethod = .none
        }
        guard let converter, buffer.format.sampleRate > 0 else { return nil }
        let ratio = output.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
        let feeder = Feeder(buffer)
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, inputStatus in feeder.next(inputStatus) }
        guard status != .error, converted.frameLength > 0 else { return nil }
        return converted
    }
}

/// Hands one buffer to `AVAudioConverter`, then says there is no more for now.
private final class Feeder: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            status.pointee = .noDataNow
            return nil
        }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}
