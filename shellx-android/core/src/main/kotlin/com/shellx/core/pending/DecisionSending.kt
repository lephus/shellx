package com.shellx.core.pending

import com.shellx.core.link.PendingKey
import com.shellx.link.core.LinkDecision
import com.shellx.link.core.ReplyOutcome

/**
 * Sends one decision to the Mac of a pending item (DecisionCenter takes it, Task 16). Throws LinkCallException when
 * nothing was sent, LinkClientException when the call failed. MachineHub is the real one.
 */
fun interface DecisionSending {
    suspend fun reply(key: PendingKey, decision: LinkDecision): ReplyOutcome
}
