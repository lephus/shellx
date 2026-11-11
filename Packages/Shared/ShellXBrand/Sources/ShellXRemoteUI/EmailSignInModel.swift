import Foundation
import Observation
import ShellXRemoteCore

/// State of the email part of the sign-in sheet. The two calls are injected (`ShellXAccount`), so this module stays free
/// of the account and the bundle. Nothing here logs an address, a code or a challenge id.
///
/// The sheet opens on ``Step/email``. Send code mails a code and shows the code step; the sixth digit verifies by
/// itself. How each relay answer changes the steps is the desktop decision D2:
///
/// ```swift
/// let model = EmailSignInModel(
///     labels: .english,
///     requestCode: { try await account.requestEmailCode(email: $0, locale: "en") },
///     verify: { try await account.signInWithEmailCode(challengeID: $0, code: $1).email }
/// )
/// model.setEmail("foo@bar.com")
/// model.sendCode()
/// ```
@MainActor
@Observable
public final class EmailSignInModel {
    /// Where the sheet is in the email flow.
    public enum Step: Equatable, Sendable {
        /// The address field and Send code (the sheet's first screen).
        case email
        /// A code is being requested (Send code or Resend).
        case sending
        /// The code field; the challenge may be dead (see ``EmailSignInModel/codeIsLive``).
        case code
        /// The code is being verified.
        case verifying
        /// Signed in to the account with this address.
        case done(email: String)
    }

    /// The number of digits in a code.
    public static let codeLength = 6

    /// The current step; ``Step/email`` at first, so the sheet opens on the address.
    public private(set) var step: Step = .email
    /// What the email field holds; kept through the code step and back.
    public private(set) var email = ""
    /// The last failure as a sentence.
    public private(set) var errorText: String?
    /// The relay's address while the code step shows; nil on the email step.
    public private(set) var sentTo: String?
    /// The typed code: ASCII digits only, at most ``codeLength``.
    public private(set) var code = ""
    /// Grows each time the shown field should take the keyboard: when the step becomes ``Step/email``, or
    /// ``Step/code`` with a live challenge.
    public private(set) var focusRequest = 0
    /// Called once when the sheet should close: `true` after ``finish()``, `false` after ``cancel()``.
    @ObservationIgnored public var onFinished: (@MainActor (Bool) -> Void)?

    /// The challenge the relay may still take; nil once it is dead or dropped.
    private var challenge: EmailCodeChallenge?
    /// When Resend unlocks; nil when it is unlocked.
    private var resendUnlocksAt: Date?
    @ObservationIgnored private let labels: SignInErrorLabels
    @ObservationIgnored private let requestCode: @MainActor (String) async throws -> EmailCodeChallenge
    @ObservationIgnored private let verifyCode: @MainActor (String, String) async throws -> String
    @ObservationIgnored private let now: @MainActor () -> Date
    /// Grows with each request, `useDifferentEmail()` and `cancel()`; an answer for an older value is ignored.
    @ObservationIgnored private var requestID = 0
    @ObservationIgnored private var closed = false
    @ObservationIgnored private var reported = false

    /// - Parameters:
    ///   - labels: The localized sentences for failures.
    ///   - requestCode: Mails a code to the address and returns its challenge (`ShellXAccount.requestEmailCode`).
    ///   - verify: Verifies `(challengeID, code)` and returns the account's address (`ShellXAccount.signInWithEmailCode`).
    ///   - now: The clock for the resend lock; the system clock by default, a fixed one in tests.
    public init(
        labels: SignInErrorLabels,
        requestCode: @escaping @MainActor (String) async throws -> EmailCodeChallenge,
        verify: @escaping @MainActor (String, String) async throws -> String,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.labels = labels
        self.requestCode = requestCode
        self.verifyCode = verify
        self.now = now
    }

    // MARK: - Derived state

    /// The sentence under the email field: ``errorText``, else the invalid-email sentence while the trimmed address
    /// holds a character outside ASCII (D4: shown as soon as it is typed).
    public var emailFieldError: String? {
        if let errorText { return errorText }
        return Self.isASCII(Self.trimmed(email)) ? nil : labels.invalidEmail
    }

