@file:OptIn(ExperimentalCoroutinesApi::class)

package com.shellx.app.platform

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.FakeResultRegistry
import com.shellx.app.testing.TestOwner
import com.shellx.app.testing.eventually
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf

@RunWith(AndroidJUnit4::class)
class PermissionRequesterTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val registry = FakeResultRegistry()
    private val owner = TestOwner()

    /** Attached while CREATED, as MainActivity.onCreate does, then in front (resumed). */
    private fun attached(): PermissionRequester = PermissionRequester(context).also {
        it.attach(registry, owner)
        owner.resume()
    }

    @Test
    fun nothingAttachedAnswersFalse() {
        runTest {
            assertFalse(PermissionRequester(context).request(Manifest.permission.RECORD_AUDIO))
            assertTrue(registry.launches.isEmpty())
        }
    }

    @Test
    fun oneLaunchAnswersEveryoneAskingTheSamePermission() {
        runTest {
            val requester = attached()
            val first = async { requester.request(Manifest.permission.RECORD_AUDIO) }
            val second = async { requester.request(Manifest.permission.RECORD_AUDIO) }
            runCurrent()
            assertEquals(listOf<Any?>(Manifest.permission.RECORD_AUDIO), registry.launches.map { it.input })
            registry.answerLast(true)
            assertTrue(first.await())
            assertTrue(second.await())
        }
    }

    @Test
    fun requestsForDifferentPermissionsRunInOrder() {
        runTest {
            val requester = attached()
            val microphone = async { requester.request(Manifest.permission.RECORD_AUDIO) }
            val notifications = async { requester.request(Manifest.permission.POST_NOTIFICATIONS) }
            runCurrent()
            assertEquals(listOf<Any?>(Manifest.permission.RECORD_AUDIO), registry.launches.map { it.input })
            registry.answerLast(false)
            runCurrent()
            assertEquals(
                listOf<Any?>(Manifest.permission.RECORD_AUDIO, Manifest.permission.POST_NOTIFICATIONS),
                registry.launches.map { it.input },
            )
            registry.answerLast(true)
            assertFalse(microphone.await())
            assertTrue(notifications.await())
        }
    }

    /** Chunk A review M-5: a prompt fired while the activity is not in front can be dropped by Android's background
     *  rules and never answered. Requests wait until it is resumed again. */
    @Test
    fun requestsWaitUntilTheActivityIsInFront() {
        runTest {
            val requester = PermissionRequester(context).also { it.attach(registry, owner) }
            owner.start()
            val microphone = async { requester.request(Manifest.permission.RECORD_AUDIO) }
            runCurrent()
            assertTrue("started, not resumed: nothing asked", registry.launches.isEmpty())
            owner.resume()
            assertEquals(listOf<Any?>(Manifest.permission.RECORD_AUDIO), registry.launches.map { it.input })
            registry.answerLast(true)
            assertTrue(microphone.await())

            owner.stop()
            val notifications = async { requester.request(Manifest.permission.POST_NOTIFICATIONS) }
            runCurrent()
            assertEquals("in the background: nothing asked", 1, registry.launches.size)
            owner.resume()
            assertEquals(Manifest.permission.POST_NOTIFICATIONS, registry.launches.last().input)
            registry.answerLast(false)
            assertFalse(notifications.await())
        }
    }

    /** A request whose every caller left before its prompt showed (the screen went away) is dropped, so it never
     *  shows later; the next one is asked in its place. */
    @Test
    fun aRequestWhoseCallersLeftBeforeItsPromptIsDropped() {
        runTest {
            val requester = PermissionRequester(context).also { it.attach(registry, owner) }
            owner.start()
            val notifications = async { requester.request(Manifest.permission.POST_NOTIFICATIONS) }
            val microphone = async { requester.request(Manifest.permission.RECORD_AUDIO) }
            runCurrent()
            notifications.cancel()
            runCurrent()
            owner.resume()
            assertEquals(listOf<Any?>(Manifest.permission.RECORD_AUDIO), registry.launches.map { it.input })
            registry.answerLast(true)
            assertTrue(microphone.await())
            assertEquals(1, registry.launches.size)
        }
    }

    /** A prompt open while the activity is recreated (rotation, dark mode) is answered through the new activity's
     *  registration, once, and is not asked again. */
    @Test
    fun aPromptOpenAcrossRecreationIsAnsweredThroughTheNewActivity() {
        val app: Application = ApplicationProvider.getApplicationContext()
        val requester = PermissionRequester(app)
        val attach = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
                (activity as? ComponentActivity)?.let { requester.attach(it.activityResultRegistry, it) }
            }

            override fun onActivityStarted(activity: Activity) {}

            override fun onActivityResumed(activity: Activity) {}

            override fun onActivityPaused(activity: Activity) {}

            override fun onActivityStopped(activity: Activity) {}

            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}

            override fun onActivityDestroyed(activity: Activity) {}
        }
        app.registerActivityLifecycleCallbacks(attach)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        try {
            val controller = Robolectric.buildActivity(ComponentActivity::class.java).setup()
            val answer = scope.async { requester.request(Manifest.permission.POST_NOTIFICATIONS) }
            val asked = shadowOf(controller.get()).lastRequestedPermission
            assertEquals(listOf(Manifest.permission.POST_NOTIFICATIONS), asked.requestedPermissions.toList())

            controller.recreate()
            assertFalse("the open prompt is not lost with the old activity", answer.isCompleted)
            assertNull("the new activity does not ask again", shadowOf(controller.get()).lastRequestedPermission)

            shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
            controller.get().onRequestPermissionsResult(
                asked.requestCode, arrayOf(Manifest.permission.POST_NOTIFICATIONS), intArrayOf(PackageManager.PERMISSION_GRANTED),
            )
            assertTrue(eventually { answer.isCompleted })
            assertTrue(answer.getCompleted())
        } finally {
            scope.cancel()
            app.unregisterActivityLifecycleCallbacks(attach)
        }
    }
}
