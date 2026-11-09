package com.shellx.link.core

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertFailsWith
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

/** Ports `InMemoryCircuitTests.swift`: the in-memory pair must behave like a relay circuit, or session tests prove nothing. */
class InMemoryCircuitTest {
    @Test
    fun framesArriveInOrder() {
        runBlocking {
            within {
                val (a, b) = inMemoryCircuitPair()
                a.send(byteArrayOf(1))
                a.send(byteArrayOf(2))
                a.send(byteArrayOf(3))
                assertContentEquals(byteArrayOf(1), b.receive())
                assertContentEquals(byteArrayOf(2), b.receive())
                assertContentEquals(byteArrayOf(3), b.receive())
                // And the other way.
                b.send(byteArrayOf(4))
                assertContentEquals(byteArrayOf(4), a.receive())
            }
        }
    }

    @Test
    fun closeEndsPendingReceiveOnBothEnds() {
        runBlocking {
            within {
                val (a, b) = inMemoryCircuitPair()
                // Undispatched: each receive() is pending before close() runs.
                val waitingA = async(start = CoroutineStart.UNDISPATCHED) { assertFailsWith<RelayException.Closed> { a.receive() } }
                val waitingB = async(start = CoroutineStart.UNDISPATCHED) { assertFailsWith<RelayException.Closed> { b.receive() } }
                a.close()
                waitingA.await()
                waitingB.await()
                assertFailsWith<RelayException.Closed> { a.receive() }
                assertFailsWith<RelayException.Closed> { b.receive() }
                a.close() // idempotent
            }
        }
    }

    @Test
    fun sendAfterCloseThrows() {
        runBlocking {
            within {
                val (a, b) = inMemoryCircuitPair()
                b.close()
                assertFailsWith<RelayException.Closed> { a.send(byteArrayOf(1)) }
                assertFailsWith<RelayException.Closed> { b.send(byteArrayOf(1)) }
            }
        }
    }

    @Test
    fun framesSentBeforePeerClosedStillArrive() {
        runBlocking {
            within {
                val (a, b) = inMemoryCircuitPair()
                b.send(byteArrayOf(9)) // unread by a when a closes: dropped
                a.send(byteArrayOf(1))
                a.send(byteArrayOf(2))
                a.close()
                assertContentEquals(byteArrayOf(1), b.receive())
                assertContentEquals(byteArrayOf(2), b.receive())
                assertFailsWith<RelayException.Closed> { b.receive() }
                assertFailsWith<RelayException.Closed> { a.receive() }
            }
        }
    }

    @Test
    fun cancellingAPendingReceiveClosesTheCircuit() {
        runBlocking {
            within {
                val (a, b) = inMemoryCircuitPair()
                val waiting = launch(start = CoroutineStart.UNDISPATCHED) { a.receive() }
                waiting.cancelAndJoin()
                assertFailsWith<RelayException.Closed> { b.receive() }
                assertFailsWith<RelayException.Closed> { b.send(byteArrayOf(1)) }
            }
        }
    }
}
