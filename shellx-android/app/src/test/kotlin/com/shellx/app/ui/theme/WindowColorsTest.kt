package com.shellx.app.ui.theme

import android.content.Context
import androidx.compose.ui.graphics.toArgb
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.R
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** The window behind Compose (and the Android 12+ splash) has the theme's background, so nothing flashes. */
@RunWith(AndroidJUnit4::class)
class WindowColorsTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun lightWindowBackgroundIsTheShellXBackground() =
        assertEquals(ShellXColors.Light.background.toArgb(), context.getColor(R.color.shellx_background))

    @Test
    @Config(qualifiers = "night")
    fun darkWindowBackgroundIsTheShellXBackground() =
        assertEquals(ShellXColors.Dark.background.toArgb(), context.getColor(R.color.shellx_background))
}
