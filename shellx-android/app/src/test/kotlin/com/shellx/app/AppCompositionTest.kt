@file:OptIn(ExperimentalCoroutinesApi::class)

package com.shellx.app

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.testComposition
import com.shellx.app.testing.waitFor
import com.shellx.app.ui.nav.Routes
import com.shellx.core.account.SecretItem
import com.shellx.core.account.SecretStore
import com.shellx.core.account.SecretStoreException
import com.shellx.core.demo.DemoSecretStore
import com.shellx.core.demo.FakeMac
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.link.MachineHub
import com.shellx.core.pairing.PairingModel
import com.shellx.core.platform.Clock
import com.shellx.core.platform.KeyValueStore
import com.shellx.core.update.AvailableUpdate
import com.shellx.core.update.UpdateChecker
import com.shellx.core.voice.VoiceCapabilities
import com.shellx.core.voice.VoiceCapabilityCache
import com.shellx.core.voice.VoiceService
import java.io.File
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith

/** The composition root: the real account, its per-hub scope, the pairing link and the release-only pieces. */
@RunWith(AndroidJUnit4::class)
class AppCompositionTest {
    @get:Rule val folder = TemporaryFolder()

    /** A secret store the Keystore daemon keeps busy while [busy]. */
    private class BusySecrets(private val inner: SecretStore = DemoSecretStore()) : SecretStore by inner {
        @Volatile var busy = false

        override fun read(item: SecretItem): ByteArray? {
            if (busy) throw SecretStoreException.Unavailable()
            return inner.read(item)
        }
    }

    @Test
    fun signingInMakesTheScopeOfTheNewHub() {
        runTest {
            val t = testComposition(folder.root, signedIn = false)
            val c = t.composition
            c.real.coordinator.launch()
            assertTrue(waitFor { c.root.value == Routes.SIGN_IN })

            c.real.coordinator.signInWithGoogle()

            assertTrue(waitFor { c.root.value == Routes.FIRST_MAC })
            assertSame(c.real.coordinator.hub.value, c.real.scopes.current.value!!.hub)
            assertEquals(listOf("nonce", "google:google-id-token"), t.relay.calls.take(2))
        }
    }

    @Test
    fun pairingTheFirstMacMovesTheRootHome() {
        runTest {
            val mac = FakeMac("MacBook Pro", backgroundScope)
            val t = testComposition(folder.root, signedIn = false, pairable = listOf(mac))
            val c = t.composition
            c.real.coordinator.launch()
            c.real.coordinator.signInWithGoogle()
            assertTrue(waitFor { c.root.value == Routes.FIRST_MAC })

            val scope = c.real.scopes.current.value!!
            scope.pairing.begin(mac.pairingCode())
            scope.pairing.confirm()

            assertTrue(waitFor { c.root.value == Routes.HOME })
        }
    }

    @Test
    fun pairTappedTwiceSendsOnePairingRequest() {
        runTest {
            val mac = FakeMac("MacBook Pro", backgroundScope)
            val t = testComposition(folder.root, signedIn = false, pairable = listOf(mac))
            val c = t.composition
            c.real.coordinator.launch()
            c.real.coordinator.signInWithGoogle()
            assertTrue(waitFor { c.real.scopes.current.value != null })
            val pairing = c.real.scopes.current.value!!.pairing

            pairing.begin(mac.pairingCode())
            backgroundScope.launch { pairing.confirm() }
            backgroundScope.launch { pairing.confirm() }

            assertTrue(waitFor { pairing.step.value is PairingModel.Step.Paired })
            assertEquals(1, t.relay.calls.count { it == "pair" })
        }
    }

    @Test
    fun signingOutDropsTheScope() {
        runTest {
            val mac = FakeMac("MacBook Pro", backgroundScope)
            val t = testComposition(folder.root, macs = listOf(mac))
            val c = t.composition
            c.real.coordinator.launch()
            assertTrue(waitFor { c.root.value == Routes.HOME })

            c.real.coordinator.signOut()

            assertTrue(waitFor { c.root.value == Routes.SIGN_IN })
            assertTrue(waitFor { c.real.scopes.current.value == null })
        }
    }

