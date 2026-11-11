package com.shellx.core.account

import com.shellx.core.account.EmailSignInState.Step
import com.shellx.core.platform.Clock
import com.shellx.link.account.EmailChallenge
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * What the email and code steps show (sign-in, and Delete Account for an email session). Neither the email nor the
 * code prints.
 */
data class EmailSignInState(
    val step: Step = Step.IDLE,
    /** As typed; from the relay's 202 on, the relay's spelling (trimmed, lower case). */
    val email: String = "",
    /** ASCII digits, at most [EmailSignInModel.CODE_LENGTH]. */
    val code: String = "",
    /** The code step: seconds until "Resend code" is allowed; 0: allowed. */
    val resendInSeconds: Int = 0,
    val resending: Boolean = false,
    /** The relay said `code_expired`: only Resend or another address helps. */
    val codeDead: Boolean = false,
    val error: SignInException? = null,
) {
    /** IDLE: no email step shows. SENDING and VERIFYING: a request is on the relay. DONE: signed in (or deleted). */
    enum class Step { IDLE, EMAIL, SENDING, CODE, VERIFYING, DONE }

    val canSend: Boolean get() = step == Step.EMAIL && EmailSignInModel.looksLikeEmail(email)

    val canVerify: Boolean get() = step == Step.CODE && code.length == EmailSignInModel.CODE_LENGTH && !codeDead && !resending

    val canResend: Boolean get() = step == Step.CODE && resendInSeconds == 0 && !resending

    /** A request is on the relay, or the step is over: nothing takes a tap. */
    val busy: Boolean get() = step == Step.SENDING || step == Step.VERIFYING || step == Step.DONE || resending

    override fun toString(): String = "EmailSignInState(step=$step, resendInSeconds=$resendInSeconds, resending=$resending, " +
        "codeDead=$codeDead, error=${error?.message}, <redacted>)"
}

/**
 * The email and code steps behind a screen: idle → email → sending → code → verifying → done, with the failures of
 * each request and the "Resend code" countdown. Main-confined. Every method returns at once; requests run in [scope].
 *
 * The countdown is read from [clock]'s wall time each second, never counted in ticks: time spent in the background, or
 * in a process that was killed, counts ([Saved] carries the deadlines). It is advice; the relay enforces the limit.
 * With [autoSubmit] the sixth digit verifies by itself (sign-in); without it only [verify] does (Delete Account).
 */
