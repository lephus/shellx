package com.shellx.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.platform.CameraAccess
import com.shellx.app.ui.pairing.PairingScreenContent
import com.shellx.core.pairing.PairingFailure
import com.shellx.core.pairing.PairingModel.Step
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Every step of the pairing page (MachinesRenderTests' pairing renders). A render never holds an endless animation,
 * so the waiting step's spinner is a still, determinate one here.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
class PairingRenderTest {
    private val stillSpinner: @Composable (Modifier) -> Unit = { CircularProgressIndicator(progress = { 0.7f }, modifier = it) }

    private fun render(name: String, step: Step, camera: CameraAccess = CameraAccess.UNAVAILABLE) {
        assertRenders(name) {
            PairingScreenContent(
                step,
                camera,
                scanner = { modifier, _ -> Box(modifier.background(Color.Black)) },
                spinner = stillSpinner,
            )
        }
    }

    @Test fun idleUnavailable() = render("pairing-idle-unavailable", Step.Idle)

    @Test fun idleDenied() = render("pairing-idle-denied", Step.Idle, CameraAccess.DENIED)

    @Test fun idleScanner() = render("pairing-idle-scanner", Step.Idle, CameraAccess.AUTHORIZED)

    @Test fun confirm() = render("pairing-confirm", Step.Confirm("MacBook Pro"))

    @Test fun waiting() = render("pairing-waiting", Step.WaitingForMac("MacBook Pro"))

    @Test fun paired() = render("pairing-paired", Step.Paired("MacBook Pro"))

    @Test fun failedNotShellX() = render("pairing-failed-not-shellx", Step.Failed(PairingFailure.NotShellXCode))

    @Test fun failedNeedsUpdate() = render("pairing-failed-needs-update", Step.Failed(PairingFailure.NeedsUpdate))

    @Test fun failedDamaged() = render("pairing-failed-damaged", Step.Failed(PairingFailure.DamagedCode))

    @Test fun failedDenied() = render("pairing-failed-denied", Step.Failed(PairingFailure.Denied))

    @Test fun failedExpired() = render("pairing-failed-expired", Step.Failed(PairingFailure.Expired))

    @Test fun failedOtherAccount() = render("pairing-failed-other-account", Step.Failed(PairingFailure.OtherAccount))

    @Test fun failedNetwork() = render("pairing-failed-network", Step.Failed(PairingFailure.Network))

    @Test fun failedServer() = render("pairing-failed-server", Step.Failed(PairingFailure.Server("internal")))
}
