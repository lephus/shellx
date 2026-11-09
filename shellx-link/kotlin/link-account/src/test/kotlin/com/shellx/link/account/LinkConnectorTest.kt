package com.shellx.link.account

import com.shellx.link.core.LinkMessage
import com.shellx.link.core.NoiseException
import com.shellx.link.core.NoiseStaticKey
import com.shellx.link.core.RelayControl
import com.shellx.link.core.RelayProtocol
import com.shellx.link.core.RelayRole
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Test

class LinkConnectorTest {
    private val hostKey = NoiseStaticKey.generate()
    private val phoneKey = NoiseStaticKey.generate()
    private val machine = PairedMachine("m1", "Mac", "slot-1", hostKey.publicKey)

    private suspend fun FakeWebSocketRelay.connect(machine: PairedMachine = this@LinkConnectorTest.machine) =
        LinkConnector.connect(machine, phoneKey, api(), "tok", clientVersion = "1.0.0", deviceName = "Pixel 9")

    @Test
    fun connectsWithThePinnedKeyOverTheMintedRelay() {
        runBlocking {
            FakeWebSocketRelay().use { relay ->
                val host = relay.startHost(hostKey)
                val client = within { relay.connect() }
                assertEquals(setOf("workspaces"), client.hostFeatures)
                assertEquals(LinkMessage.Hello("1.0.0", "Pixel 9"), within { host.await() })
                client.close()

                assertEquals("m1", relay.ticketBodies.single().text("target_machine_id"))
                assertEquals(listOf("Bearer ${stubTicket("slot-1")}", "Bearer jt-1"), relay.upgradeAuthorizations.toList())
                val connect = RelayControl.decode(relay.texts[0]) as RelayControl.Connect
                assertEquals("slot-1", connect.slot)
                assertEquals(RelayProtocol.VERSION, connect.protocol)
                assertEquals(5, connect.protocol)
                val join = RelayControl.decode(relay.texts[1]) as RelayControl.Join
                assertEquals(RelayRole.CLIENT, join.role)
                assertEquals("c-1", join.circuit)
                assertEquals("jt-1", join.ticket)
            }
        }
    }

    @Test
    fun anotherHostKeyIsUntrustedPeer() {
        runBlocking {
            FakeWebSocketRelay().use { relay ->
                relay.startHost(hostKey)
                val impostor = machine.copy(hostKey = NoiseStaticKey.generate().publicKey)
                within { assertFailsWith<NoiseException.UntrustedPeer> { relay.connect(impostor) } }
            }
        }
    }

    @Test
    fun ticketForAnotherSlotNeverOpensASocket() {
        runBlocking {
            FakeWebSocketRelay(mintedSlot = "other").use { relay ->
                within { assertFailsWith<RelayApiException.SlotMismatch> { relay.connect() } }
                assertEquals(1, relay.ticketBodies.size)
                assertEquals(0, relay.upgradeAuthorizations.size)
            }
        }
    }

    @Test
    fun revokedGrantSurfacesItsCode() {
        runBlocking {
            FakeWebSocketRelay().use { relay ->
                relay.refuseTickets = 403 to "not_granted"
                assertEquals(
                    RelayApiException.Http(403, "not_granted"),
                    within { assertFailsWith<RelayApiException.Http> { relay.connect() } },
                )
                assertEquals(0, relay.upgradeAuthorizations.size)
            }
        }
    }
}