class EmailSignInModel(
    private val actions: EmailCodeActions,
    private val clock: Clock,
    private val scope: CoroutineScope,
    private val autoSubmit: Boolean = true,
    private val sleep: suspend (Duration) -> Unit = { delay(it) },
    restored: Saved? = null,
) {
    /**
     * What a killed process needs to come back to its step; never the typed code. [challengeId] null: the email step.
     * The deadlines are wall-clock milliseconds ([Clock.nowMs]).
     */
    data class Saved(val email: String, val challengeId: String?, val expiresAtMs: Long, val resendAtMs: Long) {
        override fun toString(): String = "Saved(codeStep=${challengeId != null}, <redacted>)"
    }

    private val _state = MutableStateFlow(EmailSignInState())
    val state: StateFlow<EmailSignInState> = _state.asStateFlow()

    /** The live challenge of the code step. */
    private var challengeId: String? = null
    private var expiresAtMs = 0L
    private var resendAtMs = 0L
    private var ticker: Job? = null

    /**
     * The expired challenge this model was restored from, while its email step still says "expired": [saved] hands it
     * back as it was, so a window made a second time on the way back (the host replaces its restored page) says so too.
     * Gone once the address changes, a code is asked for or the step is left.
     */
    private var expiredRestore: Saved? = null

    init {
        if (restored != null) {
            val id = restored.challengeId
            when {
                id == null -> _state.value = EmailSignInState(Step.EMAIL, email = restored.email)
                restored.expiresAtMs > clock.nowMs() -> {
                    challengeId = id
                    expiresAtMs = restored.expiresAtMs
                    resendAtMs = restored.resendAtMs
                    _state.value = EmailSignInState(Step.CODE, email = restored.email, resendInSeconds = resendIn())
                    startTicker()
                }
                else -> {
                    expiredRestore = restored
                    _state.value = EmailSignInState(Step.EMAIL, email = restored.email, error = SignInException.CodeExpired())
                }
            }
        }
    }

    /** IDLE → EMAIL. [email], when given, replaces the one kept from before. Clears the error. */
    fun start(email: String? = null) {
        val current = _state.value
        if (current.step != Step.IDLE) return
        _state.value = current.copy(step = Step.EMAIL, email = email?.take(MAX_EMAIL_LENGTH) ?: current.email, error = null)
    }

    /** The email step only: [text] cut to [MAX_EMAIL_LENGTH]. A change clears the error. */
    fun setEmail(text: String) {
        val current = _state.value
        val email = text.take(MAX_EMAIL_LENGTH)
        if (current.step != Step.EMAIL || email == current.email) return
        expiredRestore = null
        _state.value = current.copy(email = email, error = null)
    }

    /** Asks for a code in [locale] ("en" or "vi"): EMAIL → SENDING → CODE, or back to EMAIL with the failure. */
    fun send(locale: String) {
        val current = _state.value
        if (!current.canSend) return
        expiredRestore = null
        _state.value = current.copy(step = Step.SENDING, error = null)
        scope.launch {
            try {
                accept(actions.requestCode(current.email.trim(), locale))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.value = _state.value.copy(step = Step.EMAIL, error = failure(e))
            }
        }
    }

    /**
     * The code step, unless its code is dead: the digits of [text] ([digits]). A change clears the error and, with
     * autoSubmit, verifies once there are [CODE_LENGTH] digits.
     */
    fun setCode(text: String) {
        val current = _state.value
        val code = digits(text)
        if (current.step != Step.CODE || current.codeDead || code == current.code) return
        _state.value = current.copy(code = code, error = null)
        if (autoSubmit && code.length == CODE_LENGTH) verify()
    }

    /** CODE with six digits → VERIFYING → DONE, or back to CODE (or EMAIL) with the failure. */
    fun verify() {
        val current = _state.value
        val id = challengeId
        if (!current.canVerify || id == null) return
        _state.value = current.copy(step = Step.VERIFYING, error = null)
        scope.launch {
            try {
                actions.verify(id, current.code)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                verifyFailed(failure(e))
                return@launch
            }
            ticker?.cancel()
            _state.value = _state.value.copy(step = Step.DONE, error = null)
        }
    }

    /** Asks for a new code for the same address once the countdown is over (or the code is dead). */
    fun resend(locale: String) {
        val current = _state.value
        if (!current.canResend) return
        _state.value = current.copy(resending = true, error = null)
        scope.launch {
            try {
                accept(actions.requestCode(current.email.trim(), locale))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.value = _state.value.copy(resending = false, error = failure(e))
            }
        }
    }

    /** "Use a different email": CODE → EMAIL. The address stays; the challenge, the digits and the error go. */
    fun changeEmail() {
        val current = _state.value
        if (current.step != Step.CODE || current.resending) return
        toEmailStep(error = null)
    }

    /**
     * System Back: CODE → EMAIL → IDLE (the address is kept for the next [start]). True when Back was taken: also while
     * a request is on the relay, when nothing moves. False in IDLE and DONE.
     */
    fun back(): Boolean {
        val current = _state.value
        when (current.step) {
            Step.IDLE, Step.DONE -> return false
            Step.SENDING, Step.VERIFYING -> Unit
            Step.CODE -> changeEmail()
            Step.EMAIL -> {
                expiredRestore = null
                _state.value = current.copy(step = Step.IDLE, error = null)
            }
        }
        return true
    }

    /**
     * What a killed process needs; null in IDLE and DONE. A dead code, like the email step, saves the address only; an
     * email step that came from an expired restore saves what it was restored from.
     */
    fun saved(): Saved? {
        val current = _state.value
        val id = challengeId
        return when (current.step) {
            Step.IDLE, Step.DONE -> null
            Step.EMAIL -> expiredRestore ?: Saved(current.email, null, 0, 0)
            Step.SENDING -> Saved(current.email, null, 0, 0)
            Step.CODE, Step.VERIFYING ->
                if (id == null || current.codeDead) Saved(current.email, null, 0, 0) else Saved(current.email, id, expiresAtMs, resendAtMs)
        }
    }

    /** The relay's 202: the code step for a new challenge, its countdown starting now. */
    private fun accept(challenge: EmailChallenge) {
        val now = clock.nowMs()
        challengeId = challenge.challengeId
        expiresAtMs = now + challenge.expiresIn * 1_000L
        resendAtMs = now + challenge.resendIn * 1_000L
        _state.value = _state.value.copy(
            step = Step.CODE, email = challenge.email, code = "", resendInSeconds = resendIn(), resending = false,
            codeDead = false, error = null,
        )
        startTicker()
    }

    private fun verifyFailed(error: SignInException) {
        when (error) {
            // Six new digits submit again.
            is SignInException.InvalidCode -> _state.value = _state.value.copy(step = Step.CODE, code = "", error = error)
            is SignInException.CodeExpired -> {
                ticker?.cancel()
                _state.value = _state.value.copy(step = Step.CODE, code = "", codeDead = true, resendInSeconds = 0, error = error)
            }
            // That address cannot go on.
            is SignInException.SwitchFromSignedInDevice -> toEmailStep(error)
            // The digits stay for another tap.
            else -> _state.value = _state.value.copy(step = Step.CODE, error = error)
        }
    }

    private fun toEmailStep(error: SignInException?) {
        ticker?.cancel()
        challengeId = null
        expiresAtMs = 0
        resendAtMs = 0
        _state.value = _state.value.copy(
            step = Step.EMAIL, code = "", resendInSeconds = 0, resending = false, codeDead = false, error = error,
        )
    }

    private fun failure(error: Exception): SignInException = error as? SignInException ?: SignInException.Server("unknown")

    /** The seconds until Resend is allowed, by the clock: rounded up, within 0..[MAX_RESEND_SECONDS]. */
    private fun resendIn(): Int = ((resendAtMs - clock.nowMs() + 999) / 1_000).coerceIn(0, MAX_RESEND_SECONDS.toLong()).toInt()

    /** One per challenge: reads the clock, then sleeps a second, until Resend is allowed. */
    private fun startTicker() {
        ticker?.cancel()
        ticker = scope.launch {
            while (true) {
                val left = resendIn()
                val current = _state.value
                if (current.resendInSeconds != left) _state.value = current.copy(resendInSeconds = left)
                if (left == 0) return@launch
                sleep(1.seconds)
            }
        }
    }

    companion object {
        const val CODE_LENGTH = 6

        /** The longest address the field takes (RFC 5321's limit for a path). */
        const val MAX_EMAIL_LENGTH = 254

        private const val MAX_RESEND_SECONDS = 600

        /**
         * Whether Send is worth a tap; the relay does the real check. [text] trimmed has an '@' that is not first, and
         * after it a '.' that is neither right behind the '@' nor last.
         */
        fun looksLikeEmail(text: String): Boolean {
            val trimmed = text.trim()
            val at = trimmed.indexOf('@')
            if (at < 1) return false
            val dot = trimmed.indexOf('.', at + 2)
            return dot != -1 && dot < trimmed.length - 1
        }

        /**
         * Every Unicode decimal digit of [text] as its ASCII digit, the first [CODE_LENGTH] of them: a pasted
         * "123 456", a whole pasted sentence, and full-width digits all give the code.
         */
        fun digits(text: String): String {
            val out = StringBuilder(CODE_LENGTH)
            var index = 0
            while (index < text.length && out.length < CODE_LENGTH) {
                val codePoint = text.codePointAt(index)
                val digit = Character.digit(codePoint, 10)
                if (digit >= 0) out.append('0' + digit)
                index += Character.charCount(codePoint)
            }
            return out.toString()
        }
    }
}
