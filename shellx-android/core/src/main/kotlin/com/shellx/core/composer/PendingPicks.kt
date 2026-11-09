package com.shellx.core.composer

import com.shellx.core.platform.rethrowIfCancelled
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * The photos and files picked for the composer that are still being read (PendingPicks.swift). Each holds a place in
 * the composer's row from the moment the picker closes until its read ends; then `done` gets its attachment, or why it
 * could not be read. The composer holds Send while any is left, so a message goes out with every attachment the user
 * kept.
 *
 * Any pick can be cancelled (its ✕): its place goes at once and its read is cancelled. Whatever that read returns
 * afterwards is dropped, so a read that never ends costs one tap, never the whole composer.
 *
 * Reads run one at a time in [scope], in the order picked, so the attachments arrive in that order and a name made from
 * what the composer already holds (`photo-2.jpg` after `photo-1.jpg`) stays unique. Main-confined.
 */
class PendingPicks(private val scope: CoroutineScope) {
    private class Pick(val load: suspend () -> OutgoingAttachment, val done: (Result<OutgoingAttachment>) -> Unit) {
        var job: Job? = null
    }

    private val picks = HashMap<String, Pick>()
    private val _ids = MutableStateFlow<List<String>>(emptyList())

    /** The picks still being read, in the order picked: the first one is being read now. Ids are UUID strings. */
    val ids: StateFlow<List<String>> = _ids.asStateFlow()

    val count: Int get() = ids.value.size

    /** Reads [loads] after the picks already waiting, one at a time and in order, handing each result to [done].
     *  Returns the picks' ids, in the same order, for [cancel]. */
    fun read(loads: List<suspend () -> OutgoingAttachment>, done: (Result<OutgoingAttachment>) -> Unit): List<String> {
        val added = loads.map { load -> UUID.randomUUID().toString().also { picks[it] = Pick(load, done) } }
        _ids.value = _ids.value + added
        startNext()
        return added
    }

    /** Drops pick [id] now: it leaves [ids], its read is cancelled, and `done` never hears of it. The next pick starts
     *  if this one was being read. Nothing happens for an id no longer here. */
    fun cancel(id: String) {
        val pick = picks.remove(id) ?: return
        _ids.value = _ids.value - id
        pick.job?.cancel()
        startNext()
    }

    /** Starts reading the first pick, unless it already runs. */
    private fun startNext() {
        val id = ids.value.firstOrNull() ?: return
        val pick = picks[id] ?: return
        if (pick.job != null) return
        pick.job = scope.launch {
            val result = try {
                Result.success(pick.load())
            } catch (e: Exception) {
                // A cancelled pick (its ✕) reports nothing; a read that threw a CancellationException of its own is
                // a failure.
                rethrowIfCancelled(e)
                Result.failure(e)
            }
            finish(id, result)
        }
    }

    /** The read of pick [id] ended. A pick cancelled meanwhile is gone, and its result with it. */
    private fun finish(id: String, result: Result<OutgoingAttachment>) {
        val pick = picks.remove(id) ?: return
        _ids.value = _ids.value - id
        pick.done(result)
        startNext()
    }
}
