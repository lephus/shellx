package com.shellx.app.platform

import android.app.Activity
import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.GetCredentialProviderConfigurationException
import androidx.credentials.exceptions.GetCredentialUnsupportedException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException
import com.shellx.app.R
import com.shellx.core.account.IdentityProviderException
import com.shellx.core.account.IdentityProviding

/** The OAuth client of type "Web application" (contracts §16), Credential Manager's serverClientId. */
object GoogleWebClient {
    /** What res/values/google_oauth.xml holds until plan 1D fills the real ID; 3H's release script refuses it. */
    const val PLACEHOLDER = "0-shellx-placeholder.apps.googleusercontent.com"

    private val FORM = Regex("^[0-9]+-[a-z0-9]+\\.apps\\.googleusercontent\\.com$")

    /** Not the placeholder, and of the form ^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$. */
    fun isReal(id: String): Boolean = id != PLACEHOLDER && FORM.matches(id)

    /** R.string.google_web_client_id when [isReal], else null (sign-in then reads as not configured). */
    fun id(context: Context): String? = context.getString(R.string.google_web_client_id).takeIf(::isReal)
}

/** CredentialManager.getCredential, behind a seam for tests. */
fun interface CredentialGetter {
    suspend fun get(activity: Activity, request: GetCredentialRequest): GetCredentialResponse
}

object IdentityErrors {
    /**
     * GetCredentialCancellationException → Cancelled; GetCredentialProviderConfigurationException,
     * GetCredentialUnsupportedException → NotConfigured; any other GetCredentialException → Failed.
     */
    fun of(error: GetCredentialException): IdentityProviderException = when (error) {
        is GetCredentialCancellationException -> IdentityProviderException.Cancelled()
        is GetCredentialProviderConfigurationException, is GetCredentialUnsupportedException ->
            IdentityProviderException.NotConfigured()
        else -> IdentityProviderException.Failed()
    }
}

/**
 * IdentityProviding over Credential Manager (S1 §6.7): GetSignInWithGoogleOption with serverClientId = the Web client
 * (contracts §16) and setNonce(the relay's nonce). It holds no activity: [activity] is asked at each sign-in, because
 * sign-in and deletion run detached and outlive their screen (3C carry 3D-2).
 */
class CredentialManagerIdentity(
    private val serverClientId: String?,
    private val activity: () -> Activity?,
    private val getter: CredentialGetter,
) : IdentityProviding {
    override suspend fun googleIdToken(nonce: String): String {
        val client = serverClientId ?: throw IdentityProviderException.NotConfigured()
        val host = activity() ?: throw IdentityProviderException.Failed()
        val request = GetCredentialRequest.Builder()
            .addCredentialOption(GetSignInWithGoogleOption.Builder(client).setNonce(nonce).build())
            .build()
        val credential = try {
            getter.get(host, request).credential
        } catch (e: GetCredentialException) {
            throw IdentityErrors.of(e)
        }
        if (credential !is CustomCredential || credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
            throw IdentityProviderException.Failed()
        }
        return try {
            GoogleIdTokenCredential.createFrom(credential.data).idToken
        } catch (e: GoogleIdTokenParsingException) {
            throw IdentityProviderException.Failed()
        }
    }

    companion object {
        fun create(context: Context): CredentialManagerIdentity {
            val manager = CredentialManager.create(context.applicationContext)
            return CredentialManagerIdentity(GoogleWebClient.id(context), ActivityTracker::current) { activity, request ->
                manager.getCredential(activity, request)
            }
        }
    }
}
