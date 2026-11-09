package com.shellx.app.platform

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric

/** Final review F-2: Google's sheet is only ever started over a resumed window. */
@RunWith(AndroidJUnit4::class)
class ActivityTrackerTest {
    private val app: Application = ApplicationProvider.getApplicationContext()
    private val tracker = ActivityTracker()

    @Before
    fun register() = app.registerActivityLifecycleCallbacks(tracker)

    @After
    fun unregister() = app.unregisterActivityLifecycleCallbacks(tracker)

    private fun window() = Robolectric.buildActivity(ComponentActivity::class.java)

    @Test
    fun aResumedWindowAnswersAtOnce() {
        runTest {
            val window = window().setup()
            assertSame(window.get(), tracker.awaitResumed())
        }
    }

    @Test
    fun aStoppedWindowIsNotUsedUntilItIsResumedAgain() {
        runTest {
            val window = window().setup()
            window.pause().stop()
            val answer = async { tracker.awaitResumed() }
            runCurrent()
            assertFalse("a stopped window must not show Google's sheet", answer.isCompleted)
            window.restart().resume()
            assertSame(window.get(), answer.await())
        }
    }

    @Test
    fun aPausedWindowIsNotUsed() {
        runTest {
            val window = window().setup()
            window.pause()
            val answer = async { tracker.awaitResumed() }
            runCurrent()
            assertFalse(answer.isCompleted)
            window.resume()
            assertSame(window.get(), answer.await())
        }
    }

    @Test
    fun aRecreatedWindowAnswersWithTheNewOne() {
        runTest {
            val old = window().setup()
            old.pause().stop()
            val answer = async { tracker.awaitResumed() }
            runCurrent()
            assertFalse(answer.isCompleted)
            val new = window().setup()
            old.destroy()
            assertSame(new.get(), answer.await())
        }
    }

    @Test
    fun aWindowOpenedOverAnotherKeepsTheNewOne() {
        runTest {
            val under = window().setup()
            under.pause()
            val over = window().setup()
            under.stop()
            assertSame(over.get(), tracker.awaitResumed())
        }
    }

    @Test
    fun aDestroyedWindowIsNeverUsed() {
        runTest {
            val window = window().setup()
            window.pause().stop().destroy()
            val answer = async { tracker.awaitResumed() }
            runCurrent()
            assertFalse(answer.isCompleted)
            answer.cancel()
        }
    }
}
