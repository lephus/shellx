package com.shellx.core.account

/** Data this phone keeps for the signed-in account (history, caches); wiped on sign-out, account deletion, or another
 *  account's sign-in. */
fun interface LocalDataWiping {
    suspend fun wipe()
}
