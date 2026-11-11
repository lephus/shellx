package com.shellx.app.screenshots

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Modifier
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.shellx.app.demo.DemoBanner
import com.shellx.app.ui.onboarding.FirstMacView
import com.shellx.app.ui.signin.SignInView
import com.shellx.core.account.SignInException
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Sign-in, the first-Mac screen and the demo banner (SignInRenderTests, MachinesRenderTests, DemoRenderTests). */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
class SignInRenderTest {
    @Test
    fun signIn() {
        assertRenders("signin") { SignInView(expired = false, signIn = {}, startDemo = {}) }
    }

    @Test
    fun signInError() {
        assertRenders("signin-error") {
            SignInView(expired = false, signIn = {}, startDemo = {}, initialError = SignInException.SwitchFromSignedInDevice())
        }
    }

    @Test
    fun signInExpired() {
        assertRenders("signin-expired") { SignInView(expired = true, signIn = {}, startDemo = {}) }
    }

    /** The Pixel 3's window between its status bar and its three-button bar (393 × 713 dp). */
    @Test
    @Config(qualifiers = "w393dp-h713dp-xxhdpi")
    fun signInOnThePixel3() {
        assertRenders("signin-pixel3") { SignInView(expired = false, signIn = {}, startDemo = {}) }
    }

    @Test
    @Config(fontScale = 1.3f)
    fun signInWithLargeText() {
        assertRenders("signin-large-font") { SignInView(expired = false, signIn = {}, startDemo = {}) }
    }

    @Test
    @Config(qualifiers = "w393dp-h713dp-xxhdpi", fontScale = 1.3f)
    fun signInOnThePixel3WithLargeText() {
        assertRenders("signin-pixel3-large-font") { SignInView(expired = false, signIn = {}, startDemo = {}) }
    }

    /** A phone turned: the logo and the words beside the buttons, no steps (under 400 dp of height). */
    @Test
    @Config(qualifiers = "w785dp-h393dp-land-xxhdpi")
    fun signInInLandscape() {
        assertRenders("signin-landscape", width = 2355) { SignInView(expired = false, signIn = {}, startDemo = {}) }
    }

    @Test
    @Config(qualifiers = "w785dp-h393dp-land-xxhdpi", fontScale = 1.3f)
    fun signInInLandscapeWithLargeText() {
        assertRenders("signin-landscape-large-font", width = 2355) {
            SignInView(expired = true, signIn = {}, startDemo = {})
        }
    }

    /** A window under 600 dp tall: the small logo, and the taglines stand in for the subtitle. */
    @Test
    @Config(qualifiers = "w360dp-h592dp-xxhdpi")
    fun signInOnAShortPhone() {
        assertRenders("signin-short-phone", width = 1080) { SignInView(expired = false, signIn = {}, startDemo = {}) }
    }

    /** A tablet turned: the steps stand beside the logo, above the buttons. */
    @Test
    @Config(qualifiers = "w1280dp-h752dp-land-mdpi")
    fun signInOnATabletInLandscape() {
        assertRenders("signin-tablet-landscape", width = 1280) { SignInView(expired = false, signIn = {}, startDemo = {}) }
    }

    @Test
    fun firstMac() {
        assertRenders("first-mac") { FirstMacView(pair = {}, tryDemo = null, openSettings = {}) }
    }

    @Test
    fun firstMacDemo() {
        assertRenders("first-mac-demo") { FirstMacView(pair = {}, tryDemo = {}, openSettings = {}) }
    }

    @Test
    fun demoBanner() {
        assertRenders("demo-banner") {
            Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
                DemoBanner(exit = {})
                Spacer(Modifier.weight(1f))
            }
        }
    }
}
