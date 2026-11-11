package com.shellx.core.account

import com.shellx.core.platform.MemoryKeyValueStore
import com.shellx.core.testing.CoordinatorRig
import com.shellx.core.testing.FakeRelayAccount.Call
import com.shellx.core.testing.FakeRelayAccount.Function
import com.shellx.core.testing.FlakyWiper
import com.shellx.core.testing.Gate
import com.shellx.core.testing.assertSameCase
import com.shellx.core.testing.coordinatorRig
import com.shellx.core.testing.eventually
import com.shellx.core.testing.hex
import com.shellx.link.account.AccountSession
import com.shellx.link.account.AccountSignIn
import com.shellx.link.account.EmailChallenge
import com.shellx.link.account.RelayApiException
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue
import kotlinx.coroutines.async
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

/** Sign-in with an emailed code, and account deletion by one (spec §3, §4). */
class AppCoordinatorEmailTest {
    private val emailSignIn = AccountSignIn(AccountSession("u1", "d1", "tok-e"), "e@example.com")
    private val emailSession = StoredSession("u1", "d1", "tok-old", "e@example.com", AccountAuthMethod.EMAIL)

    private suspend fun TestScope.rig(pendingSettings: MemoryKeyValueStore = MemoryKeyValueStore(), wipers: List<LocalDataWiping> = emptyList()): CoordinatorRig {
        val rig = coordinatorRig(extraWipers = wipers, pendingSettings = pendingSettings)
        rig.relay.setEmailSignIn(Result.success(emailSignIn))
        return rig
    }

    /** The stored email session "tok-old" for u1, then launch(). */
    private suspend fun TestScope.signedInRig(): CoordinatorRig {
        val rig = rig()
        rig.vault.setSession(emailSession)
        rig.coordinator.launch()
        return rig
    }

    private fun assertNothingStored(rig: CoordinatorRig) {
        for (item in SecretItem.entries) assertNull(rig.store.read(item), "$item")
    }

    @Test fun emailSignInVerifiesWithThePhoneKeyAndStoresAnEmailSession() { runTest {
        val rig = rig()
        rig.coordinator.launch()

        assertEquals(EmailChallenge("challenge-1", 600, 60, "e@example.com"), rig.coordinator.requestEmailCode("E@Example.com", "vi"))
        assertEquals(AppPhase.SignedOut(false), rig.coordinator.phase.value)
        rig.coordinator.signInWithEmailCode("challenge-1", "123456")

        assertEquals(
            listOf(
                Call.RequestEmailCode("E@Example.com", "vi"),
                Call.SignInWithEmailCode("challenge-1", "123456", "Phu's Pixel", rig.vault.phoneKey().publicKey.hex()),
            ),
            rig.relay.calls,
        )
        assertEquals(StoredSession("u1", "d1", "tok-e", "e@example.com", AccountAuthMethod.EMAIL), rig.vault.session())
        assertEquals(AppPhase.SignedIn("e@example.com", AccountAuthMethod.EMAIL), rig.coordinator.phase.value)
        assertNotNull(rig.coordinator.hub.value)
        assertTrue(rig.identity.googleNonces.isEmpty(), "Google is never asked")
    } }

    @Test fun codeRequestErrorsMap() { runTest {
        val rig = rig()
        rig.coordinator.launch()
        val cases: List<Pair<Exception, SignInException>> = listOf(
            RelayApiException.Http(400, "invalid_email") to SignInException.InvalidEmail(),
            RelayApiException.Http(400, "disposable_email") to SignInException.DisposableEmail(),
            RelayApiException.Http(429, "rate_limited") to SignInException.RateLimited(),
            RelayApiException.Http(503, "email_sign_in_disabled") to SignInException.ProviderUnavailable(),
            RelayApiException.Http(502, "email_send_failed") to SignInException.EmailSendFailed(),
            RelayApiException.Http(404, "not_found") to SignInException.ProviderUnavailable(),
            IOException("offline") to SignInException.Network(),
        )
        for ((thrown, expected) in cases) {
            rig.relay.setError(thrown, Function.REQUEST_EMAIL_CODE)
            assertSameCase(expected, assertFails { rig.coordinator.requestEmailCode("e@example.com", "en") }, "$thrown")
        }
        assertEquals(AppPhase.SignedOut(false), rig.coordinator.phase.value)
    } }

