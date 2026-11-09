package com.shellx.app.platform

import android.app.Activity
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
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.shellx.core.account.IdentityProviderException
import java.util.Base64
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric

@RunWith(AndroidJUnit4::class)
class CredentialManagerIdentityTest {
    private val activity: Activity = Robolectric.buildActivity(ComponentActivity::class.java).setup().get()

    private class FakeGetter(private val answer: () -> Credential) : CredentialGetter {
        val requests = mutableListOf<GetCredentialRequest>()

        override suspend fun get(activity: Activity, request: GetCredentialRequest): GetCredentialResponse {
            requests += request
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

    private fun identity(getter: CredentialGetter, client: String? = CLIENT, activity: () -> Activity? = { this.activity }) =
        CredentialManagerIdentity(client, activity, getter)

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
            val getter = FakeGetter { googleToken(jwt("id-token-1")) }
            assertFails(IdentityProviderException.Failed::class.java, identity(getter, activity = { null }))
            assertTrue(getter.requests.isEmpty())
        }
    }

    private companion object {
        const val CLIENT = "123-abc.apps.googleusercontent.com"
    }
}
