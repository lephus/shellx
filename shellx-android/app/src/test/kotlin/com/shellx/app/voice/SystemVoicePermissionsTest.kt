package com.shellx.app.voice

import android.Manifest
import android.app.Application
import androidx.activity.result.contract.ActivityResultContracts
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.platform.PermissionRequester
import com.shellx.app.testing.FakeResultRegistry
import com.shellx.app.testing.TestOwner
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

@RunWith(AndroidJUnit4::class)
class SystemVoicePermissionsTest {
    private val app: Application = ApplicationProvider.getApplicationContext()
    private val registry = FakeResultRegistry()
    private val owner = TestOwner()

    private fun permissions(): SystemVoicePermissions {
        val requester = PermissionRequester(app)
        requester.attach(registry, owner)
        owner.start()
        return SystemVoicePermissions(requester)
    }

    @Test
    fun aGrantedMicrophoneAsksNothing() {
        runTest {
            shadowOf(app).grantPermissions(Manifest.permission.RECORD_AUDIO)
            val p = permissions()
            assertFalse(p.needsPrompt())
            assertTrue(p.microphone())
            assertTrue(registry.launches.isEmpty())
            assertTrue(p.speech())
        }
    }

    @Test
    fun aMissingMicrophoneIsAskedForOnce() {
        runTest {
            shadowOf(app).denyPermissions(Manifest.permission.RECORD_AUDIO)
            val p = permissions()
            assertTrue(p.needsPrompt())
            registry.answer = { false }
            assertFalse(p.microphone())
            val launch = registry.launches.single()
            assertTrue(launch.contract is ActivityResultContracts.RequestPermission)
            assertEquals(Manifest.permission.RECORD_AUDIO, launch.input)
        }
    }
}
