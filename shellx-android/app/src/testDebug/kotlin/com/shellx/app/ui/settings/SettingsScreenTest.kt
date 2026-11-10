package com.shellx.app.ui.settings

import android.app.Application
import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.ui.theme.AppAppearance
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.account.SignInException
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.platform.MemoryKeyValueStore
import com.shellx.core.voice.SpeechEngine
import com.shellx.core.voice.SpeechRunId
import com.shellx.core.voice.VoiceCapabilities
import com.shellx.core.voice.VoiceCapabilityCache
import com.shellx.core.voice.VoiceLanguage
import com.shellx.core.voice.VoicePermissionChecking
import com.shellx.core.voice.VoiceService
import kotlin.time.TestTimeSource
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ReceiveChannel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** A recognizer that hears nothing (not 3E's FakeSpeechEngine). */
private object SilentSpeechEngine : SpeechEngine {
    override suspend fun start(run: SpeechRunId, language: VoiceLanguage, contextualStrings: List<String>): ReceiveChannel<String> =
        Channel<String>().apply { close() }

    override suspend fun finish(run: SpeechRunId): String = ""

    override suspend fun cancel(run: SpeechRunId) {}
}

/** Every permission granted, nothing to ask. */
private object GrantedVoicePermissions : VoicePermissionChecking {
    override suspend fun needsPrompt(): Boolean = false

    override suspend fun microphone(): Boolean = true

    override suspend fun speech(): Boolean = true
}

/** A voice service whose phone recognises [language] through the speech service only. */
internal fun settingsVoiceService(scope: CoroutineScope, language: VoiceLanguage = VoiceLanguage.ENGLISH): VoiceService {
    val time = TestTimeSource()
    val settings = MemoryKeyValueStore()
    language.save(settings)
    return VoiceService(
        SilentSpeechEngine, GrantedVoicePermissions,
        VoiceCapabilityCache(timeSource = time) { VoiceCapabilities(onDeviceRecognizer = false, standardOnDevice = false, standardAvailable = true) },
        LatencyLog(), settings, scope, time, listOf("en-US"), { emptyList() },
    )
}

/** Settings: its sections in the contract order, Sign out and Delete Account…, the demo, Appearance and Licenses. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w400dp-h2000dp")
class SettingsScreenTest {
    @get:Rule val rule = createComposeRule()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val voiceScope = CoroutineScope(SupervisorJob())

    private var signOuts = 0
    private var deletes = 0
    private val appearances = mutableListOf<AppAppearance>()

    @After
    fun tearDown() {
        voiceScope.cancel()
    }

    private fun account(signOut: suspend () -> Unit = {}, delete: suspend () -> Unit = {}) = AccountActions(
        signOut = {
            signOuts++
            signOut()
        },
        deleteAccount = {
            deletes++
            delete()
        },
    )

    @Composable
    private fun Screen(account: AccountActions? = account(), email: String = "phu@example.com", voice: VoiceService? = null) {
        ShellXTheme {
            SettingsScreen(
                email = email, account = account, appearance = AppAppearance.SYSTEM, onAppearance = { appearances += it },
                voice = voice, version = "1.0.0 (100)", openMachines = {}, back = {},
            )
        }
    }

    private fun string(id: Int) = context.getString(id)

    private fun dialogButton(label: String) = rule.onNode(hasText(label) and hasClickAction() and hasAnyAncestor(isDialog()))

    /** The section headings in the list, top to bottom. */
    private fun headings(): List<String> = rule.onAllNodes(
        SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading) and hasAnyAncestor(hasTestTag("settings.list")),
        useUnmergedTree = true,
    ).fetchSemanticsNodes()
        .sortedBy { it.boundsInRoot.top }
        .map { node -> node.config[SemanticsProperties.Text].joinToString { it.text } }

    @Test
    fun sectionsComeInTheContractOrder() {
        var voice by mutableStateOf<VoiceService?>(settingsVoiceService(voiceScope))
        rule.setContent { Screen(voice = voice) }

        assertEquals(listOf("Account", "Appearance", "Voice", "About"), headings())
        val machines = rule.onNodeWithTag("settings.machines").fetchSemanticsNode().boundsInRoot.top
        val accountHeading = rule.onNode(hasText("Account") and hasAnyAncestor(hasTestTag("settings.list")), useUnmergedTree = true)
            .fetchSemanticsNode().boundsInRoot.top
        assertTrue("Your Macs sits above the Account heading", machines < accountHeading)
        rule.onNodeWithTag("settings.voice.language").assertIsDisplayed()

        voice = null
        rule.waitForIdle()
        assertEquals(listOf("Account", "Appearance", "About"), headings())
    }

    @Test
    fun signOutAsksFirst() {
        rule.setContent { Screen() }

        rule.onNodeWithTag("settings.signOut").performClick()
        rule.onNodeWithText(string(R.string.settings_account_sign_out_confirm)).assertIsDisplayed()
        assertEquals(0, signOuts)
        dialogButton(string(R.string.settings_account_sign_out)).performClick()
        rule.waitForIdle()

        assertEquals(1, signOuts)
        rule.onNodeWithText(string(R.string.settings_account_sign_out_confirm)).assertDoesNotExist()
    }

    @Test
    fun signOutTappedTwiceSignsOutOnce() {
        val gate = CompletableDeferred<Unit>()
        rule.setContent { Screen(account = account(signOut = { gate.await() })) }

        rule.onNodeWithTag("settings.signOut").performClick()
        // Two taps on Sign out in the question before it closes.
        dialogButton(string(R.string.settings_account_sign_out)).performTouchInput {
            click()
            advanceEventTime(100)
            click()
        }
        rule.waitForIdle()
        assertEquals(1, signOuts)

        // While it signs out, the row is off: the question cannot come back for a second sign-out.
        rule.onNodeWithTag("settings.signOut").assertIsNotEnabled()
        rule.onNodeWithTag("settings.signOut").performClick()
        rule.waitForIdle()
        rule.onNodeWithText(string(R.string.settings_account_sign_out_confirm)).assertDoesNotExist()
        assertEquals(1, signOuts)

        gate.complete(Unit)
        rule.waitForIdle()
        rule.onNodeWithTag("settings.signOut").assertIsEnabled()
        assertEquals(1, signOuts)
    }

    @Test
    fun deletingAsksThenWorksThenLeaves() {
        val gate = CompletableDeferred<Unit>()
        rule.setContent { Screen(account = account(delete = { gate.await() })) }

        rule.onNodeWithTag("settings.delete").performClick()
        rule.onNodeWithText(string(R.string.settings_account_delete_message)).assertIsDisplayed()
        assertEquals(0, deletes)
        rule.onNodeWithTag("delete.confirm").performClick()
        rule.waitForIdle()

        rule.onNodeWithTag("delete.working").assertIsDisplayed()
        rule.onNodeWithTag("delete.confirm").assertIsNotEnabled()
        rule.onNodeWithTag("delete.cancel").assertIsNotEnabled()
        rule.onNodeWithTag("delete.confirm").performClick()
        rule.waitForIdle()
        assertEquals(1, deletes)

        gate.complete(Unit)
        rule.waitForIdle()
        rule.onNodeWithTag("delete.working").assertIsDisplayed()
        assertEquals(1, deletes)
    }

    @Test
    fun aCancelledOrRefusedDeletionSaysSoInTheCard() {
        var failure: Exception = SignInException.Cancelled()
        rule.setContent { Screen(account = account(delete = { throw failure })) }

        rule.onNodeWithTag("settings.delete").performClick()
        rule.onNodeWithTag("delete.confirm").performClick()
        rule.waitForIdle()
        rule.onNodeWithText(string(R.string.settings_account_delete_message)).assertIsDisplayed()
        rule.onNodeWithTag("delete.error").assertDoesNotExist()
        rule.onNodeWithTag("delete.confirm").assertIsEnabled()

        failure = SignInException.ReauthRequired()
        rule.onNodeWithTag("delete.confirm").performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("delete.error").assertIsDisplayed()
            .assertTextEquals(string(R.string.signin_error_reauth_required))
        assertEquals(2, deletes)
    }

    @Test
    fun aSignOutAndADeletionUnderWaySurviveRecreation() {
        val signOutGate = CompletableDeferred<Unit>()
        val deleteGate = CompletableDeferred<Unit>()
        val restoration = StateRestorationTester(rule)
        restoration.setContent { Screen(account = account(signOut = { signOutGate.await() }, delete = { deleteGate.await() })) }
        rule.onNodeWithTag("settings.signOut").performClick()
        dialogButton(string(R.string.settings_account_sign_out)).performClick()
        rule.onNodeWithTag("settings.delete").performClick()
        rule.onNodeWithTag("delete.confirm").performClick()
        rule.waitForIdle()

        // A rotation, a theme or a language change while both wait.
        restoration.emulateSavedInstanceStateRestore()

        rule.onNodeWithTag("delete.working").assertIsDisplayed()
        rule.onNodeWithTag("delete.confirm").assertIsNotEnabled()
        rule.onNodeWithTag("settings.signOut").assertIsNotEnabled()
        assertEquals(1, signOuts)
        assertEquals(1, deletes)
        signOutGate.complete(Unit)
        deleteGate.complete(Unit)
        rule.waitForIdle()
        rule.onNodeWithTag("delete.working").assertIsDisplayed()
        assertEquals(1, deletes)
    }

    @Test
    fun theDemoShowsOnlyTheEmail() {
        rule.setContent { Screen(account = null, email = "demo@shellx.pro") }

        rule.onNodeWithText("demo@shellx.pro").assertIsDisplayed()
        rule.onNodeWithTag("settings.signOut").assertDoesNotExist()
        rule.onNodeWithTag("settings.delete").assertDoesNotExist()
    }

    @Test
    fun appearanceChangesAtOnce() {
        rule.setContent { Screen() }

        rule.onNodeWithText(string(R.string.settings_appearance_dark)).performClick()

        assertEquals(listOf(AppAppearance.DARK), appearances)
    }

    @Test
    fun licensesOpensTheWebsite() {
        val opened = mutableListOf<String>()
        val handler = object : UriHandler {
            override fun openUri(uri: String) {
                opened += uri
            }
        }
        rule.setContent { CompositionLocalProvider(LocalUriHandler provides handler) { Screen() } }

        rule.onNodeWithTag("settings.about.license").performClick()

        assertEquals(listOf("https://shellx.pro"), opened)
    }

    /** Review D m-6: with no app to open a web page (no browser, some work profiles), Licenses does nothing, no crash. */
    @Test
    fun licensesWithNoBrowserDoesNotCrash() {
        shadowOf(ApplicationProvider.getApplicationContext<Application>()).checkActivities(true)
        rule.setContent { Screen() }

        rule.onNodeWithTag("settings.about.license").performClick()
        rule.waitForIdle()

        rule.onNodeWithTag("settings.about.license").assertIsDisplayed()
    }
}
