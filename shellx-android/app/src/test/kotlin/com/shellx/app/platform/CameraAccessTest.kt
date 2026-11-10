package com.shellx.app.platform

import android.Manifest
import android.app.Application
import android.content.pm.PackageManager
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

/** Whether the scanner can use the camera. DENIED comes only from a refused request. */
@RunWith(AndroidJUnit4::class)
class CameraAccessTest {
    private val app: Application = ApplicationProvider.getApplicationContext()

    private fun camera(present: Boolean) {
        shadowOf(app.packageManager).setSystemFeature(PackageManager.FEATURE_CAMERA_ANY, present)
    }

    @Test
    fun noCameraIsUnavailable() {
        camera(present = false)
        assertEquals(CameraAccess.UNAVAILABLE, CameraAccess.current(app))
    }

    @Test
    fun aGrantedCameraIsAuthorized() {
        camera(present = true)
        shadowOf(app).grantPermissions(Manifest.permission.CAMERA)
        assertEquals(CameraAccess.AUTHORIZED, CameraAccess.current(app))
    }

    @Test
    fun notAskedYetIsNotDetermined() {
        camera(present = true)
        assertEquals(CameraAccess.NOT_DETERMINED, CameraAccess.current(app))
    }
}
