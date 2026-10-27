import Foundation
import ShellXAppCore

/// `VoicePermissionChecking` with answers the test sets, counting each request. `promptPending`
/// says whether asking would show the system prompt.
public final class FakeVoicePermissions: VoicePermissionChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var microphoneAnswer: Bool
    private var speechAnswer: Bool
    private var prompting = false
    private var microphoneCount = 0
    private var speechCount = 0

    public init(microphone: Bool = true, speech: Bool = true) {
        microphoneAnswer = microphone
        speechAnswer = speech
    }

    public var microphoneGranted: Bool {
        get { lock.withLock { microphoneAnswer } }
        set { lock.withLock { microphoneAnswer = newValue } }
    }

    public var speechGranted: Bool {
        get { lock.withLock { speechAnswer } }
        set { lock.withLock { speechAnswer = newValue } }
    }

    public var promptPending: Bool {
        get { lock.withLock { prompting } }
        set { lock.withLock { prompting = newValue } }
    }

    public var microphoneRequests: Int { lock.withLock { microphoneCount } }
    public var speechRequests: Int { lock.withLock { speechCount } }

    public func needsPrompt() async -> Bool {
        promptPending
    }

    public func microphone() async -> Bool {
        lock.withLock {
            microphoneCount += 1
            return microphoneAnswer
        }
    }

    public func speech() async -> Bool {
        lock.withLock {
            speechCount += 1
            return speechAnswer
        }
    }
}
