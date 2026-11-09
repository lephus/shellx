package com.shellx.core.storage

import com.shellx.core.link.SessionRef
import com.shellx.core.platform.Clock
import java.io.File
import java.nio.file.Files
import java.nio.file.attribute.PosixFilePermissions
import java.util.Collections
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.time.TimeSource
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.putJsonArray
import org.junit.jupiter.api.io.TempDir

class ConversationStoreTest {
    private data class Doc(val items: List<String>)

    private object DocCodec : JsonCodec<Doc> {
        override fun encode(value: Doc): JsonElement = buildJsonObject {
            putJsonArray("items") { value.items.forEach { add(JsonPrimitive(it)) } }
        }

        override fun decode(json: JsonElement): Doc =
            Doc(json.jsonObject.getValue("items").jsonArray.map { it.jsonPrimitive.content })
    }

    /** A clock that advances one second per call (or walks [fixed], in seconds), so write order is deterministic. */
    private class Ticks(private val fixed: List<Double>? = null) : Clock {
        private var value = 0

        @Synchronized override fun nowMs(): Long {
            value += 1
            val seconds = fixed?.let { it[minOf(value, it.size) - 1] } ?: (1_000_000.0 + value)
            return (seconds * 1000).toLong()
        }

        override val monotonic: TimeSource.WithComparableMarks get() = TimeSource.Monotonic
    }

    @TempDir lateinit var root: File

    private val directory: File get() = File(root, "conversation-store")

    private fun ref(id: String, machine: String = "m1") = SessionRef(machine, id, "claude", "w")

    private fun TestScope.makeStore(maxThreads: Int = 100): ConversationStore =
        ConversationStore(directory, StandardTestDispatcher(testScheduler), Ticks(), maxThreads)

    /** A thread document the tests that do not care which one use. */
    private val doc: StoreDocument get() = StoreDocument.Thread(ref("s0"))

    /** The one file in the threads directory. */
    private fun onlyThreadFile(): File {
        val names = File(directory, "threads").list().orEmpty()
        assertEquals(1, names.size)
        return File(File(directory, "threads"), names.single())
    }

    @Test fun newerClaimOnADocumentDropsTheOlderWriter() { runTest {
        val store = makeStore()
        val s1 = StoreDocument.Thread(ref("s1"))
        // A screen is popped and the same session pushed again: two writers for one thread.
        val older = store.writer(claiming = s1)
        val newer = store.writer(claiming = s1)

        newer.save(Doc(listOf("new")), DocCodec, s1)
        older.save(Doc(listOf("old, written late")), DocCodec, s1)
        assertEquals(Doc(listOf("new")), store.load(s1, DocCodec), "the older screen's late save is dropped")

        // A claim on another thread changes nothing for this one.
        val other = store.writer(claiming = StoreDocument.Thread(ref("s2")))
        other.save(Doc(listOf("s2")), DocCodec, StoreDocument.Thread(ref("s2")))
        newer.save(Doc(listOf("newer")), DocCodec, s1)
        assertEquals(Doc(listOf("newer")), store.load(s1, DocCodec))

        // A wipe still ends every claimed writer.
        store.wipe()
        newer.save(Doc(listOf("after wipe")), DocCodec, s1)
        assertNull(store.load(s1, DocCodec))
    } }

    @Test fun removeDropsTheDocumentUnlessSuperseded() { runTest {
        val store = makeStore()
        val s1 = StoreDocument.Thread(ref("s1"))
        val older = store.writer(claiming = s1)
        older.save(Doc(listOf("old transcript")), DocCodec, s1)
        older.remove(s1)
        assertNull(store.load(s1, DocCodec), "a transcript reset drops the stored copy")

        // A newer screen claimed the thread: the older writer can neither write nor remove it.
        val newer = store.writer(claiming = s1)
        newer.save(Doc(listOf("new")), DocCodec, s1)
        older.remove(s1)
        assertEquals(Doc(listOf("new")), store.load(s1, DocCodec))

        // Removing what is not there is fine.
        newer.remove(StoreDocument.Thread(ref("never-written")))
    } }

    @Test fun roundTripEachDocument() { runTest {
        val store = makeStore()
        val docs = listOf(StoreDocument.Thread(ref("s0")), StoreDocument.Thread(ref("s1")), StoreDocument.Thread(ref("s2")))
        docs.forEachIndexed { index, doc -> store.writer().save(Doc(listOf("a$index")), DocCodec, doc) }
        docs.forEachIndexed { index, doc -> assertEquals(Doc(listOf("a$index")), store.load(doc, DocCodec)) }
        assertNull(store.load(StoreDocument.Thread(ref("nope")), DocCodec))
        // A thread is found by machine and session id, not by the title or agent.
        val renamed = SessionRef("m1", "s1", "codex", "other")
        assertEquals(Doc(listOf("a1")), store.load(StoreDocument.Thread(renamed), DocCodec))
        assertNull(store.load(StoreDocument.Thread(ref("s1", machine = "m2")), DocCodec))
    } }

    @Test fun fileNames() { runTest {
        val store = makeStore()
        store.writer().save(Doc(emptyList()), DocCodec, StoreDocument.Thread(ref("s1")))
        // The merged chat's `home.json` and `last-sessions.json` are not written.
        assertFalse(File(directory, "home.json").exists())
        assertFalse(File(directory, "last-sessions.json").exists())
        val thread = onlyThreadFile()
        // sha256("m1\0s1") in hex plus ".json"; no session id in the name.
        assertEquals(64 + 5, thread.name.length)
        assertFalse("s1" in thread.name)
    } }

