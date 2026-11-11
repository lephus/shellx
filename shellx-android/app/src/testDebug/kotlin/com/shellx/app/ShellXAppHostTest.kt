package com.shellx.app

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.navigation.NavHostController
import androidx.navigation.compose.rememberNavController
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.ManualClock
import com.shellx.app.testing.ScriptedRelay
import com.shellx.app.testing.TestNetworkMonitor
import com.shellx.app.testing.mainComposition
import com.shellx.app.testing.testEnvironment
import com.shellx.app.ui.ShellXApp
import com.shellx.app.ui.nav.Routes
import com.shellx.app.ui.theme.AppAppearance
import com.shellx.app.ui.theme.ShellXAppTheme
import com.shellx.core.account.AccountAuthMethod
import com.shellx.core.account.AccountVault
import com.shellx.core.account.IdentityProviding
import com.shellx.core.account.StoredSession
import com.shellx.core.demo.DemoSecretStore
import com.shellx.core.demo.FakeMac
import com.shellx.core.demo.FakeMacFleet
import com.shellx.core.platform.MemoryKeyValueStore
import com.shellx.link.core.LinkTerminal
import com.shellx.link.core.LinkWorkspace
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Review D m-7: the paths the screen tests cannot see, through the real [ShellXApp] host (the NavHost, its
 * entry-owned ViewModels and RootSync): a link waiting through sign-in, a deletion across a recreated window (with
 * Google, and with an emailed code), and a sign-out from Settings.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w400dp-h1600dp")
class ShellXAppHostTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val folder = TemporaryFolder()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    @After
    fun tearDown() {
        appScope.cancel()
    }

    private fun shown(text: String) = rule.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    private fun tagShown(tag: String) = rule.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty()

    /** A real-time wait that runs the main looper meanwhile (Robolectric: the account's work is posted to it). */
    private fun waitUntil(condition: () -> Boolean) {
        rule.waitUntil(10_000) {
            rule.waitForIdle()
            condition()
        }
    }

    private fun tap(text: String) {
        waitUntil { rule.onAllNodes(hasText(text) and hasClickAction()).fetchSemanticsNodes().isNotEmpty() }
        rule.onNode(hasText(text) and hasClickAction()).performClick()
    }

    private fun mac() = FakeMac("MacBook Pro", appScope).apply {
        setWorkspaces(
            listOf(LinkWorkspace("ws-shellx-ios", "shellx-ios", 0, terminals = listOf(LinkTerminal("t1", "zsh", 0, selected = true)))),
        )
    }

    /** Google's sheet held open until [gate] completes. */
    private class GatedIdentity : IdentityProviding {
        val gate = CompletableDeferred<Unit>()
        val asked = AtomicInteger()

        override suspend fun googleIdToken(nonce: String): String {
            asked.incrementAndGet()
            gate.await()
            return "google-id-token"
        }
    }

    /** Review Focus 2 in the host: a link that came while signed out waits, then opens only the confirmation. */
    @Test
    fun aLinkThatCameWhileSignedOutOpensOnlyTheConfirmationAfterSignIn() {
        val mac = mac()
        val t = mainComposition(folder.root, macs = emptyList(), appScope = appScope, signedIn = false, pairable = listOf(mac))
        rule.setContent { ShellXAppTheme(AppAppearance.SYSTEM) { ShellXApp(t.composition) } }
        rule.runOnUiThread { t.composition.lifecycle.onStart() }
        waitUntil { shown("Continue with Google") }
        rule.runOnUiThread { t.composition.inbox.receive(mac.pairingCode()) }
        rule.waitForIdle()
        assertFalse("waits on the sign-in screen", shown("Pair with MacBook Pro?"))

        tap("Continue with Google")
        waitUntil { shown("Pair with MacBook Pro?") }
        assertEquals("nothing before Pair", 0, t.relay.calls.count { it == "pair" })
        tap("Pair")
        waitUntil { shown("Paired with MacBook Pro.") }
        assertEquals(1, t.relay.calls.count { it == "pair" })
    }

    /** Delete Account: Working survives a recreated window, one request goes out, then a clean sign-in (not
     *  "expired") with nothing under it. */
    @Test
    fun aDeletionSurvivesARecreatedWindowAndEndsOnACleanSignIn() {
        val mac = mac()
        val secrets = DemoSecretStore()
        runBlocking {
            val vault = AccountVault(secrets, Dispatchers.IO)
            vault.setSession(StoredSession("u1", "d1", "tok-1", "phu@example.com"))
            vault.setMachines(listOf(mac.machine), "u1")
        }
        val identity = GatedIdentity()
        val relay = ScriptedRelay(listOf(mac.machine))
        val environment = testEnvironment(
            folder.root, Dispatchers.IO, secrets, MemoryKeyValueStore(), TestNetworkMonitor(), ManualClock(), identity,
        )
        val composition = AppComposition(
            environment = environment,
            appScope = appScope,
            relays = { vault -> RelayBundle(relay, FakeMacFleet(listOf(mac)) { vault.phoneKey() }) },
        )
        lateinit var nav: NavHostController
        // One content lambda for both windows, as MainActivity's setContent is on a real recreation.
        val window: @Composable () -> Unit = {
            ShellXAppTheme(AppAppearance.SYSTEM) { ShellXApp(composition, rememberNavController().also { nav = it }) }
        }
        rule.setContent(window)
        rule.runOnUiThread { composition.lifecycle.onStart() }
        waitUntil { shown("shellx-ios") }
        rule.runOnUiThread { nav.navigate(Routes.SETTINGS) }
        waitUntil { tagShown("settings.delete") }
        rule.onNodeWithTag("settings.delete").performClick()
        waitUntil { tagShown("delete.confirm") }
        rule.onNodeWithTag("delete.confirm").performClick()
        waitUntil { tagShown("delete.working") && identity.asked.get() == 1 }

        rule.activityRule.scenario.recreate()
        rule.setContent(window)

        waitUntil { tagShown("delete.working") }
        rule.onNodeWithTag("delete.confirm").assertIsNotEnabled()
        assertEquals("Google is asked once", 1, identity.asked.get())

        identity.gate.complete(Unit)
        waitUntil { shown("Continue with Google") }
        assertFalse("never 'expired' after a deletion", shown(context.getString(R.string.signin_expired)))
        assertEquals(1, relay.calls.count { it.startsWith("delete:") })
        assertEquals(Routes.SIGN_IN, nav.currentBackStackEntry?.destination?.route)
        assertNull("nothing under the sign-in screen", nav.previousBackStackEntry)
    }

    /**
     * Delete Account for an account that signed in with an emailed code: the row says "Email code", the code goes to
     * the account's address, the typed code survives a recreated window without a second mail, and one tap on Delete
     * Account deletes with it (no Google, no nonce), ending on a clean sign-in.
     */
    @Test
    fun anEmailSessionDeletesItsAccountWithACode() {
        val mac = mac()
        val secrets = DemoSecretStore()
        runBlocking {
            val vault = AccountVault(secrets, Dispatchers.IO)
            vault.setSession(StoredSession("u1", "d1", "tok-1", "phu@example.com", AccountAuthMethod.EMAIL))
            vault.setMachines(listOf(mac.machine), "u1")
        }
        val identity = GatedIdentity()
        val relay = ScriptedRelay(listOf(mac.machine))
        val environment = testEnvironment(
            folder.root, Dispatchers.IO, secrets, MemoryKeyValueStore(), TestNetworkMonitor(), ManualClock(), identity,
        )
        val composition = AppComposition(
            environment = environment,
            appScope = appScope,
            relays = { vault -> RelayBundle(relay, FakeMacFleet(listOf(mac)) { vault.phoneKey() }) },
        )
        lateinit var nav: NavHostController
        val window: @Composable () -> Unit = {
            ShellXAppTheme(AppAppearance.SYSTEM) { ShellXApp(composition, rememberNavController().also { nav = it }) }
        }
        rule.setContent(window)
        rule.runOnUiThread { composition.lifecycle.onStart() }
        waitUntil { shown("shellx-ios") }
        rule.runOnUiThread { nav.navigate(Routes.SETTINGS) }
        waitUntil { tagShown("settings.delete") }
        assertTrue("the row says how the account signed in", shown("Email code"))

        rule.onNodeWithTag("settings.delete").performClick()
        waitUntil { tagShown("delete.confirm") }
        rule.onNodeWithTag("delete.confirm").performClick()
        waitUntil { tagShown("delete.code.field") }
        assertEquals(listOf("email:code:phu@example.com:en"), relay.calls.filter { it.startsWith("email:code:") })
        rule.onNodeWithTag("delete.code.field").performTextInput("654321")
        rule.waitForIdle()

        rule.activityRule.scenario.recreate()
        rule.setContent(window)
        waitUntil { tagShown("delete.code.field") }
        assertEquals("654321", rule.onNodeWithTag("delete.code.field").fetchSemanticsNode().config[SemanticsProperties.EditableText].text)
        assertEquals("no second mail", 1, relay.calls.count { it.startsWith("email:code:") })

        rule.onNodeWithTag("delete.confirm").performClick()
        waitUntil { shown("Continue with Google") }
        assertEquals(1, relay.calls.count { it == "delete:code:challenge-1:654321" })
        assertEquals("no other deletion: ${relay.calls}", 1, relay.calls.count { it.startsWith("delete:") })
        assertFalse("no nonce: ${relay.calls}", relay.calls.contains("nonce"))
        assertEquals("Google is never asked", 0, identity.asked.get())
        assertFalse("never 'expired' after a deletion", shown(context.getString(R.string.signin_expired)))
    }

    /** Sign out from Settings, with a page opened and closed on the way: the sign-in screen with a cleared stack. */
    @Test
    fun signingOutFromSettingsClearsTheStack() {
        val mac = mac()
        val t = mainComposition(folder.root, macs = listOf(mac), appScope = appScope)
        lateinit var nav: NavHostController
        rule.setContent {
            ShellXAppTheme(AppAppearance.SYSTEM) { ShellXApp(t.composition, rememberNavController().also { nav = it }) }
        }
        rule.runOnUiThread { t.composition.lifecycle.onStart() }
        waitUntil { shown("shellx-ios") }
        rule.runOnUiThread { nav.navigate(Routes.SETTINGS) }
        rule.runOnUiThread { nav.navigate(Routes.MACHINES) }
        rule.runOnUiThread { nav.popBackStack() }
        waitUntil { tagShown("settings.signOut") }

        rule.onNodeWithTag("settings.signOut").performClick()
        val confirm = hasText(context.getString(R.string.settings_account_sign_out)) and hasClickAction() and hasAnyAncestor(isDialog())
        waitUntil { rule.onAllNodes(confirm).fetchSemanticsNodes().isNotEmpty() }
        rule.onNode(confirm).performClick()

        waitUntil { shown("Continue with Google") }
        assertFalse(shown(context.getString(R.string.signin_expired)))
        assertEquals(Routes.SIGN_IN, nav.currentBackStackEntry?.destination?.route)
        assertNull(nav.previousBackStackEntry)
        assertEquals(1, t.relay.calls.count { it == "logout" })
    }
}
