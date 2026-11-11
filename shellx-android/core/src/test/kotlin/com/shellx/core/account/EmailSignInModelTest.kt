package com.shellx.core.account

import com.shellx.core.account.EmailSignInState.Step
import com.shellx.core.testing.Gate
import com.shellx.core.testing.ManualClock
import com.shellx.core.testing.assertSameCase
import com.shellx.link.account.EmailChallenge
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

/** The email and code steps: what each tap does, the countdown read from the clock, and what a killed process keeps. */
class EmailSignInModelTest {
    /**
     * The relay's two calls, recorded. Each waits at its gate, when one is set, then answers the next queued result; with
     * none queued a code request answers a new challenge ("c1", then "c2", …) for phu@example.com and a verify succeeds.
     */
    private class FakeActions {
        val requested = mutableListOf<Pair<String, String>>()
        val verified = mutableListOf<Pair<String, String>>()
        val codeAnswers = ArrayDeque<Result<EmailChallenge>>()
        val verifyAnswers = ArrayDeque<Result<Unit>>()
        var codeGate: Gate? = null
        var verifyGate: Gate? = null
        private var challenges = 0

        val actions = EmailCodeActions(
            requestCode = { email, locale ->
                requested += email to locale
                codeGate?.wait()
                val answer = codeAnswers.removeFirstOrNull()
                    ?: Result.success(EmailChallenge("c${++challenges}", 600, 60, "phu@example.com"))
                answer.getOrThrow()
            },
            verify = { challengeId, code ->
                verified += challengeId to code
                verifyGate?.wait()
                (verifyAnswers.removeFirstOrNull() ?: Result.success(Unit)).getOrThrow()
            },
        )

        fun failNextCode(error: Exception) {
            codeAnswers += Result.failure(error)
        }

        fun failNextVerify(error: Exception) {
            verifyAnswers += Result.failure(error)
        }
    }

    private class Rig(val clock: ManualClock, val fake: FakeActions, val model: EmailSignInModel) {
        val t0 = clock.wallMs
        val state: EmailSignInState get() = model.state.value
    }

    private fun TestScope.rig(autoSubmit: Boolean = true, restored: EmailSignInModel.Saved? = null, clock: ManualClock = ManualClock()): Rig {
        val fake = FakeActions()
        val model = EmailSignInModel(fake.actions, clock, backgroundScope, autoSubmit = autoSubmit, restored = restored)
        runCurrent()
        return Rig(clock, fake, model)
    }

    /** A rig in the code step: "c1" for phu@example.com, asked for in English. */
    private fun TestScope.codeRig(autoSubmit: Boolean = true): Rig {
        val rig = rig(autoSubmit)
        rig.model.start()
        rig.model.setEmail("phu@example.com")
        rig.model.send("en")
        runCurrent()
        assertEquals(Step.CODE, rig.state.step)
        return rig
    }

    private fun TestScope.tick(rig: Rig, seconds: Int) {
        repeat(seconds) {
            rig.clock.advance(1.seconds)
            advanceTimeBy(1_000)
            runCurrent()
        }
    }

    @Test fun stepsGoFromIdleToDone() { runTest {
        val rig = rig()
        assertEquals(EmailSignInState(), rig.state)
        assertNull(rig.model.saved())

        rig.model.start()
        assertEquals(Step.EMAIL, rig.state.step)
        assertFalse(rig.state.canSend)
        rig.model.setEmail(" Phu@Example.com ")
        assertTrue(rig.state.canSend)

        rig.fake.codeGate = Gate()
        rig.model.send("vi")
        runCurrent()
        assertEquals(Step.SENDING, rig.state.step)
        assertTrue(rig.state.busy)
        assertEquals(listOf("Phu@Example.com" to "vi"), rig.fake.requested)

        rig.fake.codeGate?.open()
        runCurrent()
        assertEquals(Step.CODE, rig.state.step)
        assertEquals("phu@example.com", rig.state.email)
        assertEquals("", rig.state.code)
        assertEquals(60, rig.state.resendInSeconds)
        assertNull(rig.state.error)
        assertFalse(rig.state.busy)

        rig.fake.verifyGate = Gate()
        rig.model.setCode("123456")
        runCurrent()
        assertEquals(Step.VERIFYING, rig.state.step)
        assertEquals(listOf("c1" to "123456"), rig.fake.verified)

        rig.fake.verifyGate?.open()
        runCurrent()
        assertEquals(Step.DONE, rig.state.step)
        assertTrue(rig.state.busy)
        assertNull(rig.model.saved())
    } }

