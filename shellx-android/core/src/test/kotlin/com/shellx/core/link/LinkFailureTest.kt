package com.shellx.core.link

import com.shellx.link.account.RelayApiException
import com.shellx.link.core.LinkClientException
import com.shellx.link.core.NoiseException
import com.shellx.link.core.RelayException
import java.io.IOException
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertEquals

class LinkFailureTest {
    @Test fun unauthorizedIsSignedOut() {
        assertEquals(LinkFailure.SIGNED_OUT, LinkFailure.of(RelayApiException.Http(401, "unauthorized")))
        assertEquals(LinkFailure.SIGNED_OUT, LinkFailure.of(RelayApiException.Http(401, "unknown")))
    }

    @Test fun notGrantedIsRevoked() {
        assertEquals(LinkFailure.REVOKED, LinkFailure.of(RelayApiException.Http(403, "not_granted")))
    }

    @Test fun machineNotFoundIsRevoked() {
        assertEquals(LinkFailure.REVOKED, LinkFailure.of(RelayApiException.Http(404, "machine_not_found")))
    }

    @Test fun untrustedPeerIsHostKeyChanged() {
        assertEquals(LinkFailure.HOST_KEY_CHANGED, LinkFailure.of(NoiseException.UntrustedPeer()))
    }

    @Test fun slotMismatchIsHostKeyChanged() {
        // The relay hands out a ticket for another slot than the one pinned at pairing: a pinning
        // failure like a changed host key, which retrying cannot fix.
        assertEquals(LinkFailure.HOST_KEY_CHANGED, LinkFailure.of(RelayApiException.SlotMismatch()))
    }

    @Test fun protocolMismatchIsNeedsUpdate() {
        assertEquals(LinkFailure.NEEDS_UPDATE, LinkFailure.of(LinkClientException.ProtocolMismatch("the host speaks protocol 2")))
    }

    @Test fun otherErrorsAreOffline() {
        val errors: List<Throwable> = listOf(
            IOException("offline"),
            IOException("offline"),
            RelayException.Closed(),
            RelayException.Server("slot-offline", true),
            LinkClientException.TimedOut(),
            LinkClientException.SessionClosed(),
            LinkClientException.Rejected("busy", "later"),
            RelayApiException.Http(500, "internal"),
            RelayApiException.Http(403, "forbidden"),
            RelayApiException.BadResponse(),
            NoiseException.DecryptFailed(),
            CancellationException(),
        )
        for (error in errors) {
            assertEquals(LinkFailure.OFFLINE, LinkFailure.of(error), "$error")
        }
    }
}