    /// Send code can be pressed: the email step with a plausible address.
    public var canSend: Bool { step == .email && Self.isPlausibleEmail(email) }
    /// A challenge the relay may still take.
    public var codeIsLive: Bool { challenge != nil }
    /// The code field takes input: the code step with a live challenge.
    public var canEditCode: Bool { step == .code && codeIsLive }
    /// Verify can be pressed: the code step, a live challenge and six digits.
    public var canVerify: Bool { canEditCode && code.count == Self.codeLength }
    /// A request is on its way.
    public var isBusy: Bool { step == .sending || step == .verifying }

    // MARK: - Text rules

    /// Whether `text`, trimmed, can be sent: ASCII only, no whitespace inside, an "@" that is not first, then a "."
    /// neither right after it nor last. The relay checks the rest.
    ///
    /// - Parameter text: The address as typed.
    /// - Returns: True when Send code may be pressed.
    public static func isPlausibleEmail(_ text: String) -> Bool {
        let address = trimmed(text)
        guard !address.isEmpty, isASCII(address), !address.contains(where: \.isWhitespace),
              let at = address.lastIndex(of: "@"), at != address.startIndex else { return false }
        let domain = address[address.index(after: at)...]
        guard let first = domain.first, let last = domain.last else { return false }
        return domain.contains(".") && first != "." && last != "."
    }

    /// The first six Unicode decimal digits (General_Category Nd) of `raw`, as ASCII, so full-width and Arabic-Indic
    /// digits count (the phones' rule).
    ///
    /// - Parameter raw: What was typed or pasted, the mail's subject around the code included.
    /// - Returns: At most ``codeLength`` ASCII digits, leading zeros kept.
    public static func digits(_ raw: String) -> String {
        var result = ""
        for scalar in raw.unicodeScalars where result.count < codeLength {
            guard scalar.properties.generalCategory == .decimalNumber,
                  let value = scalar.properties.numericValue, value >= 0, value <= 9 else { continue }
            result.append(String(Int(value)))
        }
        return result
    }

    // MARK: - Email step

    /// The email field changed (only on the email step). Clears the shown failure.
    ///
    /// - Parameter text: The field's text.
    public func setEmail(_ text: String) {
        guard step == .email, !closed else { return }
        email = text
        errorText = nil
    }

    /// Mails a code to the trimmed address and shows the code step.
    ///
    /// - Returns: The request's task, or nil when ``canSend`` is false (nothing is sent).
    @discardableResult
    public func sendCode() -> Task<Void, Never>? {
        guard canSend, !closed else { return nil }
        email = Self.trimmed(email)
        return request(resending: false)
    }

    // MARK: - Code step

    /// Mails a new code to the kept address once the lock is over (the relay replaces the old challenge).
    ///
    /// - Returns: The request's task, or nil outside the code step or while ``resendWait(at:)`` is above zero.
    @discardableResult
    public func resend() -> Task<Void, Never>? {
        guard step == .code, !closed, resendWait(at: now()) == 0 else { return nil }
        return request(resending: true)
    }

    /// Whole seconds until Resend unlocks, rounded up; 0 means unlocked.
    ///
    /// - Parameter date: The moment to measure at (the view's timeline date).
    /// - Returns: The seconds left.
    public func resendWait(at date: Date) -> Int {
        guard let unlock = resendUnlocksAt else { return 0 }
        let left = unlock.timeIntervalSince(date)
        return left > 0 ? Int(left.rounded(.up)) : 0
    }

    /// The code field changed: stores ``digits(_:)`` of `raw`. A change clears the shown failure, and a change to six
    /// digits verifies by itself.
    ///
    /// - Parameter raw: The field's text.
    /// - Returns: The verify task when the sixth digit submitted, else nil.
    @discardableResult
    public func setCode(_ raw: String) -> Task<Void, Never>? {
        guard canEditCode, !closed else { return nil }
        let next = Self.digits(raw)
        guard next != code else { return nil }
        code = next
        errorText = nil
        return next.count == Self.codeLength ? submitCode() : nil
    }

