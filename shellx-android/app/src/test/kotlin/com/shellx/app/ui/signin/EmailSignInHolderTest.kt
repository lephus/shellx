package com.shellx.app.ui.signin

import androidx.compose.runtime.saveable.SaverScope
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.ManualClock
import com.shellx.core.account.EmailCodeActions
import com.shellx.core.account.EmailSignInModel
import com.shellx.core.account.EmailSignInState
import com.shellx.link.account.EmailChallenge
import kotlin.time.Duration.Companion.seconds
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.shadows.ShadowLooper

/** What the sign-in screen keeps of its email steps: across a rotation (the holder) and a killed process (the saver). */
@RunWith(AndroidJUnit4::class)
class EmailSignInHolderTest {
    private val requests = mutableListOf<Pair<String, String>>()
    private val actions = EmailCodeActions(
        requestCode = { email, locale ->
            requests += email to locale
            EmailChallenge("c1", 600, 60, "phu@example.com")
        },
        verify = { _, _ -> },
    )

    private fun roundTrip(value: EmailSignInModel.Saved?): EmailSignInModel.Saved? {
        val saved = with(EmailSignInSaver) { SaverScope { true }.save(value) } ?: return null
        return EmailSignInSaver.restore(saved)
    }

    @Test
    fun theSaverKeepsTheAddressTheChallengeAndTheDeadlines() {
        val codeStep = EmailSignInModel.Saved("phu@example.com", "c1", 1_700_000_600_000, 1_700_000_060_000)
        assertEquals(codeStep, roundTrip(codeStep))
        val emailStep = EmailSignInModel.Saved("a@b.c", null, 0, 0)
        assertEquals(emailStep, roundTrip(emailStep))
        assertNull(with(EmailSignInSaver) { SaverScope { true }.save(null) })
    }

    /** The sign-in screen's first screen is the email step: a new holder starts there, a restored one where it was. */
    @Test
    fun theStepsStartOnTheEmailStep() {
        val clock = ManualClock()
        val fresh = EmailSignInHolder(actions, clock, restored = null).model.state.value
        assertEquals(EmailSignInState.Step.EMAIL, fresh.step)
        assertEquals("", fresh.email)

        val typed = EmailSignInHolder(actions, clock, EmailSignInModel.Saved("a@b.c", null, 0, 0)).model.state.value
        assertEquals(EmailSignInState.Step.EMAIL, typed.step)
        assertEquals("a@b.c", typed.email)

        val code = EmailSignInModel.Saved("a@b.c", "c1", clock.nowMs() + 600_000, clock.nowMs() + 60_000)
        assertEquals(EmailSignInState.Step.CODE, EmailSignInHolder(actions, clock, code).model.state.value.step)
        assertEquals(emptyList<Pair<String, String>>(), requests)
    }

    @Test
    fun aKilledAppComesBackToTheCodeStepWithTheTimeLeft() {
        val clock = ManualClock()
        val first = EmailSignInHolder(actions, clock, restored = null)
        first.model.start()
        first.model.setEmail("phu@example.com")
        first.model.send("en")
        ShadowLooper.idleMainLooper()
        assertEquals(EmailSignInState.Step.CODE, first.model.state.value.step)
        first.model.setCode("12")
        val saved = roundTrip(first.model.saved())
        assertEquals(EmailSignInModel.Saved("phu@example.com", "c1", clock.nowMs() + 600_000, clock.nowMs() + 60_000), saved)

        clock.advance(20.seconds)
        val state = EmailSignInHolder(actions, clock, saved).model.state.value

        assertEquals(EmailSignInState.Step.CODE, state.step)
        assertEquals("phu@example.com", state.email)
        assertEquals("the typed code is never saved", "", state.code)
        assertEquals(40, state.resendInSeconds)
        assertEquals(listOf("phu@example.com" to "en"), requests)
    }
}