    @Test fun sendIsOffUntilTheTextLooksLikeAnEmail() { runTest {
        for (good in listOf("a@b.c", " a@b.c ")) assertTrue(EmailSignInModel.looksLikeEmail(good), good)
        for (bad in listOf("", "a@b", "@b.c", "a@.c", "a@b.", "a.b@c")) assertFalse(EmailSignInModel.looksLikeEmail(bad), bad)

        val rig = rig()
        rig.model.start()
        rig.model.setEmail("a@b")
        assertFalse(rig.state.canSend)
        rig.model.send("en")
        runCurrent()
        assertEquals(Step.EMAIL, rig.state.step)
        assertEquals(emptyList(), rig.fake.requested)
    } }

    /**
     * Gboard's Vietnamese Telex rewrites "ex" as "ẽ" even in an email field: an address with a letter outside ASCII is
     * one the relay refuses, so Send stays off and no request is spent on it.
     */
    @Test fun anAddressWithALetterOutsideAsciiDoesNotLookLikeAnEmail() { runTest {
        for (bad in listOf("phu@ẽample.com", "phú@example.com", "phu@example.cóm", "phu@ｅxample.com")) {
            assertFalse(EmailSignInModel.looksLikeEmail(bad), bad)
        }
        assertTrue(EmailSignInModel.looksLikeEmail("phu@example.com"))

        val rig = rig()
        rig.model.start()
        rig.model.setEmail("phu@ẽample.com")
        assertFalse(rig.state.canSend)
        rig.model.send("vi")
        runCurrent()
        assertEquals(Step.EMAIL, rig.state.step)
        assertEquals(emptyList(), rig.fake.requested)
    } }

    @Test fun aLongEmailIsCutAt254() { runTest {
        val rig = rig()
        rig.model.start()
        rig.model.setEmail("a".repeat(300))
        assertEquals(254, rig.state.email.length)
        assertEquals(254, EmailSignInModel.MAX_EMAIL_LENGTH)
    } }

    @Test fun aPastedCodeKeepsItsDigits() { runTest {
        assertEquals("123456", EmailSignInModel.digits("123 456"))
        assertEquals("123456", EmailSignInModel.digits(" 12-34 56\n"))
        assertEquals("123456", EmailSignInModel.digits("Your ShellX sign-in code is 123456"))
        assertEquals("123456", EmailSignInModel.digits("１２３４５６"))
        assertEquals("123456", EmailSignInModel.digits("1234567"))
        assertEquals("12", EmailSignInModel.digits("12ab"))
        assertEquals("", EmailSignInModel.digits(""))

        val rig = codeRig()
        rig.model.setCode("123 456")
        runCurrent()
        assertEquals(listOf("c1" to "123456"), rig.fake.verified)
        assertEquals(Step.DONE, rig.state.step)
    } }

    @Test fun sendTappedTwiceSendsOnce() { runTest {
        val rig = rig()
        rig.model.start()
        rig.model.setEmail("phu@example.com")
        rig.fake.codeGate = Gate()
        rig.model.send("en")
        rig.model.send("en")
        runCurrent()
        rig.model.send("en")
        runCurrent()
        assertEquals(1, rig.fake.requested.size)
        rig.fake.codeGate?.open()
        runCurrent()
        assertEquals(Step.CODE, rig.state.step)
        assertEquals(1, rig.fake.requested.size)
    } }

    @Test fun verifyTappedTwiceVerifiesOnce() { runTest {
        val rig = codeRig()
        rig.fake.verifyGate = Gate()
        rig.model.setCode("123456")
        rig.model.verify()
        runCurrent()
        rig.model.verify()
        runCurrent()
        assertEquals(1, rig.fake.verified.size)
        rig.fake.verifyGate?.open()
        runCurrent()
        assertEquals(Step.DONE, rig.state.step)
        rig.model.verify()
        runCurrent()
        assertEquals(1, rig.fake.verified.size)
    } }

