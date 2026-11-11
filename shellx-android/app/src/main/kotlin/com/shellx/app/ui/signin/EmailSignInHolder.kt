package com.shellx.app.ui.signin

import androidx.compose.runtime.saveable.Saver
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.shellx.core.account.EmailCodeActions
import com.shellx.core.account.EmailSignInModel
import com.shellx.core.platform.Clock

/**
 * The sign-in screen's email steps, kept across a rotation or a theme or language change: the step, the address, the
 * digits and a request on the relay all stay, and nothing is asked or sent again. [restored] is what a killed process
 * left ([EmailSignInSaver]); it is read once, when the holder is made.
 */
internal class EmailSignInHolder(actions: EmailCodeActions, clock: Clock, restored: EmailSignInModel.Saved?) : ViewModel() {
    val model = EmailSignInModel(actions, clock, viewModelScope, restored = restored)
}

/**
 * [EmailSignInModel.Saved] in the activity's saved state as `[email, challengeId or "", expiresAtMs, resendAtMs]`; null
 * stays null (nothing to come back to). The typed code is never part of it, and the challenge alone cannot sign in: it
 * needs the mailed code, and the relay allows five tries.
 */
val EmailSignInSaver: Saver<EmailSignInModel.Saved?, Any> = Saver(
    save = { saved -> saved?.let { arrayListOf<Any>(it.email, it.challengeId.orEmpty(), it.expiresAtMs, it.resendAtMs) } },
    restore = { stored ->
        val fields = stored as? List<*>
        val email = fields?.getOrNull(0) as? String
        val challengeId = fields?.getOrNull(1) as? String
        val expiresAtMs = fields?.getOrNull(2) as? Long
        val resendAtMs = fields?.getOrNull(3) as? Long
        if (email == null || challengeId == null || expiresAtMs == null || resendAtMs == null) {
            null
        } else {
            EmailSignInModel.Saved(email, challengeId.ifEmpty { null }, expiresAtMs, resendAtMs)
        }
    },
)
