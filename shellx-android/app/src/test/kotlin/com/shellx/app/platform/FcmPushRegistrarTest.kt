@file:OptIn(ExperimentalCoroutinesApi::class)

package com.shellx.app.platform

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.FakeFcmMessaging
import com.shellx.core.account.AppPhase
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

/** 3C's PushRegistrar over FCM (contracts §8, §25): auto-init is on only for a signed-in account. */
@RunWith(AndroidJUnit4::class)
class FcmPushRegistrarTest {
    @Test
    fun aTokenForTheSignedInAccountTurnsAutoInitOn() {
        runTest {
            val fcm = FakeFcmMessaging()
            assertEquals("fcm-1", FcmPushRegistrar { fcm }.currentToken())
            assertEquals(listOf(true), fcm.autoInit)

            fcm.token = null
            assertNull("FCM refused", FcmPushRegistrar { fcm }.currentToken())
        }
    }

    /**
     * Review C concern 7: after a sign-out FCM must stop refreshing the token with Google (plan 3H's Data safety
     * answers). Each sign-out turns auto-init off; only a token asked for a signed-in account turns it on again.
     */
    @Test
    fun eachSignOutTurnsAutoInitOff() {
        runTest {
            val fcm = FakeFcmMessaging()
            val registrar = FcmPushRegistrar { fcm }
            val phase = MutableStateFlow<AppPhase>(AppPhase.Launching)
            backgroundScope.launch { registrar.followSignOuts(phase) }
            runCurrent()
            phase.value = AppPhase.SignedIn("a@b.c")
            runCurrent()
            assertEquals(emptyList<Boolean>(), fcm.autoInit)

            phase.value = AppPhase.SignedOut(false)
            runCurrent()
            assertEquals(listOf(false), fcm.autoInit)

            phase.value = AppPhase.SignedIn("a@b.c")
            runCurrent()
            assertEquals("signing in alone turns nothing on", listOf(false), fcm.autoInit)
            registrar.currentToken()
            phase.value = AppPhase.SignedOut(true)
            runCurrent()
            assertEquals(listOf(false, true, false), fcm.autoInit)
        }
    }

    @Test
    fun withoutFirebaseNothingBreaks() {
        runTest {
            val registrar = FcmPushRegistrar { throw IllegalStateException("Default FirebaseApp is not initialized") }
            assertNull(registrar.currentToken())
            registrar.signedOut()
        }
    }
}
