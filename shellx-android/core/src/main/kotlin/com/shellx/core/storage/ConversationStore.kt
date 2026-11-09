package com.shellx.core.storage

import com.shellx.core.account.LocalDataWiping
import com.shellx.core.platform.Clock
import com.shellx.core.platform.CoreLog
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json

/**
 * History kept on this phone as JSON files in [directory] (3D passes File(context.noBackupFilesDir, "ShellX"), so
 * nothing is backed up). A corrupt file is dropped, never fatal. Pending items and agent state are not stored here;
 * they are always fetched from the Mac.
 *
 * A thread is `threads/<sha256-hex("<machineId>\u0000<sessionId>")>.json`, replaced atomically (a temp file, then
 * Files.move(…, ATOMIC_MOVE, REPLACE_EXISTING)), with its last-modified time set to clock.nowMs(). Only the newest
 * [maxThreads] files are kept, and the file just written is never evicted.
 *
 * Writes go through a [Writer] bound to an epoch; [wipe] ends the epoch, so a write that was in flight at sign-out
 * cannot recreate the previous account's history.
 *
 * Every operation holds one Mutex and does its file work, encoding and decoding in withContext([io]), never on the
 * caller's dispatcher (S3 §4).
 */
class ConversationStore(
    private val directory: File,
    private val io: CoroutineDispatcher,
    private val clock: Clock,
    private val maxThreads: Int = 100,
) : LocalDataWiping {
    private val mutex = Mutex()
    private var epoch = 0

    /** The newest claim on each document ([writer] with a claim). */
    private val claims = HashMap<StoreDocument, Int>()

    private val threadsDirectory: File get() = File(directory, "threads")

    /** The stored document, or null when there is none or it is unreadable (an unreadable file is removed). */
    suspend fun <T> load(doc: StoreDocument, codec: JsonCodec<T>): T? = mutex.withLock {
        withContext(io) {
            val file = fileOf(doc)
            val text = try {
                file.readText()
            } catch (_: IOException) {
                return@withContext null
            }
            try {
                codec.decode(Json.parseToJsonElement(text))
            } catch (_: Exception) {
                CoreLog.log("store_corrupt kind=${doc.kind}")
                file.delete()
                null
            }
        }
    }

    /**
     * A writer bound to the store's current epoch. Obtain one when work for the signed-in account starts (a refresh, a
     * chat subscription) and keep it only for that work: once [wipe] runs, every older writer's saves are dropped.
     */
    suspend fun writer(): Writer = mutex.withLock { Writer(this, epoch, null) }

    /**
     * A writer that also claims [claiming]: once a newer writer claims the same document, this one's saves to it are
     * dropped. An agent screen takes one, so when the same session's screen is closed and opened again, a late save of
     * the old screen cannot overwrite the new one's.
     */
    suspend fun writer(claiming: StoreDocument): Writer = mutex.withLock {
        val number = (claims[claiming] ?: 0) + 1
        claims[claiming] = number
        Writer(this, epoch, Claim(claiming, number))
    }

    internal class Claim(val doc: StoreDocument, val number: Int)

    /** Saves for one epoch of the store (and, for a claiming writer, one claim). */
    class Writer internal constructor(
        private val store: ConversationStore,
        private val epoch: Int,
        private val claim: Claim?,
    ) {
        /** Replaces the stored document unless the store was wiped since this writer was made, or a newer writer
         *  claimed the document. */
        suspend fun <T> save(value: T, codec: JsonCodec<T>, doc: StoreDocument) {
            store.write(value, codec, doc, epoch, claimNumber(doc))
        }

        /** Deletes the stored document (a transcript reset drops the old copy), with the same rules as [save]. */
        suspend fun remove(doc: StoreDocument) {
            store.delete(doc, epoch, claimNumber(doc))
        }

        private fun claimNumber(doc: StoreDocument): Int? = claim?.takeIf { it.doc == doc }?.number
    }

    /** Deletes everything this store holds and invalidates every writer made before. The epoch moves even when the
     *  delete fails, so no stale writer can write afterwards; the failure is thrown. */
    override suspend fun wipe() {
        mutex.withLock {
            epoch += 1
            withContext(io) {
                if (!directory.exists()) return@withContext
                if (!directory.deleteRecursively()) {
                    CoreLog.log("store_wipe_failed")
                    throw IOException("store_wipe_failed")
                }
            }
        }
    }

    private fun current(doc: StoreDocument, writerEpoch: Int, claim: Int?, action: String): Boolean {
        if (writerEpoch != epoch) {
            CoreLog.log("store_${action}_stale kind=${doc.kind}")
            return false
        }
        if (claim != null && claims[doc] != claim) {
            CoreLog.log("store_${action}_superseded kind=${doc.kind}")
            return false
        }
        return true
    }

    private suspend fun delete(doc: StoreDocument, writerEpoch: Int, claim: Int?) {
        mutex.withLock {
            if (!current(doc, writerEpoch, claim, "remove")) return@withLock
            withContext(io) {
                try {
                    Files.deleteIfExists(fileOf(doc).toPath())
                } catch (_: IOException) {
                    CoreLog.log("store_remove_failed kind=${doc.kind}")
                }
            }
        }
    }

    private suspend fun <T> write(value: T, codec: JsonCodec<T>, doc: StoreDocument, writerEpoch: Int, claim: Int?) {
        mutex.withLock {
            if (!current(doc, writerEpoch, claim, "write")) return@withLock
            withContext(io) {
                try {
                    val text = codec.encode(value).toString()
                    val threads = threadsDirectory
                    Files.createDirectories(threads.toPath())
                    val file = fileOf(doc)
                    val temp = File.createTempFile("write-", ".tmp", threads)
                    try {
                        temp.writeText(text)
                        Files.move(temp.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
                    } finally {
                        temp.delete()
                    }
                    file.setLastModified(clock.nowMs())
                    when (doc) {
                        is StoreDocument.Thread -> evictOldThreads(keeping = file)
                    }
                } catch (_: Exception) {
                    CoreLog.log("store_write_failed kind=${doc.kind}")
                }
            }
        }
    }

    /** Keeps the [maxThreads] most recently written thread files; the file just written is never evicted, even if the
     *  clock went backwards. */
    private fun evictOldThreads(keeping: File) {
        val files = threadsDirectory.listFiles { file -> file.isFile && file.name.endsWith(".json") } ?: return
        if (files.size <= maxThreads) return
        val oldestFirst = files.filter { it.name != keeping.name }
            .map { it to it.lastModified() }
            .sortedWith(compareBy({ it.second }, { it.first.name }))
        for ((file, _) in oldestFirst.take(files.size - maxThreads)) file.delete()
    }

    private fun fileOf(doc: StoreDocument): File = when (doc) {
        is StoreDocument.Thread -> {
            val digest = MessageDigest.getInstance("SHA-256")
                .digest("${doc.ref.machineId}\u0000${doc.ref.sessionId}".encodeToByteArray())
            File(threadsDirectory, digest.joinToString("") { "%02x".format(it.toInt() and 0xFF) } + ".json")
        }
    }
}
