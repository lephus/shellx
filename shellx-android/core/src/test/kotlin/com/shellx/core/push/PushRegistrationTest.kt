package com.shellx.core.push

import com.shellx.core.account.AccountVault
import com.shellx.core.account.StoredSession
import com.shellx.core.testing.FakeRelayAccount
import com.shellx.core.testing.InMemorySecretStore
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest

/** Keeping the relay holding this phone's FCM token while it is signed in, and never asking for a token while signed
 *  out. */
class PushRegistrationTest {
    /** Answers with [token] and counts the requests. */
    private class FakePushRegistrar(var token: String? = null) : PushRegistrar {
        var requests = 0
            private set

        override suspend fun currentToken(): String? {
            requests += 1
            return token
        }
    }

    private class Made(val push: PushRegistration, val relay: FakeRelayAccount, val vault: AccountVault, val registrar: FakePushRegistrar)

    private companion object {
        const val TOKEN = "fcm-1"
    }

    private suspend fun TestScope.make(signedIn: Boolean = true): Made {
        val vault = AccountVault(InMemorySecretStore(), StandardTestDispatcher(testScheduler))
        if (signedIn) vault.setSession(StoredSession("u1", "d1", "tok-1", "a@b.c"))
        val relay = FakeRelayAccount()
        val registrar = FakePushRegistrar()
        return Made(PushRegistration(relay, vault, registrar), relay, vault, registrar)
    }

    private fun sets(relay: FakeRelayAccount): List<FakeRelayAccount.Call> =
        relay.calls.filter { it is FakeRelayAccount.Call.SetPushToken }

    @Test fun aNewTokenGoesToTheRelayWithTheSessionToken() { runTest {
        val made = make()

        made.push.tokenArrived(TOKEN)

        assertEquals(listOf(FakeRelayAccount.Call.SetPushToken("fcm-1", "tok-1")), sets(made.relay))
    } }

    @Test fun theSameTokenForTheSameSignInIsSentOnce() { runTest {
        val made = make()

        made.push.tokenArrived(TOKEN)
        made.push.tokenArrived(TOKEN)
        made.push.signedIn()

        assertEquals(1, sets(made.relay).size)
    } }

    @Test fun aTokenFromBeforeSignInIsSentOnceSignedIn() { runTest {
        val made = make(signedIn = false)

        made.push.tokenArrived(TOKEN)
        assertEquals(emptyList(), sets(made.relay))

        made.vault.setSession(StoredSession("u1", "d2", "tok-2", "a@b.c"))
        made.push.signedIn()

        assertEquals(listOf(FakeRelayAccount.Call.SetPushToken("fcm-1", "tok-2")), sets(made.relay))
    } }

    @Test fun aFailedSendIsTriedAgainNextTime() { runTest {
        val made = make()
        made.relay.setError(IOException("offline"), FakeRelayAccount.Function.SET_PUSH_TOKEN)
        made.push.tokenArrived(TOKEN)

        made.relay.setError(null, FakeRelayAccount.Function.SET_PUSH_TOKEN)
        made.push.signedIn()

        assertEquals(2, sets(made.relay).size)
    } }

    @Test fun comingBackToTheFrontSendsTheKnownTokenAgainInCaseTheRelayDroppedIt() { runTest {
        val made = make()
        made.push.tokenArrived(TOKEN)

        made.push.appBecameActive()

        val calls = sets(made.relay)
        assertEquals(2, calls.size)
        assertEquals(FakeRelayAccount.Call.SetPushToken("fcm-1", "tok-1"), calls.last())
    } }

    @Test fun comingBackToTheFrontWithoutATokenSendsNothing() { runTest {
        val made = make()

        made.push.appBecameActive()

        assertEquals(emptyList(), sets(made.relay))
    } }

    @Test fun anotherSignInSendsTheTokenAgain() { runTest {
        val made = make()
        made.push.tokenArrived(TOKEN)

        made.vault.setSession(StoredSession("u2", "d3", "tok-3", "b@b.c"))
        made.push.signedIn()

        val calls = sets(made.relay)
        assertEquals(FakeRelayAccount.Call.SetPushToken("fcm-1", "tok-3"), calls.last())
        assertEquals(2, calls.size)
    } }

    @Test fun signedInAsksTheRegistrarWhenNoTokenArrived() { runTest {
        val made = make()
        made.registrar.token = "fcm-2"

        made.push.signedIn()

        assertEquals(1, made.registrar.requests)
        assertEquals(listOf(FakeRelayAccount.Call.SetPushToken("fcm-2", "tok-1")), sets(made.relay))
    } }

    @Test fun appBecameActiveWithoutASessionRequestsNoToken() { runTest {
        val vault = AccountVault(InMemorySecretStore(), StandardTestDispatcher(testScheduler))   // no session stored
        val relay = FakeRelayAccount()
        val registrar = FakePushRegistrar(token = "fcm-2")
        val push = PushRegistration(relay, vault, registrar)
        push.appBecameActive()
        push.signedIn()
        assertEquals(0, registrar.requests)                       // no FCM token is requested or created while signed out
        assertEquals(emptyList(), relay.calls)
        vault.setSession(StoredSession("u1", "d2", "tok-2", "a@b.c"))
        push.signedIn()
        assertEquals(1, registrar.requests)
        assertEquals(listOf(FakeRelayAccount.Call.SetPushToken("fcm-2", "tok-2")), relay.calls)
    } }
}
