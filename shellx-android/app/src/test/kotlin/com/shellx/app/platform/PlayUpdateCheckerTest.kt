package com.shellx.app.platform

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.android.play.core.appupdate.testing.FakeAppUpdateManager
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.shellx.app.platform.PlayUpdateChecker.InstallPhase.DOWNLOADED
import com.shellx.app.platform.PlayUpdateChecker.InstallPhase.DOWNLOADING
import com.shellx.app.platform.PlayUpdateChecker.InstallPhase.FAILED
import com.shellx.app.platform.PlayUpdateChecker.InstallPhase.INSTALLING
import com.shellx.app.platform.PlayUpdateChecker.InstallPhase.NONE
import com.shellx.app.testing.FakeResultRegistry
import com.shellx.app.testing.TestOwner
import com.shellx.core.update.AvailableUpdate
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** 3C's UpdateChecker over Play In-App Updates, flexible flow only (S3 §7.3), against Play's own fake. */
@RunWith(AndroidJUnit4::class)
class PlayUpdateCheckerTest {
    private val fake = FakeAppUpdateManager(ApplicationProvider.getApplicationContext())

    private fun attached() = PlayUpdateChecker(fake).also {
        val owner = TestOwner()
        it.attach(FakeResultRegistry(), owner)
        owner.start()
    }

    @Test
    fun noUpdateOffersNothing() {
        runTest {
            fake.setUpdateNotAvailable()
            assertNull(attached().check())
        }
    }

    @Test
    fun aFlexibleUpdateIsOfferedStartedDownloadedAndCompleted() {
        runTest {
            fake.setUpdateAvailable(101)
            val checker = attached()
            assertEquals(AvailableUpdate(101), checker.check())
            checker.startUpdate(AvailableUpdate(101))
            assertTrue(fake.isConfirmationDialogVisible)
            fake.userAcceptsUpdate()
            fake.downloadStarts()
            assertEquals(DOWNLOADING, checker.installs.value)
            fake.downloadCompletes()
            assertEquals(DOWNLOADED, checker.installs.value)
            assertNull("a downloaded update is not offered again", checker.check())
            assertEquals(DOWNLOADED, checker.installs.value)
            checker.completeUpdate()
            assertTrue(fake.isInstallSplashScreenVisible)
        }
    }

    @Test
    fun anImmediateOnlyUpdateIsNotOffered() {
        runTest {
            fake.setUpdateAvailable(101, AppUpdateType.IMMEDIATE)
            assertNull(attached().check())
        }
    }

    @Test
    fun withoutAnActivityStartingDoesNothing() {
        runTest {
            fake.setUpdateAvailable(101)
            val checker = PlayUpdateChecker(fake)
            checker.check()
            checker.startUpdate(AvailableUpdate(101))
            assertFalse(fake.isConfirmationDialogVisible)
        }
    }

    @Test
    fun installStatusesMapToPhases() {
        assertEquals(
            listOf(DOWNLOADING, DOWNLOADING, DOWNLOADED, INSTALLING, FAILED, NONE, NONE, NONE),
            listOf(
                InstallStatus.PENDING, InstallStatus.DOWNLOADING, InstallStatus.DOWNLOADED, InstallStatus.INSTALLING,
                InstallStatus.FAILED, InstallStatus.INSTALLED, InstallStatus.CANCELED, InstallStatus.UNKNOWN,
            ).map(PlayUpdateChecker::phase),
        )
    }
}
