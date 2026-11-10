package com.shellx.link.core

import com.shellx.link.core.LinkMessage as M
import com.shellx.link.core.TerminalViewPush.Ended
import com.shellx.link.core.TerminalViewPush.Opened
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.takeWhile
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

/**
 * Review A, I-3: an open whose answer arrives as its timeout fires has one outcome. Either the call returns `ok` and
 * its Opened is queued, or it times out and no Opened is queued for it. The answers straddle the timeout, so many land
 * on the edge; the check holds however the race falls, so the test cannot flake on a slow or a fast machine.
 */
class LinkClientOpenRaceTest {
    @Test
    fun noOpenedEverBelongsToAnOpenThatTimedOut() {
        runBlocking {
            within(60.seconds) {
                val rig = HostRig(
                    features = listOf(ShellXLink.TERMINAL_VIEW_FEATURE),
                    timings = LinkTimings(20.seconds, 45.seconds, requestTimeout = 30.milliseconds),
                )
                val host = async { rig.host() }
                val client = rig.client()
                val (ch, _) = host.await()
                val opens = 300
                repeat(5) { round ->
                    val end = Ended("end-$round", TerminalViewEndReason.GONE)
                    val answering = launch(Dispatchers.Default) {
                        coroutineScope {
                            repeat(opens) { i ->
                                val open = ch.request() as M.TerminalViewOpen
                                launch {
                                    delay((i % 7) * 10L)
                                    ch.send(M.TerminalViewOpenResult(open.callId, TerminalViewOpenOutcome.OK))
                                }
                            }
                        }
                        // After every answer, so the reader has handled them all when it reaches this.
                        ch.send(M.TerminalViewEnded(end.terminalId, end.reason))
                    }
                    val results = (0 until opens).map { i ->
                        async(Dispatchers.Default) {
                            val id = "r$round-t-$i"
                            id to try {
                                client.openTerminalView(id, 80, 24) == TerminalViewOpenOutcome.OK
                            } catch (_: LinkClientException.TimedOut) {
                                false
                            }
                        }
                    }.awaitAll()
                    answering.join()
                    val opened = client.terminalPushes.takeWhile { it != end }.toList().map { (it as Opened).terminalId }
                    val ok = results.filter { it.second }.map { it.first }.toSet()
                    assertEquals(emptySet(), opened.toSet() - ok, "Opened for an open that timed out, round $round")
                    assertEquals(emptySet(), ok - opened.toSet(), "ok without its Opened, round $round")
                    assertEquals(opened.size, opened.toSet().size, "an Opened twice, round $round")
                }
                client.close()
            }
        }
    }
}
