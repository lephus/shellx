package com.shellx.app.ui.settings

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
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
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import com.shellx.app.testing.ManualClock
import com.shellx.app.ui.theme.AppAppearance
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.core.account.AccountAuthMethod
import com.shellx.core.account.EmailCodeActions
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
import com.shellx.link.account.EmailChallenge
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

/**
 * Settings: its sections in the contract order, Sign out and Delete Account… (with Google's fresh sign-in, or with a
 * mailed code for an account that signed in with one), the demo, Appearance and Licenses.
 */
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

    /** The deletion codes asked for and the deletions sent with one, in order. */
    private val requests = mutableListOf<Pair<String, String>>()
    private val verifies = mutableListOf<Pair<String, String>>()

    /** What the next code request and the next deletion by code throw, one each; then they succeed. */
    private val requestFailures = ArrayDeque<SignInException>()
    private val verifyFailures = ArrayDeque<SignInException>()

    /** While set, a deletion by code waits for it. */
    private var heldVerify: CompletableDeferred<Unit>? = null

    /** Deletion by a mailed code, as the test scripts the relay: the challenge is "c1". */
    private val emailDeletion = EmailCodeActions(
        requestCode = { address, locale ->
            requests += address to locale
            requestFailures.removeFirstOrNull()?.let { throw it }
            EmailChallenge("c1", 600, 60, "phu@example.com")
        },
        verify = { challengeId, code ->
            verifies += challengeId to code
            heldVerify?.await()
            verifyFailures.removeFirstOrNull()?.let { throw it }
        },
    )

    private fun account(
        signOut: suspend () -> Unit = {},
        delete: suspend () -> Unit = {},
        emailDeletion: EmailCodeActions? = null,
    ) = AccountActions(
        signOut = {
            signOuts++
            signOut()
        },
        deleteAccount = {
            deletes++
            delete()
        },
        emailDeletion = emailDeletion,
    )

    @Composable
    private fun Screen(
        account: AccountActions? = account(),
        email: String = "phu@example.com",
        voice: VoiceService? = null,
        authMethod: AccountAuthMethod = AccountAuthMethod.GOOGLE,
    ) {
        ShellXTheme {
            SettingsScreen(
                email = email, account = account, appearance = AppAppearance.SYSTEM, onAppearance = { appearances += it },
                voice = voice, version = "1.0.0 (100)", openMachines = {}, back = {}, authMethod = authMethod, clock = ManualClock(),
            )
        }
    }

    /** Settings of an account that signed in with an emailed code. */
    @Composable
    private fun EmailScreen() = Screen(account = account(emailDeletion = emailDeletion), authMethod = AccountAuthMethod.EMAIL)

    /** From Settings to the deletion's code step: Delete Account…, then Delete Account on the question. */
    private fun reachTheDeletionCode() {
        rule.onNodeWithTag("settings.delete").performClick()
        rule.onNodeWithTag("delete.confirm").performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("delete.code.field").assertIsDisplayed()
    }

    /** What a field shows: its editable text. */
    private fun fieldText(tag: String): String =
        rule.onNodeWithTag(tag).fetchSemanticsNode().config[SemanticsProperties.EditableText].text

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

        assertEquals(listOf("Account", "Appearance", "Voice", "Notifications", "About"), headings())
        val machines = rule.onNodeWithTag("settings.machines").fetchSemanticsNode().boundsInRoot.top
        val accountHeading = rule.onNode(hasText("Account") and hasAnyAncestor(hasTestTag("settings.list")), useUnmergedTree = true)
            .fetchSemanticsNode().boundsInRoot.top
        assertTrue("Your Macs sits above the Account heading", machines < accountHeading)
        rule.onNodeWithTag("settings.voice.language").assertIsDisplayed()

        voice = null
        rule.waitForIdle()
        assertEquals(listOf("Account", "Appearance", "Notifications", "About"), headings())
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

    // An account that signed in with an emailed code.

    @Test
    fun anEmailSessionsRowIsLabelledEmailCode() {
        var method by mutableStateOf(AccountAuthMethod.EMAIL)
        var account by mutableStateOf<AccountActions?>(account(emailDeletion = emailDeletion))
        rule.setContent { Screen(account = account, authMethod = method) }
        val row = { label: String -> hasText(label) and hasText("phu@example.com") and hasAnyAncestor(hasTestTag("settings.list")) }

        rule.onNode(row("Email code")).assertIsDisplayed()

        method = AccountAuthMethod.GOOGLE
        rule.waitForIdle()
        rule.onNode(row("Email")).assertIsDisplayed()
        rule.onNodeWithText("Email code").assertDoesNotExist()

        // The demo's account is nobody's.
        account = null
        rule.waitForIdle()
        rule.onNode(row("Email")).assertIsDisplayed()
    }

    /** Review Focus 8: the sixth digit never deletes by itself. */
    @Test
    fun deletingAnEmailAccountAsksForACodeAndNeedsATap() {
        rule.setContent { EmailScreen() }

        rule.onNodeWithTag("settings.delete").performClick()
        rule.onNodeWithText(string(R.string.settings_account_delete_message)).assertIsDisplayed()
        assertEquals("nothing is mailed before the question is answered", emptyList<Pair<String, String>>(), requests)
        rule.onNodeWithTag("delete.confirm").performClick()
        rule.waitForIdle()

        assertEquals(listOf("phu@example.com" to "en"), requests)
        rule.onNodeWithTag("delete.code.intro").assertTextEquals(string(R.string.settings_account_delete_code_intro))
        // In the card: the e-mail row behind the dialog shows the address too.
        rule.onNode(hasText("phu@example.com") and hasAnyAncestor(isDialog())).assertIsDisplayed()
        rule.onNodeWithTag("delete.code.resend").assertTextEquals("Resend code in 60 s").assertIsNotEnabled()
        rule.onNodeWithTag("delete.confirm").assertIsNotEnabled()

        rule.onNodeWithTag("delete.code.field").performTextInput("654 321")
        rule.waitForIdle()
        assertEquals("654321", fieldText("delete.code.field"))
        assertEquals("six digits wait for the tap", emptyList<Pair<String, String>>(), verifies)

        rule.onNodeWithTag("delete.confirm").assertIsEnabled().performClick()
        rule.waitForIdle()
        assertEquals(listOf("c1" to "654321"), verifies)
        rule.onNodeWithTag("delete.working").assertIsDisplayed()
        rule.onNodeWithTag("delete.confirm").assertIsNotEnabled()
        assertEquals("Google's path is never taken", 0, deletes)
        assertEquals(1, requests.size)
    }

    @Test
    fun aWrongDeletionCodeSaysSoAndKeepsTheCard() {
        verifyFailures += SignInException.InvalidCode()
        rule.setContent { EmailScreen() }
        reachTheDeletionCode()
        rule.onNodeWithTag("delete.code.field").performTextInput("654321")
        rule.onNodeWithTag("delete.confirm").performClick()
        rule.waitForIdle()

        rule.onNodeWithTag("delete.error").assertTextEquals(string(R.string.signin_error_invalid_code))
        assertEquals("", fieldText("delete.code.field"))
        rule.onNodeWithTag("delete.confirm").assertIsNotEnabled()
        rule.onNodeWithTag("delete.cancel").assertIsEnabled()

        // The right code then deletes.
        rule.onNodeWithTag("delete.code.field").performTextInput("123456")
        rule.onNodeWithTag("delete.confirm").performClick()
        rule.waitForIdle()
        assertEquals(listOf("c1" to "654321", "c1" to "123456"), verifies)
        rule.onNodeWithTag("delete.working").assertIsDisplayed()
    }

    @Test
    fun aCodeThatCannotBeSentSaysSoOnTheQuestion() {
        requestFailures += SignInException.EmailSendFailed()
        rule.setContent { EmailScreen() }
        rule.onNodeWithTag("settings.delete").performClick()
        rule.onNodeWithTag("delete.confirm").performClick()
        rule.waitForIdle()

        rule.onNodeWithTag("delete.error").assertTextEquals(string(R.string.signin_error_email_send_failed))
        rule.onNodeWithTag("delete.code.field").assertDoesNotExist()
        rule.onNodeWithText(string(R.string.settings_account_delete_message)).assertIsDisplayed()
        rule.onNodeWithTag("delete.confirm").assertIsEnabled()

        // Cancel closes the question; opening it again starts afresh.
        rule.onNodeWithTag("delete.cancel").performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("delete.confirm").assertDoesNotExist()
        rule.onNodeWithTag("settings.delete").performClick()
        rule.onNodeWithTag("delete.error").assertDoesNotExist()
    }

    @Test
    fun theCodeCardStaysWhileItDeletes() {
        heldVerify = CompletableDeferred()
        rule.setContent { EmailScreen() }
        reachTheDeletionCode()
        rule.onNodeWithTag("delete.code.field").performTextInput("654321")
        rule.onNodeWithTag("delete.confirm").performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("delete.working").assertIsDisplayed()

        rule.onNodeWithTag("delete.cancel").assertIsNotEnabled().performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("delete.working").assertIsDisplayed()
        assertEquals(1, verifies.size)

        heldVerify?.complete(Unit)
        rule.waitForIdle()
        rule.onNodeWithTag("delete.working").assertIsDisplayed()
        assertEquals(1, verifies.size)
    }

    @Test
    fun aGoogleSessionStillConfirmsWithGoogle() {
        val gate = CompletableDeferred<Unit>()
        rule.setContent { Screen(account = account(delete = { gate.await() }, emailDeletion = emailDeletion)) }

        rule.onNodeWithTag("settings.delete").performClick()
        rule.onNodeWithTag("delete.confirm").performClick()
        rule.waitForIdle()

        assertEquals(1, deletes)
        assertEquals(emptyList<Pair<String, String>>(), requests)
        rule.onNodeWithTag("delete.code.field").assertDoesNotExist()
        rule.onNodeWithTag("delete.working").assertIsDisplayed()
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
}