    @Test fun aWrongCodeClearsTheFieldAndKeepsTheChallenge() { runTest {
        val rig = codeRig()
        rig.fake.failNextVerify(SignInException.InvalidCode())
        rig.model.setCode("123456")
        runCurrent()
        assertEquals(Step.CODE, rig.state.step)
        assertEquals("", rig.state.code)
        assertSameCase(SignInException.InvalidCode(), rig.state.error)
        assertFalse(rig.state.codeDead)
        assertEquals(60, rig.state.resendInSeconds)

        rig.model.setCode("654321")
        runCurrent()
        assertEquals(listOf("c1" to "123456", "c1" to "654321"), rig.fake.verified)
        assertEquals(Step.DONE, rig.state.step)
    } }

    @Test fun anExpiredCodeOpensResendAtOnce() { runTest {
        val rig = codeRig()
        tick(rig, 10)
        assertEquals(50, rig.state.resendInSeconds)
        rig.fake.failNextVerify(SignInException.CodeExpired())
        rig.model.setCode("123456")
        runCurrent()
        assertEquals(Step.CODE, rig.state.step)
        assertEquals("", rig.state.code)
        assertTrue(rig.state.codeDead)
        assertSameCase(SignInException.CodeExpired(), rig.state.error)
        assertEquals(0, rig.state.resendInSeconds)
        assertTrue(rig.state.canResend)
        assertFalse(rig.state.canVerify)

        val dead = rig.state
        rig.model.setCode("111111")
        runCurrent()
        assertEquals(dead, rig.state)
        assertEquals(1, rig.fake.verified.size)
        // The old countdown never comes back over a dead code.
        tick(rig, 2)
        assertEquals(0, rig.state.resendInSeconds)

        rig.model.resend("vi")
        runCurrent()
        assertEquals(listOf("phu@example.com" to "en", "phu@example.com" to "vi"), rig.fake.requested)
        assertFalse(rig.state.codeDead)
        assertEquals(60, rig.state.resendInSeconds)
        assertNull(rig.state.error)

        rig.model.setCode("222222")
        runCurrent()
        assertEquals("c2" to "222222", rig.fake.verified.last())
    } }

    @Test fun offlineKeepsTheCodeForAnotherTry() { runTest {
        val rig = codeRig()
        rig.fake.failNextVerify(SignInException.Network())
        rig.model.setCode("123456")
        runCurrent()
        assertEquals(Step.CODE, rig.state.step)
        assertEquals("123456", rig.state.code)
        assertSameCase(SignInException.Network(), rig.state.error)
        assertEquals(1, rig.fake.verified.size)
        // Nothing retries by itself.
        tick(rig, 5)
        assertEquals(1, rig.fake.verified.size)

        rig.model.verify()
        runCurrent()
        assertEquals(listOf("c1" to "123456", "c1" to "123456"), rig.fake.verified)
        assertEquals(Step.DONE, rig.state.step)

        val offline = rig()
        offline.model.start()
        offline.model.setEmail("phu@example.com")
        offline.fake.failNextCode(SignInException.Network())
        offline.model.send("en")
        runCurrent()
        assertEquals(Step.EMAIL, offline.state.step)
        assertEquals("phu@example.com", offline.state.email)
        assertSameCase(SignInException.Network(), offline.state.error)
        assertTrue(offline.state.canSend)
    } }

    @Test fun aFailedSendSaysWhy() { runTest {
        val failures = listOf(
            SignInException.ProviderUnavailable(), SignInException.InvalidEmail(), SignInException.DisposableEmail(),
            SignInException.EmailSendFailed(), SignInException.RateLimited(),
        )
        for (failure in failures) {
            val rig = rig()
            rig.model.start()
            rig.model.setEmail("phu@example.com")
            rig.fake.failNextCode(failure)
            rig.model.send("en")
            runCurrent()
            assertEquals(Step.EMAIL, rig.state.step, "$failure")
            assertSameCase(failure, rig.state.error)
            assertEquals("phu@example.com", rig.state.email)
        }

        val rig = rig()
        rig.model.start()
        rig.model.setEmail("phu@example.com")
        rig.fake.failNextCode(IllegalStateException("boom"))
        rig.model.send("en")
        runCurrent()
        assertEquals(Step.EMAIL, rig.state.step)
        assertSameCase(SignInException.Server("unknown"), rig.state.error)
        // Typing again clears the failure.
        rig.model.setEmail("phu@example.org")
        assertNull(rig.state.error)
    } }

