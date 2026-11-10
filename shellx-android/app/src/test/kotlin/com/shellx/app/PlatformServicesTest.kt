package com.shellx.app

import android.app.Application
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.testing.FakeAppUpdateManager
import com.shellx.app.platform.FcmPushRegistrar
import com.shellx.app.ui.composer.AttachmentPreparer
import com.shellx.app.voice.SystemVoicePermissions
import com.shellx.core.voice.FallbackTranscriber
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Plan 3E's platform pieces (contracts §5, §15), made once per process before the composition. */
@RunWith(AndroidJUnit4::class)
class PlatformServicesTest {
    private val app: Application = ApplicationProvider.getApplicationContext()

    /** Review C m-6: tests give Play's FakeAppUpdateManager, so no test binds to the Play Store. */
    private val made = mutableListOf<Context>()
    private val fakeManager: (Context) -> AppUpdateManager = { context -> FakeAppUpdateManager(context).also { made += context } }

    @Test
    fun theUpdateCheckerExistsOnlyInRelease() {
        val platform = PlatformServices(app, BuildConfig.DEBUG, fakeManager)
        assertEquals("S3 §6.1: never in debug builds", !BuildConfig.DEBUG, platform.playUpdates != null)
        assertSame(platform.playUpdates, platform.updateChecker)
    }

    @Test
    fun theUpdateManagerIsMadeOnlyInReleaseByTheGivenFactory() {
        PlatformServices(app, debugBuild = true, fakeManager)
        assertEquals("debug makes none", emptyList<Context>(), made)
        PlatformServices(app, debugBuild = false, fakeManager)
        assertEquals(listOf<Context>(app), made)
    }

    @Test
    fun theContractPiecesAreTheRealOnes() {
        val platform = PlatformServices(app, BuildConfig.DEBUG, fakeManager)
        assertTrue(platform.speechEngine is FallbackTranscriber)
        assertSame(platform.voice.engine, platform.speechEngine)
        assertTrue(platform.voicePermissions is SystemVoicePermissions)
        assertTrue(platform.pushRegistrar is FcmPushRegistrar)
        assertTrue(platform.attachmentReader is AttachmentPreparer)
    }
}
