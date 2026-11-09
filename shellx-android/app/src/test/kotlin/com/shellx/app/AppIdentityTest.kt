package com.shellx.app

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import java.util.Properties
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AppIdentityTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun identityMatchesTheBuildType() {
        assertEquals("com.shellx.prod", context.packageName)
        if (BuildConfig.DEBUG) {
            assertEquals("ShellX Dev", context.getString(R.string.app_name))
        } else {
            assertEquals("ShellX", context.getString(R.string.app_name))
        }
    }

    @Test
    fun versionComesFromVersionProperties() {
        val version = Properties().apply { File("../version.properties").inputStream().use { load(it) } }
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        assertEquals(version.getProperty("VERSION_NAME"), info.versionName)
        assertEquals(version.getProperty("VERSION_CODE").toLong(), info.longVersionCode)
    }
}