    @Test fun theCountdownFollowsTheClock() { runTest {
        val rig = codeRig()
        assertEquals(60, rig.state.resendInSeconds)
        assertFalse(rig.state.canResend)
        rig.model.resend("en")
        runCurrent()
        assertEquals(1, rig.fake.requested.size)

        tick(rig, 59)
        assertEquals(1, rig.state.resendInSeconds)
        assertFalse(rig.state.canResend)
        tick(rig, 1)
        assertEquals(0, rig.state.resendInSeconds)
        assertTrue(rig.state.canResend)

        rig.model.resend("en")
        runCurrent()
        assertEquals(2, rig.fake.requested.size)
        assertEquals(60, rig.state.resendInSeconds)
    } }

    @Test fun timeAwayCountsEvenWhenNothingTicked() { runTest {
        val rig = codeRig()
        assertEquals(60, rig.state.resendInSeconds)
        rig.clock.advance(45.seconds)
        tick(rig, 1)
        assertEquals(14, rig.state.resendInSeconds)
    } }

    @Test fun aFailedResendKeepsTheCodeStep() { runTest {
        val rig = codeRig(autoSubmit = false)
        rig.model.setCode("12")
        tick(rig, 60)
        rig.fake.failNextCode(SignInException.RateLimited())
        rig.fake.codeGate = Gate()
        rig.model.resend("en")
        runCurrent()
        assertTrue(rig.state.resending)
        assertTrue(rig.state.busy)
        assertFalse(rig.state.canResend)
        rig.model.resend("en")
        runCurrent()
        assertEquals(2, rig.fake.requested.size)

        rig.fake.codeGate?.open()
        runCurrent()
        assertEquals(Step.CODE, rig.state.step)
        assertFalse(rig.state.resending)
        assertSameCase(SignInException.RateLimited(), rig.state.error)
        assertEquals("12", rig.state.code)
        assertTrue(rig.state.canResend)
    } }

    @Test fun anAddressThatMustSwitchGoesBackToTheEmailStep() { runTest {
        val rig = codeRig()
        rig.fake.failNextVerify(SignInException.SwitchFromSignedInDevice())
        rig.model.setCode("123456")
        runCurrent()
        assertEquals(Step.EMAIL, rig.state.step)
        assertEquals("phu@example.com", rig.state.email)
        assertEquals("", rig.state.code)
        assertSameCase(SignInException.SwitchFromSignedInDevice(), rig.state.error)
        assertEquals(EmailSignInModel.Saved("phu@example.com", null, 0, 0), rig.model.saved())
    } }

    @Test fun useADifferentEmailKeepsTheAddress() { runTest {
        val rig = codeRig(autoSubmit = false)
        rig.model.setCode("123")
        rig.model.changeEmail()
        assertEquals(Step.EMAIL, rig.state.step)
        assertEquals("phu@example.com", rig.state.email)
        assertEquals("", rig.state.code)
        assertNull(rig.state.error)
        assertEquals(0, rig.state.resendInSeconds)

        // Back: code → email → the first step → nothing left to go back from.
        rig.model.send("en")
        runCurrent()
        assertEquals(Step.CODE, rig.state.step)
        assertTrue(rig.model.back())
        assertEquals(Step.EMAIL, rig.state.step)
        assertTrue(rig.model.back())
        assertEquals(Step.IDLE, rig.state.step)
        assertFalse(rig.model.back())
        // The address typed before is there when the step opens again, unless another one is handed in.
        rig.model.start()
        assertEquals("phu@example.com", rig.state.email)
        assertTrue(rig.model.back())
        rig.model.start("other@example.com")
        assertEquals("other@example.com", rig.state.email)

        // While a request is on the relay, Back is taken and nothing moves.
        rig.fake.codeGate = Gate()
        rig.model.send("en")
        runCurrent()
        assertEquals(Step.SENDING, rig.state.step)
        assertTrue(rig.model.back())
        assertEquals(Step.SENDING, rig.state.step)
        rig.fake.codeGate?.open()
        runCurrent()
        assertEquals(Step.CODE, rig.state.step)

        rig.fake.verifyGate = Gate()
        rig.model.setCode("123456")
        rig.model.verify()
        runCurrent()
        assertEquals(Step.VERIFYING, rig.state.step)
        assertTrue(rig.model.back())
        assertEquals(Step.VERIFYING, rig.state.step)
        rig.fake.verifyGate?.open()
        runCurrent()
        assertEquals(Step.DONE, rig.state.step)
        assertFalse(rig.model.back())
    } }