    @Test
    fun aBusyKeystoreKeepsTheLaunchScreenUntilItOpens() {
        runTest {
            val mac = FakeMac("MacBook Pro", backgroundScope)
            val secrets = BusySecrets()
            val t = testComposition(folder.root, macs = listOf(mac), secrets = secrets)
            val c = t.composition
            secrets.busy = true

            c.real.coordinator.launch()
            advanceUntilIdle()
            assertEquals("a busy store is not a signed-out phone", Routes.LAUNCH, c.root.value)

            secrets.busy = false
            c.real.coordinator.protectedDataBecameAvailable()

            assertTrue(waitFor { c.root.value == Routes.HOME })
        }
    }

    @Test
    fun aLinkWaitsForARealSignedInHomeAndOnlyFillsTheConfirmation() {
        runTest {
            val b = FakeMac("Mac mini", backgroundScope)
            val t = testComposition(folder.root, signedIn = false, pairable = listOf(b))
            val c = t.composition
            c.real.coordinator.launch()
            assertTrue(waitFor { c.root.value == Routes.SIGN_IN })

            assertTrue(c.inbox.receive(b.pairingCode()))
            assertFalse("signed out: the link waits", c.takeLink())
            assertTrue(c.inbox.hasLink.value)

            c.real.coordinator.signInWithGoogle()
            assertTrue(waitFor { c.root.value == Routes.FIRST_MAC })

            assertTrue(c.takeLink())
            assertEquals(PairingModel.Step.Confirm("Mac mini"), c.real.scopes.current.value!!.pairing.step.value)
            assertFalse("nothing reaches the relay before Pair", "pair" in t.relay.calls)
            assertFalse(c.inbox.hasLink.value)
        }
    }

    @Test
    fun aLinkWaitsWhileASheetIsOpenOrTheDemoRuns() {
        runTest {
            val a = FakeMac("MacBook Pro", backgroundScope)
            val b = FakeMac("Mac mini", backgroundScope)
            val t = testComposition(folder.root, macs = listOf(a), pairable = listOf(b))
            val c = t.composition
            c.real.coordinator.launch()
            assertTrue(waitFor { c.root.value == Routes.HOME })
            val scope = c.real.scopes.current.value!!

            scope.sheets.opened()
            c.inbox.receive(b.pairingCode())
            assertFalse("a pending sheet is open: the link waits", c.takeLink())
            scope.sheets.closed()
            assertTrue(c.takeLink())

            c.demo.start()
            c.inbox.receive(b.pairingCode())
            assertFalse("the demo runs: the link waits for the real account", c.takeLink())
            assertTrue(c.inbox.hasLink.value)

            c.demo.exit()
            assertTrue(c.takeLink())
        }
    }

    @Test
    fun theUpdatePromptExistsOnlyInReleaseWithAChecker() {
        runTest {
            val checker = object : UpdateChecker {
                override suspend fun check(): AvailableUpdate? = null
                override suspend fun startUpdate(update: AvailableUpdate) {}
            }
            val debug = testComposition(File(folder.root, "debug"), signedIn = false, debugBuild = true, updateChecker = checker)
            assertNull("never in debug builds", debug.composition.updatePrompt)
            val noChecker = testComposition(File(folder.root, "release"), signedIn = false, debugBuild = false)
            assertNull(noChecker.composition.updatePrompt)
            val release = testComposition(
                File(folder.root, "release-checker"), signedIn = false, debugBuild = false, updateChecker = checker,
            ).composition
            assertNotNull(release.updatePrompt)
            assertNotNull(release.push)
            assertSame(release.vault, release.real.vault)
            assertSame(release.updatePrompt, release.real.updatePrompt)
        }
    }

    @Test
    fun makeVoiceGivesEachHubItsVoice() {
        runTest {
            val made = mutableListOf<VoiceService>()
            val factory = { hub: MachineHub, latency: LatencyLog, settings: KeyValueStore, clock: Clock ->
                VoiceService(
                    NoSpeechEngine, NoVoicePermissions,
                    VoiceCapabilityCache(timeSource = clock.monotonic) { VoiceCapabilities.NONE },
                    latency, settings, hub.scope, clock.monotonic, listOf("en"), { emptyList() },
                ).also { made += it }
            }
            val t = testComposition(folder.root, signedIn = false, makeVoice = factory)
            val c = t.composition
            c.real.coordinator.launch()
            c.real.coordinator.signInWithGoogle()

            assertTrue(waitFor { c.real.scopes.current.value != null })
            assertEquals(1, made.size)
            assertSame(made.single(), c.real.scopes.current.value!!.voice)
        }
    }
}
