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
