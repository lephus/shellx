package com.shellx.app

import android.app.NotificationManager
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.platform.DataStoreKeyValueStore
import com.shellx.app.platform.PushNotifier
import com.shellx.app.testing.TestShellXApplication
import com.shellx.core.platform.CoreLog
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowLog

/** The application builds the composition once the settings are read, off the main thread. */
@RunWith(AndroidJUnit4::class)
@Config(application = TestShellXApplication::class)
class ShellXApplicationTest {
    private val app: ShellXApplication = ApplicationProvider.getApplicationContext()

    @Test
    fun theCompositionIsBuiltOnceTheSettingsAreRead() {
        val deadline = System.nanoTime() + 10_000_000_000
        while (app.composition.value == null && System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(10)
        }
        val composition = app.composition.value
        assertNotNull("the composition is built within 10 s", composition)
        val environment = composition!!.environment
        assertEquals(File(app.noBackupFilesDir, "ShellX"), environment.historyDirectory)
        assertEquals(File(app.noBackupFilesDir, "ShellXDemo"), environment.demoHistoryDirectory)
        assertEquals(BuildConfig.DEBUG, environment.debugBuild)
        assertTrue(environment.settings is DataStoreKeyValueStore)
    }

    @Test
    fun coreLogGoesToLogcatOnly() {
        CoreLog.log("probe_line")

        assertTrue(ShadowLog.getLogsForTag("ShellX").any { it.msg == "probe_line" })
    }

    /** Plan 3E's pieces reach the composition by type, and the "Needs you" channel exists from the start. */
    @Test
    fun theCompositionGetsThePlatformsPieces() {
        val deadline = System.nanoTime() + 10_000_000_000
        while (app.composition.value == null && System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(10)
        }
        val composition = app.composition.value
        assertNotNull(composition)
        val platform = app.platform
        assertSame(platform.speechEngine, composition!!.speechEngine)
        assertSame(platform.voicePermissions, composition.voicePermissions)
        assertSame(platform.pushRegistrar, composition.pushRegistrar)
        assertSame(platform.updateChecker, composition.updateChecker)
        assertSame(platform.attachmentReader, composition.attachmentReader)
        assertEquals(BuildConfig.DEBUG, composition.updatePrompt == null)
        assertNotNull(app.getSystemService(NotificationManager::class.java).getNotificationChannel(PushNotifier.CHANNEL_ID))
    }
}