    @Test fun verifyErrorsMapAndStoreNothing() { runTest {
        val rig = rig()
        rig.coordinator.launch()
        val cases: List<Pair<Exception, SignInException>> = listOf(
            RelayApiException.Http(401, "invalid_code") to SignInException.InvalidCode(),
            RelayApiException.Http(410, "code_expired") to SignInException.CodeExpired(),
            RelayApiException.Http(409, "switch_from_signed_in_device") to SignInException.SwitchFromSignedInDevice(),
            RelayApiException.Http(400, "invalid_device") to SignInException.Server("invalid_device"),
            RelayApiException.Http(429, "x") to SignInException.RateLimited(),
            RelayApiException.Http(404, "not_found") to SignInException.ProviderUnavailable(),
        )
        for ((thrown, expected) in cases) {
            rig.relay.setError(thrown, Function.SIGN_IN_WITH_EMAIL_CODE)
            assertSameCase(expected, assertFails { rig.coordinator.signInWithEmailCode("challenge-1", "123456") }, "$thrown")
            assertEquals(AppPhase.SignedOut(false), rig.coordinator.phase.value, "$thrown")
            assertNull(rig.vault.session(), "$thrown")
            assertNull(rig.coordinator.hub.value, "$thrown")
        }
    } }

    @Test fun aPendingWipeBlocksTheCodeRequestBeforeAnyRelayCall() { runTest {
        val pending = MemoryKeyValueStore()
        pending.putBoolean(AppCoordinator.PENDING_WIPE_KEY, true)
        val rig = rig(pendingSettings = pending, wipers = listOf(FlakyWiper()))

        assertSameCase(SignInException.LocalWipePending(), assertFails { rig.coordinator.requestEmailCode("e@example.com", "en") })
        // A code step that outlived the failed wipe (a restored one) is refused the same way.
        assertSameCase(SignInException.LocalWipePending(), assertFails { rig.coordinator.signInWithEmailCode("challenge-1", "123456") })
        assertEquals(emptyList(), rig.relay.calls)
    } }

    /** Review Focus 3: a double tap on Verify, or a tap right after the sixth digit submitted by itself. */
    @Test fun aSecondVerifyWhileOneRunsJoinsIt() { runTest {
        val rig = rig()
        rig.coordinator.launch()
        val gate = Gate()
        rig.relay.setHook({ gate.wait() }, Function.SIGN_IN_WITH_EMAIL_CODE)

        val first = async { rig.coordinator.signInWithEmailCode("challenge-1", "123456") }
        assertTrue(eventually { gate.waiting == 1 })
        val second = async { rig.coordinator.signInWithEmailCode("challenge-1", "123456") }
        runCurrent()
        gate.open()
        first.await()
        second.await()

        assertEquals(1, rig.relay.calls.count { it is Call.SignInWithEmailCode }, "one verify: a second would spend a try")
        assertEquals(AppPhase.SignedIn("e@example.com", AccountAuthMethod.EMAIL), rig.coordinator.phase.value)
    } }

    @Test fun deletionByCodeMailsTheSessionsAddressThenDeletesAndWipes() { runTest {
        val rig = signedInRig()

        assertEquals(EmailChallenge("challenge-1", 600, 60, "e@example.com"), rig.coordinator.requestAccountDeletionCode("en"))
        assertEquals(listOf<Call>(Call.RequestEmailCode("e@example.com", "en")), rig.relay.calls)
        assertEquals(AppPhase.SignedIn("e@example.com", AccountAuthMethod.EMAIL), rig.coordinator.phase.value)

        rig.coordinator.deleteAccountWithEmailCode("challenge-1", "654321")

        // No nonce, no Google, no unpair, push or logout call: the account is gone.
        assertEquals(
            listOf(Call.RequestEmailCode("e@example.com", "en"), Call.DeleteAccountWithEmailCode("challenge-1", "654321", "tok-old")),
            rig.relay.calls,
        )
        assertTrue(rig.identity.googleNonces.isEmpty(), "Google is never asked")
        assertEquals(AppPhase.SignedOut(false), rig.coordinator.phase.value)
        assertNothingStored(rig)
        assertEquals(1, rig.wiper.wipes)
        assertNull(rig.coordinator.hub.value)
    } }

