package com.shellx.link.core

import kotlinx.coroutines.yield

/**
 * One phone/host pair over an in-memory circuit. The host side is scripted inline by each test. [wrapClient] wraps the
 * client's end, for example in a [SuspendingSendCircuit].
 */
class HostRig(
    val features: List<String> = emptyList(),
    val timings: LinkTimings = LinkTimings.STANDARD,
    wrapClient: (RelayCircuit) -> RelayCircuit = { it },
) {
    val hostKey = NoiseStaticKey.generate()
    val clientKey = NoiseStaticKey.generate()
    private val ends = inMemoryCircuitPair()
    val clientEnd = wrapClient(ends.first)
    val hostEnd = ends.second

    /** Responder handshake only, trusting anyone: for tests that script what comes before Welcome. */
    suspend fun handshake(): SecureChannel = SecureChannel.open(hostEnd, NoiseRole.RESPONDER, hostKey) { true }

    /** [handshake], then reads Hello and answers `Welcome(1, "test-host", "Test Mac", features)`. */
    suspend fun host(): Pair<SecureChannel, LinkMessage.Hello> {
        val channel = handshake()
        val hello = channel.receive() as LinkMessage.Hello
        channel.send(LinkMessage.Welcome(1, "test-host", "Test Mac", features))
        return channel to hello
    }

    suspend fun client(): LinkClient =
        LinkClient.connect(clientEnd, clientKey, hostKey.publicKey, "test-client", "Test Phone", timings)
}

/**
 * A circuit whose `send` suspends (yields) before it forwards, as a socket with back-pressure can. The in-memory pair
 * never suspends in `send`, so without this a cancellation could never land between a frame's encryption and its send.
 */
class SuspendingSendCircuit(private val inner: RelayCircuit) : RelayCircuit by inner {
    override suspend fun send(data: ByteArray) {
        yield()
        inner.send(data)
    }
}

/** The next frame from the client that is not one of its pings. */
suspend fun SecureChannel.request(): LinkMessage {
    while (true) {
        val message = receive()
        if (message !is LinkMessage.Ping) return message
    }
}

/** Sample content shared by the session tests. */
object Samples {
    val item = PendingItem(
        "r1", PendingKind.PERMISSION, "claude", "ws-1", "Docs", toolName = "Bash", toolInputPreview = "ls",
        createdAtMs = 1_700_000_000_000, modes = listOf("once", "deny"),
    )
    val session = AgentSession("s-1", "claude", "ws-1", "Docs", title = "Fix the build", state = AgentState.WORKING)
    val entry = ChatEntry("e-1", 1, 1, ChatEntryRole.AGENT, ChatEntryKind.PROSE, "hello", tsMs = 1_700_000_000_000)
    val workspace = LinkWorkspace(
        "ws-1", "Docs", 0, directory = "~/docs", terminals = listOf(LinkTerminal("t-1", "zsh", 0, selected = true)),
    )
}
