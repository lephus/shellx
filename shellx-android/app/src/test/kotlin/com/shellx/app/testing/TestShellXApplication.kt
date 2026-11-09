package com.shellx.app.testing

import com.google.android.play.core.appupdate.testing.FakeAppUpdateManager
import com.shellx.app.BuildConfig
import com.shellx.app.PlatformServices
import com.shellx.app.ShellXApplication
import com.shellx.app.platform.FcmPushRegistrar

/**
 * The application with Play's FakeAppUpdateManager and a fake FCM ([messaging]) in its platform (review C m-6): no
 * test binds to the Play Store or reaches Firebase. Everything else is ShellXApplication's own.
 */
open class TestShellXApplication : ShellXApplication() {
    val messaging = FakeFcmMessaging()

    override fun makePlatform(): PlatformServices =
        PlatformServices(this, BuildConfig.DEBUG, { FakeAppUpdateManager(it) }, FcmPushRegistrar { messaging })
}
