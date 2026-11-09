package com.shellx.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.ui.settings.NotificationsSettingsContent
import com.shellx.app.ui.settings.OemGuide
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Settings › Notifications on, off, and with the late-notifications guide open (ledger A-1, A-28). */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
class NotificationsSettingsRenderTest {
    @Composable
    private fun Section(on: Boolean, guide: OemGuide = OemGuide.OTHER, lateOpen: Boolean = false) {
        Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
            NotificationsSettingsContent(on = on, guide = guide, turnOn = {}, openAppSettings = {}, lateOpen = lateOpen)
        }
    }

    @Test
    fun on() {
        assertRenders("settings-notifications-on") { Section(on = true) }
    }

    @Test
    fun off() {
        assertRenders("settings-notifications-off") { Section(on = false) }
    }

    @Test
    fun late() {
        assertRenders("settings-notifications-late") { Section(on = true, guide = OemGuide.OTHER, lateOpen = true) }
    }

    @Test
    fun lateXiaomi() {
        assertRenders("settings-notifications-late-xiaomi") { Section(on = true, guide = OemGuide.XIAOMI, lateOpen = true) }
    }
}