    @Test fun aWrongOrExpiredDeletionCodeKeepsEverything() { runTest {
        val rig = signedInRig()
        val hub = assertNotNull(rig.coordinator.hub.value)
        val cases: List<Pair<Exception, SignInException>> = listOf(
            RelayApiException.Http(401, "invalid_code") to SignInException.InvalidCode(),
            RelayApiException.Http(410, "code_expired") to SignInException.CodeExpired(),
            RelayApiException.Http(401, "reauth_required") to SignInException.ReauthRequired(),
            RelayApiException.Http(404, "not_found") to SignInException.ProviderUnavailable(),
            IOException("offline") to SignInException.Network(),
        )
        for ((thrown, expected) in cases) {
            rig.relay.setError(thrown, Function.DELETE_ACCOUNT_WITH_EMAIL_CODE)
            assertSameCase(expected, assertFails { rig.coordinator.deleteAccountWithEmailCode("challenge-1", "654321") }, "$thrown")
            assertEquals(emailSession, rig.vault.session(), "$thrown")
            assertSame(hub, rig.coordinator.hub.value, "$thrown")
            assertEquals(AppPhase.SignedIn("e@example.com", AccountAuthMethod.EMAIL), rig.coordinator.phase.value, "$thrown")
        }
        assertEquals(0, rig.wiper.wipes)

        // A code request that fails keeps everything too.
        rig.relay.setError(RelayApiException.Http(502, "email_send_failed"), Function.REQUEST_EMAIL_CODE)
        assertSameCase(SignInException.EmailSendFailed(), assertFails { rig.coordinator.requestAccountDeletionCode("en") })
        assertEquals(emailSession, rig.vault.session())
    } }

    @Test fun deletionByCodeWithARefusedTokenSignsOutAsExpired() { runTest {
        val rig = signedInRig()
        rig.relay.setError(RelayApiException.Http(401, "unauthorized"), Function.DELETE_ACCOUNT_WITH_EMAIL_CODE)

        assertSameCase(SignInException.Server("unauthorized"), assertFails { rig.coordinator.deleteAccountWithEmailCode("challenge-1", "654321") })

        assertEquals(AppPhase.SignedOut(true), rig.coordinator.phase.value)
        assertNull(rig.coordinator.hub.value)
        assertNull(rig.vault.session())
    } }

    @Test fun deletionByCodeWithoutASessionIsSignedOut() { runTest {
        val rig = rig()
        rig.coordinator.launch()
        assertSameCase(SignInException.Server("signed_out"), assertFails { rig.coordinator.requestAccountDeletionCode("en") })
        assertSameCase(SignInException.Server("signed_out"), assertFails { rig.coordinator.deleteAccountWithEmailCode("challenge-1", "654321") })
        assertEquals(emptyList(), rig.relay.calls)
    } }

    /** Google's sheet never opens for an account that signed in with a code. */
    @Test fun googlesDeletionRefusesAnEmailSession() { runTest {
        val rig = signedInRig()
        val hub = assertNotNull(rig.coordinator.hub.value)

        assertSameCase(SignInException.Server("code_required"), assertFails { rig.coordinator.deleteAccount() })

        assertEquals(emptyList(), rig.relay.calls)
        assertTrue(rig.identity.googleNonces.isEmpty(), "Google is never asked")
        assertEquals(emailSession, rig.vault.session())
        assertSame(hub, rig.coordinator.hub.value)
        assertEquals(AppPhase.SignedIn("e@example.com", AccountAuthMethod.EMAIL), rig.coordinator.phase.value)
    } }
}
