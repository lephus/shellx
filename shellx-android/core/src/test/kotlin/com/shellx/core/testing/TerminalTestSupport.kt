package com.shellx.core.testing

import com.shellx.link.core.TerminalFrameAssembler
import com.shellx.link.core.TerminalScreen
import com.shellx.link.core.TerminalViewPush
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

/** Keeps every element of [flow] as it arrives, collected in [scope] (Collector in TerminalTestSupport.swift). */
class Collector<T>(flow: Flow<T>, scope: CoroutineScope) {
    private val lock = Any()
    private val kept = ArrayList<T>()

    init {
        scope.launch { flow.collect { synchronized(lock) { kept += it } } }
    }

    val items: List<T> get() = synchronized(lock) { kept.toList() }
}

/**
 * Reads [pushes] as they come, collected in [scope] (TerminalPushReader in TerminalTestSupport.swift): every push, and
 * the screen of the newest view of [terminalId] (a fresh 2A [TerminalFrameAssembler] and [TerminalScreen] at each
 * `Opened(terminalId)`; frames of other terminals are ignored).
 */
class TerminalPushReader(pushes: Flow<TerminalViewPush>, private val terminalId: String, scope: CoroutineScope) {
    private val lock = Any()
    private val received = ArrayList<TerminalViewPush>()
    private var assembler = TerminalFrameAssembler()
    private var current = TerminalScreen()

    init {
        scope.launch { pushes.collect(::take) }
    }

    val pushes: List<TerminalViewPush> get() = synchronized(lock) { received.toList() }

    /** The newest view's screen. Read it, do not change it. */
    val screen: TerminalScreen get() = synchronized(lock) { current }

    private fun take(push: TerminalViewPush) {
        synchronized(lock) {
            received += push
            when {
                push is TerminalViewPush.Opened && push.terminalId == terminalId -> {
                    assembler = TerminalFrameAssembler()
                    current = TerminalScreen()
                }
                push is TerminalViewPush.Frame && push.terminalId == terminalId ->
                    assembler.receive(push.part).frame?.let(current::apply)
                else -> Unit
            }
        }
    }
}
