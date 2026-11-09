package com.shellx.app

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.shellx.app.platform.PushTapInbox
import com.shellx.app.ui.LaunchView
import com.shellx.app.ui.ShellXApp
import com.shellx.app.ui.theme.ShellXAppTheme
import com.shellx.app.ui.theme.ShellXTheme
import com.shellx.app.ui.update.UpdateAlert

/**
 * The only activity, and the launcher. It shows the launch screen until the application has built the composition,
 * then [ShellXApp] in the chosen appearance, the system bars following it (Spec note 12), with the update prompt
 * (plan 3E) at the bottom. A `shellx-link` link that opened it, or that reaches it later, goes to the pairing inbox
 * through the application, which holds it until the composition exists; a tap on a "needs you" alert goes to the push
 * taps. A recreated activity does not deliver its old intent again, and neither does one relaunched from Recents (a
 * task a link or an alert started keeps it as its base intent). The permission and update launchers are registered
 * here, before the activity starts.
 */
class MainActivity : ComponentActivity() {
    private val app: ShellXApplication get() = application as ShellXApplication

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val platform = app.platform
        platform.permissions.attach(activityResultRegistry, this)
        platform.playUpdates?.attach(activityResultRegistry, this)
        if (savedInstanceState == null && !launchedFromHistory(intent)) deliver(intent)
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
                ShellXAppTheme(appearance) {
                    Box(Modifier.fillMaxSize()) {
                        ShellXApp(c, platform = platform)
                        UpdateAlert(
                            c.updatePrompt,
                            platform.playUpdates?.installs,
                            Modifier.align(Alignment.BottomCenter).navigationBarsPadding(),
                        ) { platform.playUpdates?.completeUpdate() }
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliver(intent)
    }

    private fun deliver(intent: Intent?) {
        if (PushTapInbox.isOpenPending(intent)) app.platform.pushTaps.receive()
        LinkIntents.uri(intent)?.let(app::receiveLink)
    }

    private fun launchedFromHistory(intent: Intent?): Boolean =
        intent != null && (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0

    private companion object {
        /** `enableEdgeToEdge`'s own navigation-bar scrims (three-button navigation). */
        val LIGHT_SCRIM = Color.argb(0xe6, 0xFF, 0xFF, 0xFF)
        val DARK_SCRIM = Color.argb(0x80, 0x1b, 0x1b, 0x1b)
    }
}