    @Test fun withoutAutoSubmitSixDigitsWait() { runTest {
        val rig = codeRig(autoSubmit = false)
        rig.model.setCode("123456")
        runCurrent()
        assertEquals(emptyList(), rig.fake.verified)
        assertTrue(rig.state.canVerify)
        assertEquals(Step.CODE, rig.state.step)

        rig.model.verify()
        runCurrent()
        assertEquals(listOf("c1" to "123456"), rig.fake.verified)
    } }

    @Test fun aKilledAppComesBackToTheCodeStep() { runTest {
        val rig = codeRig()
        rig.model.setCode("123")
        val saved = rig.model.saved()
        assertEquals(EmailSignInModel.Saved("phu@example.com", "c1", rig.t0 + 600_000, rig.t0 + 60_000), saved)
        assertFalse("$saved".contains("phu@example.com"), "$saved")
        assertFalse("$saved".contains("c1"), "$saved")

        // 20 s later, in a new process: the code step, with the time left and nothing typed.
        val later = rig(restored = saved, clock = ManualClock(rig.t0 + 20_000))
        assertEquals(Step.CODE, later.state.step)
        assertEquals("phu@example.com", later.state.email)
        assertEquals("", later.state.code)
        assertEquals(40, later.state.resendInSeconds)
        assertNull(later.state.error)
        assertEquals(emptyList(), later.fake.requested)
        tick(later, 40)
        assertTrue(later.state.canResend)
        // Its code still goes to the challenge that was saved.
        later.model.setCode("123456")
        runCurrent()
        assertEquals(listOf("c1" to "123456"), later.fake.verified)

        // After the code's ten minutes: the email step, saying why.
        val tooLate = rig(restored = saved, clock = ManualClock(rig.t0 + 601_000))
        assertEquals(Step.EMAIL, tooLate.state.step)
        assertEquals("phu@example.com", tooLate.state.email)
        assertSameCase(SignInException.CodeExpired(), tooLate.state.error)
        assertEquals(emptyList(), tooLate.fake.requested)
        // The window may be made twice on the way back (the host replaces its restored page): what is saved from that
        // step is what it was restored from, so the second one says "expired" too. A changed address starts afresh.
        assertEquals(saved, tooLate.model.saved())
        val again = rig(restored = tooLate.model.saved(), clock = ManualClock(rig.t0 + 602_000))
        assertEquals(Step.EMAIL, again.state.step)
        assertSameCase(SignInException.CodeExpired(), again.state.error)
        again.model.setEmail("phu@example.org")
        assertNull(again.state.error)
        assertEquals(EmailSignInModel.Saved("phu@example.org", null, 0, 0), again.model.saved())
        tooLate.model.send("en")
        runCurrent()
        assertEquals("c1", tooLate.model.saved()?.challengeId)
        assertEquals(rig.t0 + 601_000 + 600_000, tooLate.model.saved()?.expiresAtMs)

        val emailStep = rig(restored = EmailSignInModel.Saved("a@b.c", null, 0, 0))
        assertEquals(Step.EMAIL, emailStep.state.step)
        assertEquals("a@b.c", emailStep.state.email)
        assertNull(emailStep.state.error)
    } }

    @Test fun whatIsSavedFollowsTheStep() { runTest {
        val rig = rig()
        rig.model.start()
        rig.model.setEmail("phu@example.com")
        assertEquals(EmailSignInModel.Saved("phu@example.com", null, 0, 0), rig.model.saved())
        rig.fake.codeGate = Gate()
        rig.model.send("en")
        runCurrent()
        assertEquals(EmailSignInModel.Saved("phu@example.com", null, 0, 0), rig.model.saved())
        rig.fake.codeGate?.open()
        runCurrent()
        assertEquals("c1", rig.model.saved()?.challengeId)

        rig.fake.failNextVerify(SignInException.CodeExpired())
        rig.model.setCode("123456")
        runCurrent()
        assertEquals(EmailSignInModel.Saved("phu@example.com", null, 0, 0), rig.model.saved())
    } }

    @Test fun theStateNeverPrintsTheEmailOrTheCode() { runTest {
        val state = EmailSignInState(step = Step.CODE, email = "phu@example.com", code = "123456", resendInSeconds = 42)
        val printed = state.toString()
        assertFalse(printed.contains("phu@example.com"), printed)
        assertFalse(printed.contains("123456"), printed)
        assertTrue(printed.contains("CODE"), printed)
    } }
}
