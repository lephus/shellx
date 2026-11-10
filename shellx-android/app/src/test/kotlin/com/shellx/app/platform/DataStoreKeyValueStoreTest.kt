package com.shellx.app.platform

import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.job
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DataStoreKeyValueStoreTest {
    @get:Rule val folder = TemporaryFolder()

    private val scopes = mutableListOf<CoroutineScope>()
    private val file: File by lazy { File(folder.root, "settings.preferences_pb") }

    private fun newScope() = CoroutineScope(SupervisorJob() + Dispatchers.IO).also { scopes += it }

    private suspend fun load(): DataStoreKeyValueStore = DataStoreKeyValueStore.load(file, newScope())

    /** Ends every store over the file, as a killed process would, and opens it again. */
    private suspend fun relaunch(): DataStoreKeyValueStore {
        for (scope in scopes) scope.coroutineContext.job.cancelAndJoin()
        scopes.clear()
        return load()
    }

    @After
    fun tearDown() {
        runBlocking { for (scope in scopes) scope.coroutineContext.job.cancelAndJoin() }
    }

    @Test
    fun valuesSurviveARelaunch() {
        runBlocking {
            val store = load()
            store.putString("a", "1")
            store.putBoolean("b", true)
            store.flush()
            val again = relaunch()
            assertEquals("1", again.getString("a"))
            assertTrue(again.getBoolean("b"))
        }
    }

    @Test
    fun readsSeeAWriteAtOnce() {
        runBlocking {
            val store = load()
            store.putString("a", "2")
            assertEquals("2", store.getString("a"))
        }
    }

    @Test
    fun writesReachTheFileInCallOrder() {
        runBlocking {
            val store = load()
            for (i in 0 until 200) store.putString("k", if (i % 7 == 0) null else "$i")
            store.flush()
            assertEquals("199", relaunch().getString("k"))
        }
    }

    @Test
    fun nullAndRemoveDeleteTheKey() {
        runBlocking {
            val store = load()
            store.putString("a", "1")
            store.putString("a", null)
            assertNull(store.getString("a"))
            store.putBoolean("b", true)
            store.remove("b")
            assertFalse(store.getBoolean("b"))
            store.flush()
            assertNull(store.getString("a"))
            assertFalse(store.getBoolean("b"))
            val again = relaunch()
            assertNull(again.getString("a"))
            assertFalse(again.getBoolean("b"))
        }
    }

    @Test
    fun aDamagedFileStartsEmpty() {
        runBlocking {
            file.writeText("not a protobuf")
            val store = load()
            assertNull(store.getString("a"))
            store.putString("a", "3")
            store.flush()
            assertEquals("3", relaunch().getString("a"))
        }
    }

    @Test
    fun aKeyKeepsItsType() {
        runBlocking {
            val store = load()
            store.putBoolean("x", true)
            assertNull(store.getString("x"))
            assertTrue(store.getBoolean("x"))
        }
    }
}
