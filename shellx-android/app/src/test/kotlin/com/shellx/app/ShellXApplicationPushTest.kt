package com.shellx.app

import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.platform.ShellXMessagingService
import com.shellx.app.testing.SignedInShellXApplication
import com.shellx.core.account.AppPhase
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.launch
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** ShellXApplication's own push wiring, over a signed-in account of fakes. */
@RunWith(AndroidJUnit4::class)
@Config(application = SignedInShellXApplication::class)
class ShellXApplicationPushTest {
    private val app: SignedInShellXApplication = ApplicationProvider.getApplicationContext()

    /** Runs the main looper until [condition] holds, for at most 10 s. */
    private fun idleUntil(condition: () -> Boolean): Boolean {
        val deadline = System.nanoTime() + 10_000_000_000
        while (!condition() && System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(10)
        }
        return condition()
    }

    /**
     * Review C m-7 and m-9: FCM's onNewToken goes through ShellXApplication's hook to the composition's registration, and
     * the relay has the token before the service returns: FCM may have started the process for the token alone, and
     * the process can die once the service is done.
     */
    @Test
    fun aNewTokenReachesTheRelayBeforeTheServiceReturns() {
        assertTrue(idleUntil { app.composition.value != null })
        val service = Robolectric.buildService(ShellXMessagingService::class.java).create().get()
        val atReturn = AtomicReference<List<String>?>(null)
        // FCM calls onNewToken on its own thread.
        Thread {
            service.onNewToken("fcm-9")
            atReturn.set(app.relay.calls)
        }.start()

        assertTrue("onNewToken returned", idleUntil { atReturn.get() != null })
        assertTrue("the relay had the token first", "push:set" in atReturn.get()!!)
    }

    /** Review C concern 7: when the real account signs out, the application turns FCM's auto-init off. */
    @Test
    fun signingOutTurnsFcmAutoInitOff() {
        assertTrue(idleUntil { app.composition.value != null })
        val composition = app.composition.value!!
        composition.lifecycle.onStart()
        assertTrue(
            "signed in, with a token asked for the account",
            idleUntil { composition.real.coordinator.phase.value is AppPhase.SignedIn && true in app.messaging.autoInit },
        )

        composition.appScope.launch { composition.real.coordinator.signOut() }
        assertTrue(idleUntil { composition.real.coordinator.phase.value is AppPhase.SignedOut })
        assertTrue("auto-init is off", idleUntil { app.messaging.autoInit.lastOrNull() == false })
    }
}
