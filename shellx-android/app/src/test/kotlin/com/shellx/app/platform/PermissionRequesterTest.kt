@file:OptIn(ExperimentalCoroutinesApi::class)

package com.shellx.app.platform

import android.Manifest
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.testing.FakeResultRegistry
import com.shellx.app.testing.TestOwner
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PermissionRequesterTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val registry = FakeResultRegistry()
    private val owner = TestOwner()

    /** Attached while CREATED, as MainActivity.onCreate does, then started. */
    private fun attached(): PermissionRequester = PermissionRequester(context).also {
        it.attach(registry, owner)
        owner.start()
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
}
