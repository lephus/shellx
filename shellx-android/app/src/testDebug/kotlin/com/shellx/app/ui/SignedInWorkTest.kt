package com.shellx.app.ui

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.foundation.clickable
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.movableContentOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.PlatformServices
import com.shellx.app.testing.VoiceRig
import com.shellx.app.testing.WorkRig
import com.shellx.app.testing.mainComposition
import com.shellx.app.ui.composer.LocalAttachmentReader
import com.shellx.app.ui.nav.Routes
import com.shellx.app.ui.nav.WorkRoutes
import com.shellx.app.ui.theme.AppAppearance
import com.shellx.app.ui.theme.ShellXAppTheme
import com.shellx.app.voice.LocalVoice
import com.shellx.app.voice.VoiceEnvironment
import com.shellx.core.composer.AttachmentReader
import com.shellx.core.demo.FakeMac
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** What 3E's screens get from a signed-in account (iPhone `SignedInView`'s environment and tasks). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w400dp-h1600dp")
class SignedInWorkTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    private val app: Application = ApplicationProvider.getApplicationContext()
    private val platform = PlatformServices(app, debugBuild = true)
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val rigs = mutableListOf<WorkRig>()

    @After
    fun tearDown() {
        rigs.forEach { it.close() }
        appScope.cancel()
    }

    private fun rig(voice: VoiceRig? = null) = WorkRig.make(voice = voice?.service).also { rigs += it }

    /** A real-time wait that runs the main looper meanwhile (the account's work is posted to it). */
    private fun waitUntil(condition: () -> Boolean) {
        rule.waitUntil(10_000) {
            rule.waitForIdle()
            condition()
        }
    }

    private fun shown(text: String) = rule.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    @Test
    fun aTapOpensTheWaitingRequestsOnceTheMacsAreLoaded() {
        val rig = rig()
        var opened = 0
        var tick by mutableIntStateOf(0)
        platform.pushTaps.receive()
        rule.setContent {
            SignedInWork(rig.scope, platform, null, rig.settings, openPending = { opened++ }) { Text("tick $tick") }
        }
        waitUntil { opened == 1 }
        assertFalse("the tap is taken", platform.pushTaps.hasTap.value)

        tick++
        waitUntil { shown("tick 1") }
        assertEquals("a recomposition opens nothing more", 1, opened)
    }

    @Test
    fun registrationRunsOnceTheFirstMacExists() {
        val calls = mutableListOf<String>()
        var empty by mutableStateOf(true)
        var tick by mutableIntStateOf(0)
        rule.setContent {
            Text("tick $tick")
            PushRegistrationEffect(empty, { calls += "signedIn" }, { calls += "askPermission" })
        }
        rule.waitForIdle()
        assertEquals(emptyList<String>(), calls)

        empty = false
        rule.waitForIdle()
        assertEquals(listOf("signedIn", "askPermission"), calls)

        tick++
        waitUntil { shown("tick 1") }
        assertEquals(listOf("signedIn", "askPermission"), calls)
    }

    @Test
    fun theScreensGetTheMicAndTheReader() {
        val rig = rig(voice = VoiceRig.make())
        var voice: VoiceEnvironment? = null
        var reader: AttachmentReader? = null
        rule.setContent {
            SignedInWork(rig.scope, platform, null, rig.settings, openPending = {}) {
                voice = LocalVoice.current
                reader = LocalAttachmentReader.current
            }
        }
        rule.waitForIdle()
        assertSame(rig.scope.voice, voice?.service)
        assertSame(platform.voice.meter, voice?.meter)
        assertSame(rig.hub.scope, voice?.scope)
        assertSame(platform.attachmentReader, reader)
    }

    /** 3D note 7: the wrapper appears when the scope does, and the NavHost (movable content) keeps its pages and their
     *  state through it. */
    @Test
    fun theStackAndItsStateSurviveTheScopeArriving() {
        val t = mainComposition(folder.root, listOf(FakeMac("MacBook Pro", appScope)), appScope)
        lateinit var nav: NavHostController
        rule.setContent {
            nav = rememberNavController()
            val host = remember {
                movableContentOf {
                    NavHost(nav, startDestination = "a") {
                        composable("a") { Text("page a") }
                        composable("b") {
                            var taps by remember { mutableIntStateOf(0) }
                            Text("page b $taps, mic ${LocalVoice.current != null}", Modifier.testTag("b").clickable { taps++ })
                        }
                    }
                }
            }
            SignedInFrame(t.composition, nav, "a", platform) { host() }
        }
        rule.runOnIdle { nav.navigate("b") }
        rule.onNodeWithTag("b").performClick()
        waitUntil { shown("page b 1, mic false") }
        assertNull(t.composition.active.value.scopes.current.value)

        rule.runOnUiThread { t.composition.lifecycle.onStart() }
        waitUntil { t.composition.real.scopes.current.value != null }

        waitUntil { shown("page b 1, mic true") }
        assertEquals("a", nav.previousBackStackEntry?.destination?.route)
    }

    /** 3D note 6: a tap over an open page puts the waiting requests right above the root (the stack's real bottom). */
    @Test
    fun aTapOverAnOpenPageOpensTheRequestsAboveTheRoot() {
        val mac = FakeMac("MacBook Pro", appScope).apply {
            setWorkspaces(listOf(LinkWorkspace("ws-1", "shellx-ios", 0, terminals = listOf(LinkTerminal("t1", "zsh", 0, selected = true)))))
        }
        val t = mainComposition(folder.root, listOf(mac), appScope)
        lateinit var nav: NavHostController
        rule.setContent {
            nav = rememberNavController()
            ShellXAppTheme(AppAppearance.SYSTEM) { ShellXApp(t.composition, nav, platform) }
        }
        rule.runOnUiThread { t.composition.lifecycle.onStart() }
        waitUntil { nav.currentBackStackEntry?.destination?.route == Routes.HOME && shown("shellx-ios") }
        rule.runOnUiThread { nav.navigate(Routes.SETTINGS) }
        waitUntil { nav.currentBackStackEntry?.destination?.route == Routes.SETTINGS }

        rule.runOnUiThread { platform.pushTaps.receive() }

        waitUntil { nav.currentBackStackEntry?.destination?.route == WorkRoutes.PENDING }
        assertEquals(Routes.HOME, nav.previousBackStackEntry?.destination?.route)
        assertFalse(platform.pushTaps.hasTap.value)
    }
}
