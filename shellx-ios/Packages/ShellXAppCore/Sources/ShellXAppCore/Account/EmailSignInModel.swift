import Foundation
import Observation
import ShellXLinkAccount

/// Sign-in with a code sent by email: the steps, what was typed, the Resend lock and the failure to show. The same
/// model runs the code step of Delete Account for an email session (other `request` and `submit`, `autoSubmit` false).
///
/// Nothing here logs or describes an address, a code or a challenge id.
@MainActor @Observable
public final class EmailSignInModel {
    public enum Step: Equatable, Sendable { case idle, email, sending, code, verifying, done }
    /// What the screen shows: `.providers` for idle and done; `.email` for email and a first sending; `.code` for code,
    /// verifying and the sending of a resend.
    public enum Panel: Equatable, Sendable { case providers, email, code }

    public nonisolated static let codeLength = 6
    public nonisolated static let maxEmailBytes = 254

    /// Trimmed, it is ASCII only, it has an "@" that is not first, and after it a "." that is neither the next
    /// character nor the last. Only whether Send is worth pressing: the relay does the real check.
    public nonisolated static func looksLikeEmail(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isASCII(trimmed), let at = trimmed.firstIndex(of: "@"), at != trimmed.startIndex else { return false }
        let domain = trimmed[trimmed.index(after: at)...]
        return domain.indices.contains { domain[$0] == "." && $0 != domain.startIndex && domain.index(after: $0) != domain.endIndex }
    }

    /// Whether every character of `text` is ASCII. The relay takes ASCII addresses only, and a Vietnamese keyboard
    /// (Telex) turns "ex" into "ẽ" even in an email field.
    public nonisolated static func isASCII(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy(\.isASCII)
    }

    /// The first six digits of `text` as ASCII (any character with a `wholeNumberValue` of 0–9 counts); the rest is
    /// dropped. A pasted "123 456", or the subject of the mail, gives the code.
    public nonisolated static func digits(_ text: String) -> String {
        var digits = ""
        for character in text {
            guard let value = character.wholeNumberValue, (0...9).contains(value) else { continue }
            digits.append(String(value))
            if digits.count == codeLength { break }
        }
        return digits
    }

    public private(set) var step: Step = .idle
    /// What the email field holds.
    public var email = ""
    /// 0–6 ASCII digits.
    public private(set) var code = ""
    /// The address as the relay normalized it; nil until a code was sent.
    public private(set) var sentTo: String?
    /// Whole seconds until Resend unlocks, rounded up; 0 when it can be pressed.
    public private(set) var resendIn = 0
    public private(set) var error: SignInError?

    public var panel: Panel {
        switch step {
        case .idle, .done: .providers
        case .email: .email
        case .sending: sentTo == nil ? .email : .code
        case .code, .verifying: .code
        }
    }
    public var isEntering: Bool { panel != .providers }
    public var isBusy: Bool { step == .sending || step == .verifying }
    public var canSend: Bool { step == .email && Self.looksLikeEmail(email) }
    /// What shows under the email field: the last failure, else `.invalidEmail` while the address has a character
    /// outside ASCII, so that a disabled Send says why. An address still being typed is not wrong.
    public var emailFieldError: SignInError? {
        if let error { return error }
        return Self.isASCII(email.trimmingCharacters(in: .whitespacesAndNewlines)) ? nil : .invalidEmail
    }
    /// A code was sent and can still be verified: false before a send and after a 410.
    public var codeIsLive: Bool { challengeID != nil }
    public var canVerify: Bool { step == .code && code.count == Self.codeLength && codeIsLive }
    public var canResend: Bool { step == .code && resendIn == 0 }

    /// Signs in (or deletes) together with the mailed code; nil before a send, after a 410 and once it was used.
    private var challengeID: String?
    @ObservationIgnored private var lock: ResendLock?
    @ObservationIgnored private var countdown: Task<Void, Never>?
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let autoSubmit: Bool
    @ObservationIgnored private let request: @MainActor (String) async throws -> EmailChallenge
    @ObservationIgnored private let submit: @MainActor (_ challengeID: String, _ code: String) async throws -> Void

    /// `request` mails a code to the address it is given; `submit` uses the code. With `autoSubmit` the sixth digit
    /// submits by itself.
    init(
        clock: any Clock<Duration>, autoSubmit: Bool = true,
        request: @escaping @MainActor (String) async throws -> EmailChallenge,
        submit: @escaping @MainActor (_ challengeID: String, _ code: String) async throws -> Void
    ) {
        self.clock = clock
        self.autoSubmit = autoSubmit
        self.request = request
        self.submit = submit
    }

    /// Opens the email step, with `email` in the field when given.
    public func begin(email: String? = nil) {
        guard step == .idle || step == .done else { return }
        if let email { self.email = email }
        error = nil
        step = .email
    }

    /// Back to the Google and Apple buttons. The address stays for the next time.
    public func cancel() {
        guard step == .email || step == .code else { return }
        dropCode()
        step = .idle
    }

    /// "Use a different email": back to the email step.
    public func changeEmail() {
        guard step == .code else { return }
        dropCode()
        step = .email
    }

    /// Mails a code to the address in the field.
    public func sendCode() async {
        guard canSend else { return }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if address != email { email = address }
        guard address.utf8.count <= Self.maxEmailBytes else {
            error = .invalidEmail
            return
        }
        error = nil
        step = .sending
        do {
            keep(try await request(address))
        } catch let failure {
            error = Self.signInError(failure)
            step = .email
        }
    }