    @Test fun corruptFileLoadsNilAndIsRemoved() { runTest {
        val store = makeStore()
        store.writer().save(Doc(listOf("x")), DocCodec, doc)
        val file = onlyThreadFile()
        file.writeText("{ not json")
        assertNull(store.load(doc, DocCodec))
        assertFalse(file.exists())
        // The store keeps working afterwards.
        store.writer().save(Doc(listOf("y")), DocCodec, doc)
        assertEquals(Doc(listOf("y")), store.load(doc, DocCodec))
    } }

    @Test fun threadsBeyondLimitEvictOldest() { runTest {
        val store = makeStore(maxThreads = 2)
        store.writer().save(Doc(listOf("1")), DocCodec, StoreDocument.Thread(ref("s1")))
        store.writer().save(Doc(listOf("2")), DocCodec, StoreDocument.Thread(ref("s2")))
        store.writer().save(Doc(listOf("1b")), DocCodec, StoreDocument.Thread(ref("s1"))) // s2 is now the oldest write
        store.writer().save(Doc(listOf("3")), DocCodec, StoreDocument.Thread(ref("s3")))
        assertEquals(Doc(listOf("1b")), store.load(StoreDocument.Thread(ref("s1")), DocCodec))
        assertNull(store.load(StoreDocument.Thread(ref("s2")), DocCodec))
        assertEquals(Doc(listOf("3")), store.load(StoreDocument.Thread(ref("s3")), DocCodec))
    } }

    @Test fun wipeRemovesEverything() { runTest {
        val store = makeStore()
        store.writer().save(Doc(listOf("a")), DocCodec, doc)
        store.writer().save(Doc(listOf("b")), DocCodec, StoreDocument.Thread(ref("s1")))
        store.wipe()
        assertNull(store.load(doc, DocCodec))
        assertNull(store.load(StoreDocument.Thread(ref("s1")), DocCodec))
        assertFalse(File(directory, "threads").exists())
        // Saving works again after a wipe.
        store.writer().save(Doc(listOf("c")), DocCodec, doc)
        assertEquals(Doc(listOf("c")), store.load(doc, DocCodec))
    } }

    @Test fun staleWriterSaveAfterWipeWritesNothing() { runTest {
        val store = makeStore()
        val stale = store.writer()
        stale.save(Doc(listOf("old")), DocCodec, doc)
        store.wipe()
        stale.save(Doc(listOf("late")), DocCodec, doc)
        stale.save(Doc(listOf("late")), DocCodec, StoreDocument.Thread(ref("s1")))
        assertFalse(directory.exists())
        assertNull(store.load(doc, DocCodec))
        // A writer made after the wipe works.
        val fresh = store.writer()
        fresh.save(Doc(listOf("new")), DocCodec, doc)
        assertEquals(Doc(listOf("new")), store.load(doc, DocCodec))
    } }

    @Test fun failedWipeThrowsButStillInvalidatesWriters() { runTest {
        // Make the delete fail: a read-only parent refuses to unlink the directory.
        val locked = File(root, "locked-${UUID.randomUUID()}")
        val inner = File(locked, "ShellX")
        val lockedStore = ConversationStore(inner, StandardTestDispatcher(testScheduler), Ticks())
        val lockedWriter = lockedStore.writer()
        lockedWriter.save(Doc(listOf("a")), DocCodec, doc)
        Files.setPosixFilePermissions(locked.toPath(), PosixFilePermissions.fromString("r-x------"))
        try {
            assertFails { lockedStore.wipe() }
            lockedWriter.save(Doc(listOf("late")), DocCodec, doc)
            Files.setPosixFilePermissions(locked.toPath(), PosixFilePermissions.fromString("rwx------"))
            // The delete emptied the directory before failing to unlink it; the stale write added nothing.
            assertNull(lockedStore.load(doc, DocCodec))
        } finally {
            Files.setPosixFilePermissions(locked.toPath(), PosixFilePermissions.fromString("rwx------"))
        }
    } }

    @Test fun backwardsClockNeverEvictsTheThreadJustSaved() { runTest {
        // Each write is older than the one before.
        val store = ConversationStore(directory, StandardTestDispatcher(testScheduler), Ticks(listOf(3_000.0, 2_000.0, 1_000.0)), 2)
        store.writer().save(Doc(listOf("1")), DocCodec, StoreDocument.Thread(ref("s1")))
        store.writer().save(Doc(listOf("2")), DocCodec, StoreDocument.Thread(ref("s2")))
        store.writer().save(Doc(listOf("3")), DocCodec, StoreDocument.Thread(ref("s3")))
        assertEquals(Doc(listOf("3")), store.load(StoreDocument.Thread(ref("s3")), DocCodec))
    } }

    /** Review Focus 3: no file work on the caller's (main) thread. */
    @Test fun fileWorkRunsOnTheIoDispatcher() {
        val executor = Executors.newSingleThreadExecutor { Thread(it, "store-io") }
        val io = executor.asCoroutineDispatcher()
        try {
            runBlocking {
                val threads = Collections.synchronizedSet(mutableSetOf<String>())
                // Under -ea, kotlinx-coroutines' debug mode appends " @coroutine#N" to the name while a coroutine runs.
                fun thread() = Thread.currentThread().name.substringBefore(" @coroutine#")
                val codec = object : JsonCodec<Doc> {
                    override fun encode(value: Doc): JsonElement = DocCodec.encode(value).also { threads += thread() }

                    override fun decode(json: JsonElement): Doc = DocCodec.decode(json).also { threads += thread() }
                }
                val store = ConversationStore(directory, io, Ticks())
                val writer = store.writer()
                writer.save(Doc(listOf("a")), codec, doc)
                assertEquals(Doc(listOf("a")), store.load(doc, codec))
                writer.remove(doc)
                store.wipe()
                assertEquals(setOf("store-io"), threads.toSet())
            }
        } finally {
            io.close()
        }
    }
}
