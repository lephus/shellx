package com.shellx.app

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import com.shellx.app.ui.LaunchView
import com.shellx.app.ui.ShellXApp
import com.shellx.app.ui.theme.ShellXAppTheme
import com.shellx.app.ui.theme.ShellXTheme
import kotlinx.coroutines.launch

/**
 * The only activity, and the launcher. It shows the launch screen until the application has built the composition,
 * then [ShellXApp] in the chosen appearance, the system bars following it (Spec note 12). A `shellx-link` link that
 * opened it, or that reaches it later, goes to the pairing inbox. A recreated activity does not deliver its old intent
 * again, and neither does one relaunched from Recents (a task a link started keeps that link as its base intent).
 * Plan 3E adds its permission and update registrations, the notification tap and its `UpdateAlert` here
 * (3E Task 12).
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (savedInstanceState == null && !launchedFromHistory(intent)) deliver(intent)
        val app = application as ShellXApplication
        setContent {
            val built by app.composition.collectAsStateWithLifecycle()
            val c = built
            if (c == null) {
                ShellXTheme { LaunchView() }
            } else {
                val appearance by c.appearance.appearance.collectAsStateWithLifecycle()
                val dark = appearance.isDark(isSystemInDarkTheme())
                DisposableEffect(dark) {
                    enableEdgeToEdge(
                        statusBarStyle = SystemBarStyle.auto(Color.TRANSPARENT, Color.TRANSPARENT) { dark },
                        navigationBarStyle = SystemBarStyle.auto(LIGHT_SCRIM, DARK_SCRIM) { dark },
                    )
                    onDispose {}
                }
                ShellXAppTheme(appearance) { ShellXApp(c) }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliver(intent)
    }

    private fun deliver(intent: Intent?) {
        val uri = LinkIntents.uri(intent) ?: return
        lifecycleScope.launch { (application as ShellXApplication).awaitComposition().inbox.receive(uri) }
    }

    private fun launchedFromHistory(intent: Intent?): Boolean =
        intent != null && (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0

    private companion object {
        /** `enableEdgeToEdge`'s own navigation-bar scrims (three-button navigation). */
        val LIGHT_SCRIM = Color.argb(0xe6, 0xFF, 0xFF, 0xFF)
        val DARK_SCRIM = Color.argb(0x80, 0x1b, 0x1b, 0x1b)
    }
}