    /// Mails a new code to the same address, once the lock is over. The new code replaces the old one.
    public func resend() async {
        guard canResend, let sentTo else { return }
        error = nil
        step = .sending
        do {
            keep(try await request(sentTo))
        } catch let failure {
            error = Self.signInError(failure)
            step = .code
        }
    }

    /// What the code field holds now. Only its first six digits are kept; with `autoSubmit`, the sixth one submits.
    public func setCode(_ text: String) {
        guard step == .code, codeIsLive else { return }
        let digits = Self.digits(text)
        guard digits != code else { return }
        code = digits
        if error == .invalidCode { error = nil }
        if autoSubmit, digits.count == Self.codeLength {
            Task { await self.verify() }
        }
    }

    /// Submits the six digits. One request at a time: a second call while one runs does nothing.
    public func verify() async {
        guard canVerify, let challengeID else { return }
        let code = code
        error = nil
        step = .verifying
        do {
            try await submit(challengeID, code)
            dropCode()
            email = ""
            step = .done
        } catch let failure {
            let failure = Self.signInError(failure)
            error = failure
            switch failure {
            case .invalidCode:
                // The challenge lives on: the same mail, another try.
                self.code = ""
                step = .code
            case .codeExpired:
                // The code is dead (expired, used, or the fifth wrong try): only a new one helps, so Resend unlocks.
                self.code = ""
                self.challengeID = nil
                endLock()
                step = .code
            case .switchFromSignedInDevice:
                // This address cannot go on: back to the email step, with the message.
                dropCode()
                error = failure
                step = .email
            default:
                step = .code
            }
        }
    }

    /// A code was mailed: the code step, with the lock the relay asked for.
    private func keep(_ challenge: EmailChallenge) {
        challengeID = challenge.challengeID
        sentTo = challenge.email
        code = ""
        step = .code
        startLock(seconds: challenge.resendIn)
    }

    /// Forgets the challenge, the digits, the address the code went to, the failure and the lock.
    private func dropCode() {
        challengeID = nil
        code = ""
        sentTo = nil
        error = nil
        endLock()
    }

    private static func signInError(_ error: any Error) -> SignInError {
        (error as? SignInError) ?? .server(code: "unknown")
    }

    // MARK: - The Resend lock

    private func startLock(seconds: Int) {
        countdown?.cancel()
        countdown = nil
        // A local, because the compiler opens the clock existential for a generic call from a local or a parameter,
        // not from a stored property.
        let clock = clock
        lock = Self.resendLock(clock, total: .seconds(max(0, seconds)))
        refreshResendIn()
        guard resendIn > 0 else { return }
        // One task per lock. It reads the time left from the clock on every pass, so a late wake (the app was in the
        // background) shows the right number at once, and it ends when the lock does.
        countdown = Task { [weak self] in
            while !Task.isCancelled {
                guard let wait = self?.nextTick() else { return }
                do { try await wait() } catch { return }
            }
        }
    }

    /// Refreshes `resendIn` and returns the wait until it changes next; nil once the lock is over.
    private func nextTick() -> (@Sendable () async throws -> Void)? {
        refreshResendIn()
        guard let lock, resendIn > 0 else { return nil }
        // The number changes when the time left crosses a whole second.
        let next = lock.total - .seconds(resendIn - 1)
        return { try await lock.sleepUntilElapsed(next) }
    }

    private func endLock() {
        countdown?.cancel()
        countdown = nil
        lock = nil
        resendIn = 0
    }

    private func refreshResendIn() {
        guard let lock else {
            resendIn = 0
            return
        }
        let left = (lock.total - lock.elapsed()).components
        let seconds = left.seconds < 0 ? 0 : Int(left.seconds) + (left.attoseconds > 0 ? 1 : 0)
        if seconds != resendIn { resendIn = seconds }
    }

    /// A lock of `total` that starts now on `clock`. Generic, so the clock existential is opened once here.
    private static func resendLock<C: Clock<Duration>>(_ clock: C, total: Duration) -> ResendLock {
        let start = clock.now
        return ResendLock(
            total: total,
            elapsed: { start.duration(to: clock.now) },
            sleepUntilElapsed: { try await clock.sleep(until: start.advanced(by: $0), tolerance: nil) })
    }
}

/// The Resend lock of one sent code, on the clock it started on.
private struct ResendLock: Sendable {
    let total: Duration
    /// The time since the code was sent.
    let elapsed: @Sendable () -> Duration
    /// Returns once `elapsed()` reached the given duration; throws when the task is cancelled.
    let sleepUntilElapsed: @Sendable (Duration) async throws -> Void
}

/// The language the relay writes the code mail in.
public enum EmailCodeLocale {
    /// "vi" for Vietnamese ("vi", "vi-VN", "VI"), "en" for anything else (spec §3).
    public static func relayValue(appLanguage: String) -> String {
        let language = appLanguage.lowercased()
        return language == "vi" || language.hasPrefix("vi-") || language.hasPrefix("vi_") ? "vi" : "en"
    }

    /// For the language the app shows: `Bundle.main.preferredLocalizations.first`.
    public static var current: String {
        relayValue(appLanguage: Bundle.main.preferredLocalizations.first ?? "")
    }
}
