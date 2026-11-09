package com.shellx.app.platform

import android.app.Activity
import android.app.Application
import androidx.activity.ComponentActivity
import androidx.credentials.Credential
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.PasswordCredential
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialProviderConfigurationException
import androidx.credentials.exceptions.GetCredentialUnknownException
import androidx.credentials.exceptions.GetCredentialUnsupportedException
import androidx.credentials.exceptions.NoCredentialException
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.shellx.core.account.IdentityProviderException
import java.util.Base64
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric

@RunWith(AndroidJUnit4::class)
class CredentialManagerIdentityTest {
    private val activity: Activity = Robolectric.buildActivity(ComponentActivity::class.java).setup().get()

    private class FakeGetter(private val answer: () -> Credential) : CredentialGetter {
        val requests = mutableListOf<GetCredentialRequest>()
        val hosts = mutableListOf<Activity>()

        override suspend fun get(activity: Activity, request: GetCredentialRequest): GetCredentialResponse {
            requests += request
            hosts += activity
            return GetCredentialResponse(answer())
        }
    }

    /** googleid 1.2 reads `sub` and `email` from the token, so the fake is shaped like a JWT. */
    private fun jwt(subject: String): String {
        fun part(json: String) = Base64.getUrlEncoder().withoutPadding().encodeToString(json.toByteArray())
        return "${part("""{"alg":"none"}""")}.${part("""{"sub":"$subject","email":"a@b.c"}""")}.sig"
    }

    private fun googleToken(token: String): Credential = CustomCredential(
        GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL,
        GoogleIdTokenCredential.Builder().setId("a@b.c").setIdToken(token).build().data,
    )

    private fun identity(
        getter: CredentialGetter,
        client: String? = CLIENT,
        activity: suspend () -> Activity = { this.activity },
    ) = CredentialManagerIdentity(client, activity, getter)

    private suspend fun failure(identity: CredentialManagerIdentity): Throwable =
        try {
            identity.googleIdToken("n-1")
            throw AssertionError("googleIdToken returned")
        } catch (e: IdentityProviderException) {
            e
        }

    private suspend fun assertFails(expected: Class<out IdentityProviderException>, identity: CredentialManagerIdentity) {
        val error = failure(identity)
        assertEquals(expected, error.javaClass)
    }

    @Test
    fun aPlaceholderClientIsNotConfigured() {
        runTest {
            val getter = FakeGetter { googleToken(jwt("id-token-1")) }
            assertFails(IdentityProviderException.NotConfigured::class.java, identity(getter, client = null))
            assertTrue(getter.requests.isEmpty())
        }
    }

    @Test
    fun theRequestCarriesTheWebClientAndTheRelayNonce() {
        runTest {
            val token = jwt("id-token-1")
            val getter = FakeGetter { googleToken(token) }
            assertEquals(token, identity(getter).googleIdToken("n-1"))
            val options = getter.requests.single().credentialOptions
            assertEquals(1, options.size)
            val option = options.single() as GetSignInWithGoogleOption
            assertEquals(CLIENT, option.serverClientId)
            assertEquals("n-1", option.nonce)
        }
    }

    @Test
    fun closingGoogleSheetIsCancelled() {
        runTest {
            val getter = FakeGetter { throw GetCredentialCancellationException("x") }
            assertFails(IdentityProviderException.Cancelled::class.java, identity(getter))
        }
    }

    @Test
    fun noProviderIsNotConfigured() {
        runTest {
            for (error in listOf(GetCredentialProviderConfigurationException("x"), GetCredentialUnsupportedException("x"))) {
                assertFails(IdentityProviderException.NotConfigured::class.java, identity(FakeGetter { throw error }))
            }
        }
    }

    @Test
    fun otherFailuresAreFailed() {
        runTest {
            assertFails(IdentityProviderException.Failed::class.java, identity(FakeGetter { throw NoCredentialException("x") }))
            assertFails(IdentityProviderException.Failed::class.java, identity(FakeGetter { throw GetCredentialUnknownException("x") }))
            assertFails(IdentityProviderException.Failed::class.java, identity(FakeGetter { PasswordCredential("u", "p") }))
        }
    }

    // Final review F-2: Google's sheet is an activity started over ShellX's, which Android may block from the
    // background, so that no answer ever comes. The identity waits for ShellX to be in front again instead.

    @Test
    fun googleIsAskedOnlyOnceShellXIsInFrontAgain() {
        runTest {
            val front = MutableStateFlow<Activity?>(null)
            val token = jwt("id-token-1")
            val getter = FakeGetter { googleToken(token) }
            val answer = async { identity(getter, activity = { front.filterNotNull().first() }).googleIdToken("n-1") }
            advanceTimeBy(CredentialManagerIdentity.RESUME_WAIT - 1.milliseconds)
            runCurrent()
            assertTrue("Google was asked while ShellX was in the background", getter.requests.isEmpty())
            front.value = activity
            assertEquals(token, answer.await())
            assertSame(activity, getter.hosts.single())
        }
    }

    @Test
    fun shellXAwayForLongerThanTheWaitEndsAsIfTheSheetWereClosed() {
        runTest {
            val getter = FakeGetter { googleToken(jwt("id-token-1")) }
            val start = currentTime
            assertFails(IdentityProviderException.Cancelled::class.java, identity(getter, activity = { awaitCancellation() }))
            assertEquals(CredentialManagerIdentity.RESUME_WAIT.inWholeMilliseconds, currentTime - start)
            assertTrue(getter.requests.isEmpty())
        }
    }

    @Test
    fun aSignInWaitingForShellXCanBeCancelled() {
        runTest {
            val getter = FakeGetter { googleToken(jwt("id-token-1")) }
            val job = launch { identity(getter, activity = { awaitCancellation() }).googleIdToken("n-1") }
            runCurrent()
            assertFalse(job.isCompleted)
            job.cancel()
            runCurrent()
            assertTrue(job.isCancelled && job.isCompleted)
            assertTrue(getter.requests.isEmpty())
        }
    }

    @Test
    fun aSignInFromAStoppedWindowShowsGoogleOverTheWindowOnceItIsBack() {
        runTest {
            val app: Application = ApplicationProvider.getApplicationContext()
            val tracker = ActivityTracker()
            app.registerActivityLifecycleCallbacks(tracker)
            try {
                val window = Robolectric.buildActivity(ComponentActivity::class.java).setup()
                window.pause().stop()
                val token = jwt("id-token-1")
                val getter = FakeGetter { googleToken(token) }
                val answer = async { identity(getter, activity = tracker::awaitResumed).googleIdToken("n-1") }
                runCurrent()
                assertTrue(getter.requests.isEmpty())
                window.restart().resume()
                assertEquals(token, answer.await())
                assertSame(window.get(), getter.hosts.single())
            } finally {
                app.unregisterActivityLifecycleCallbacks(tracker)
            }
        }
    }

    private companion object {
        const val CLIENT = "123-abc.apps.googleusercontent.com"
    }
}
