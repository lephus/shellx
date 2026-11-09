package com.shellx.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.shellx.app.PlatformServices
import com.shellx.app.SignedInScope
import com.shellx.app.platform.NotificationPermission
import com.shellx.app.ui.composer.LocalAttachmentReader
import com.shellx.app.voice.LocalVoice
import com.shellx.app.voice.VoiceEnvironment
import com.shellx.core.platform.KeyValueStore
import com.shellx.core.push.PushRegistration

/**
 * What 3E's screens need from a signed-in account (the iPhone `SignedInView`'s environment and tasks), around the whole
 * NavHost ([SignedInFrame]):
 * - the account's mic ([LocalVoice]) and the attachment reader ([LocalAttachmentReader]);
 * - once a Mac exists, the push registration and the one automatic notification-permission ask (not in the demo,
 *   which has no [push]);
 * - a tap on a "needs you" alert opens the waiting requests ([openPending]) once the Macs are loaded.
 *
 * The decision center is synced by `SignedInScope.start()`, and `AppLifecycle.onStop` stops every mic when the app
 * leaves the foreground, so neither happens here (3D's 3E-fit notes 2 and 4).
 */
@Composable
fun SignedInWork(
    scope: SignedInScope,
    platform: PlatformServices,
    push: PushRegistration?,
    settings: KeyValueStore,
    openPending: () -> Unit,
    content: @Composable () -> Unit,
) {
    val hub by scope.hub.state.collectAsStateWithLifecycle()
    val machinesEmpty = hub.machines.isEmpty()

    // As the iPhone's guard `push != nil`: the demo neither registers nor asks. Once per scope, as the iPhone's task
    // belongs to each hub's SignedInView.
    key(scope) {
        PushRegistrationEffect(
            machinesEmpty = push == null || machinesEmpty,
            signedIn = { push?.signedIn() },
            askPermission = { NotificationPermission.requestOnce(platform.permissions, settings) },
        )
    }

    // A tap that started the app waits here until the Macs are loaded.
    val hasTap by platform.pushTaps.hasTap.collectAsStateWithLifecycle()
    val currentOpenPending by rememberUpdatedState(openPending)
    LaunchedEffect(hasTap, machinesEmpty) {
        if (hasTap && !machinesEmpty && platform.pushTaps.take()) currentOpenPending()
    }

    val voice = remember(scope, platform) { VoiceEnvironment(scope.voice, platform.voice.meter, scope.hub.scope) }
    CompositionLocalProvider(LocalVoice provides voice, LocalAttachmentReader provides platform.attachmentReader) {
        content()
    }
}

/** Alerts are worth asking for once a Mac can send them: [signedIn], then [askPermission], each time [machinesEmpty]
 *  turns false (iPhone `.task(id: hub.machines.isEmpty)`). */
@Composable
fun PushRegistrationEffect(machinesEmpty: Boolean, signedIn: suspend () -> Unit, askPermission: suspend () -> Unit) {
    val currentSignedIn by rememberUpdatedState(signedIn)
    val currentAsk by rememberUpdatedState(askPermission)
    LaunchedEffect(machinesEmpty) {
        if (machinesEmpty) return@LaunchedEffect
        currentSignedIn()
        currentAsk()
    }
}
