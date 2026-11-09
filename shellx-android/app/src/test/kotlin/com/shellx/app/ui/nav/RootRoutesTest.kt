package com.shellx.app.ui.nav

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.core.account.AppPhase
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/** The one root destination for each account state (plan 3D Task 7's table). */
@RunWith(AndroidJUnit4::class)
class RootRoutesTest {
    private val signedIn = AppPhase.SignedIn("phu@example.com")

    private fun root(demo: Boolean, phase: AppPhase, ready: Boolean = false, hasMachines: Boolean = false): String =
        RootRoutes.of(RootState(demo, phase, hubLoaded = ready, hasMachines = hasMachines, scopeReady = ready))

    @Test
    fun theRootFollowsTheAccount() {
        assertEquals(Routes.DEMO, root(demo = true, phase = signedIn, ready = true, hasMachines = true))
        assertEquals(Routes.LAUNCH, root(demo = true, phase = AppPhase.Launching))
        assertEquals(Routes.LAUNCH, root(demo = false, phase = AppPhase.Launching))
        assertEquals(Routes.SIGN_IN, root(demo = false, phase = AppPhase.SignedOut(expired = true)))
        assertEquals("a sign-out in progress is not signed out", Routes.LAUNCH, root(demo = false, phase = signedIn))
        assertEquals(Routes.HOME, root(demo = false, phase = signedIn, ready = true, hasMachines = true))
        assertEquals(Routes.FIRST_MAC, root(demo = false, phase = signedIn, ready = true, hasMachines = false))
        // A loaded hub whose scope is not made yet still waits.
        assertEquals(
            Routes.LAUNCH,
            RootRoutes.of(RootState(false, signedIn, hubLoaded = true, hasMachines = true, scopeReady = false)),
        )
    }
}
