package com.shellx.app

import android.content.Intent
import com.shellx.core.pairing.PairingInbox

/** The `shellx-link` intent filter's intents (contracts §5): what [MainActivity] hands to the [PairingInbox]. */
object LinkIntents {
    /** ACTION_VIEW with a shellx-link URI (the scheme compared ignoring case) → its string; anything else → null. */
    fun uri(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val data = intent.data ?: return null
        if (!data.scheme.equals(PairingInbox.SCHEME, ignoreCase = true)) return null
        return data.toString()
    }
}
