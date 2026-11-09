package com.shellx.app.demo

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.testComposition
import com.shellx.app.testing.waitFor
import com.shellx.app.ui.nav.Routes
import com.shellx.core.account.AppPhase
import com.shellx.core.account.SecretItem
import com.shellx.core.account.SecretStore
import com.shellx.core.demo.DemoSecretStore
import com.shellx.core.link.MachineLinkState
import com.shellx.core.platform.KeyValueStore
import com.shellx.core.platform.MemoryKeyValueStore
import java.io.File
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith

/** "Try without an account" over the real app (1C's DemoSession): in, the sample Mac, out, and nothing real touched. */
@RunWith(AndroidJUnit4::class)
class DemoSessionTest {
    @get:Rule val folder = TemporaryFolder()

    private class CountingSecrets(private val inner: SecretStore = DemoSecretStore()) : SecretStore by inner {
        var writes = 0

        override fun write(data: ByteArray, item: SecretItem) {
            writes++
            inner.write(data, item)
        }

        override fun delete(item: SecretItem) {
            writes++
            inner.delete(item)
        }
    }

    private class CountingSettings(private val inner: KeyValueStore = MemoryKeyValueStore()) : KeyValueStore by inner {
        var writes = 0

        override fun putString(key: String, value: String?) {
            writes++
            inner.putString(key, value)
        }

        override fun putBoolean(key: String, value: Boolean) {
            writes++
            inner.putBoolean(key, value)
        }

        override fun remove(key: String) {
            writes++
            inner.remove(key)
        }
    }

    @Test
    fun startSignsInToTheDemoWithItsSampleMac() {
        runTest {
            val c = testComposition(folder.root, signedIn = false).composition

            c.demo.start()

            val graph = c.active.value
            assertTrue(graph.isDemo)
            assertTrue(waitFor { graph.coordinator.phase.value == AppPhase.SignedIn("demo@shellx.pro") })
            assertTrue(
                waitFor {
                    val machines = graph.coordinator.hub.value?.machines.orEmpty()
                    machines.map { it.name } == listOf("Mac giả") && machines.all { it.state == MachineLinkState.Online }
                },
            )
            assertNull("no push in the demo", graph.push)
            assertNull("no update prompt in the demo", graph.updatePrompt)
            assertTrue(waitFor { c.root.value == Routes.DEMO })
        }
    }

    @Test
    fun startingTwiceKeepsOneDemo() {
        runTest {
            val t = testComposition(folder.root, signedIn = false)
            val c = t.composition

            c.demo.start()
            val first = c.demo.graph.value
            c.demo.start()

            assertSame(first, c.demo.graph.value)
            assertEquals(1, t.demoEnvironments.size)
        }
    }

    @Test
    fun exitHandsTheAppBackToTheRealAccount() {
        runTest {
            val t = testComposition(folder.root, signedIn = false)
            val c = t.composition
            c.real.coordinator.launch()
            c.demo.start()
            assertTrue(waitFor { c.root.value == Routes.DEMO })
            val demoMac = t.demoEnvironments.single().first
            assertTrue(waitFor { demoMac.liveSessionCount > 0 })

            c.demo.exit()

            assertSame(c.real, c.active.value)
            assertNull(c.demo.graph.value)
            assertTrue(waitFor { c.root.value == Routes.SIGN_IN })
            assertTrue("the demo's links close", waitFor { demoMac.liveSessionCount == 0 })
        }
    }

    @Test
    fun theDemoNeverTouchesTheRealStores() {
        runTest {
            val secrets = CountingSecrets()
            val settings = CountingSettings()
            val c = testComposition(folder.root, signedIn = false, secrets = secrets, settings = settings).composition

            c.demo.start()
            assertTrue(waitFor { c.root.value == Routes.DEMO })
            advanceTimeBy(5.seconds)
            c.demo.exit()

            assertEquals(0, secrets.writes)
            assertEquals(0, settings.writes)
            assertFalse(File(folder.root, "ShellX").exists())
        }
    }
}