    /// Verifies the typed code (the Verify button and Return).
    ///
    /// - Returns: The verify task, or nil unless ``canVerify``.
    @discardableResult
    public func submitCode() -> Task<Void, Never>? {
        guard canVerify, !closed, let challengeID = challenge?.challengeID else { return nil }
        let digits = code
        step = .verifying
        errorText = nil
        requestID += 1
        let id = requestID
        return Task { [weak self] in
            guard let self else { return }
            do {
                let address = try await verifyCode(challengeID, digits)
                guard id == requestID else { return }
                step = .done(email: address)
            } catch {
                guard id == requestID else { return }
                verifyFailed(error)
            }
        }
    }

    /// Forgets the shown failure.
    public func clearError() {
        errorText = nil
    }

    /// Asks the shown field to take the keyboard again (``focusRequest`` grows), for when another flow took it away:
    /// a field turned off while it has the keyboard loses it. Only while that field takes input: the email step, or
    /// the code step with a live challenge; never after the sheet closed.
    public func requestFocus() {
        guard !closed, step == .email || canEditCode else { return }
        focusRequest += 1
    }

    /// Back to the email step with the address kept; the challenge, the digits, the failure and the lock are dropped.
    public func useDifferentEmail() {
        guard step == .code, !closed else { return }
        requestID += 1
        challenge = nil
        sentTo = nil
        code = ""
        errorText = nil
        resendUnlocksAt = nil
        showEmailStep()
    }

    // MARK: - Closing

    /// Closes the sheet: reports `false` once, and every answer still on its way changes nothing. A request already
    /// sent is never cancelled, so a verify that succeeds after the close still leaves the account signed in.
    public func cancel() {
        requestID += 1
        closed = true
        guard !reported else { return }
        reported = true
        onFinished?(false)
    }

    /// The person confirmed "Signed in as …" (only in ``Step/done(email:)``): reports `true` once.
    public func finish() {
        guard case .done = step, !reported else { return }
        reported = true
        closed = true
        onFinished?(true)
    }

    // MARK: - Private

    private func request(resending: Bool) -> Task<Void, Never> {
        let address = email
        step = .sending
        errorText = nil
        requestID += 1
        let id = requestID
        return Task { [weak self] in
            guard let self else { return }
            do {
                let challenge = try await requestCode(address)
                guard id == requestID else { return }
                showCodeStep(challenge)
            } catch {
                guard id == requestID else { return }
                if resending { resendFailed(error) } else { sendFailed(error) }
            }
        }
    }

    private func showCodeStep(_ challenge: EmailCodeChallenge) {
        self.challenge = challenge
        sentTo = challenge.email
        code = ""
        errorText = nil
        resendUnlocksAt = now().addingTimeInterval(challenge.resendIn)
        step = .code
        focusRequest += 1
    }

    private func showEmailStep() {
        step = .email
        focusRequest += 1
    }

    /// Send code failed: back to the email step with the sentence (a 429 can be sent again at once).
    private func sendFailed(_ error: any Error) {
        errorText = SignInErrorMessage.emailText(for: error, labels: labels)
        showEmailStep()
    }

    /// Resend failed: the lock ends. The relay holds no live code after `email_send_failed` and
    /// `email_sign_in_disabled`, so the challenge and digits go; any other failure keeps the challenge (D2).
    private func resendFailed(_ error: any Error) {
        resendUnlocksAt = nil
        if ["email_send_failed", "email_sign_in_disabled"].contains(Self.code(of: error)) {
            challenge = nil
            code = ""
        }
        errorText = SignInErrorMessage.emailText(for: error, labels: labels)
        step = .code
        if codeIsLive { focusRequest += 1 }
    }

    /// Verify failed: the D2 rows for 401, 410 and 409; any other failure keeps the digits and the challenge.
    private func verifyFailed(_ error: any Error) {
        errorText = SignInErrorMessage.emailText(for: error, labels: labels)
        switch Self.code(of: error) {
        case "invalid_code":
            code = ""
        case "code_expired":
            code = ""
            challenge = nil
            resendUnlocksAt = nil
        case "switch_from_signed_in_device":
            code = ""
            challenge = nil
            sentTo = nil
            resendUnlocksAt = nil
            showEmailStep()
            return
        default:
            break
        }
        step = .code
        if codeIsLive { focusRequest += 1 }
    }

    /// The core's code, or `network` for an error thrown before the core answered.
    private static func code(of error: any Error) -> String {
        (error as? ShellXCoreError)?.code ?? "network"
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isASCII(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy(\.isASCII)
    }
}
