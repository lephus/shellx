package com.shellx.core.account

import com.shellx.link.account.EmailChallenge

/**
 * The relay's two email-code calls as a screen uses them: asking for a code, and what the code is for (signing in, or
 * deleting the account). Both throw [SignInException]. The sign-in screen's are `AppCoordinator.requestEmailCode` and
 * `signInWithEmailCode`; Delete Account's are `requestAccountDeletionCode` and `deleteAccountWithEmailCode`.
 */
class EmailCodeActions(
    val requestCode: suspend (email: String, locale: String) -> EmailChallenge,
    val verify: suspend (challengeId: String, code: String) -> Unit,
) {
    companion object {
        /** Both throw [SignInException.ProviderUnavailable]: a screen with no relay behind it (a render, a preview). */
        val Unavailable: EmailCodeActions = EmailCodeActions(
            requestCode = { _, _ -> throw SignInException.ProviderUnavailable() },
            verify = { _, _ -> throw SignInException.ProviderUnavailable() },
        )
    }
}
