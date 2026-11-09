package com.shellx.app

import com.shellx.core.account.IdentityProviding
import com.shellx.core.account.SecretStore
import com.shellx.core.link.NetworkMonitor
import com.shellx.core.platform.Clock
import com.shellx.core.platform.KeyValueStore
import java.io.File
import kotlinx.coroutines.CoroutineDispatcher

/**
 * What the shell needs from Android: the platform services, the folders and the build's facts. The app makes the real
 * one ([android], S3 §7.3); tests make fakes. Not plan 3E's `PlatformServices` (Spec note 19).
 */
class AppEnvironment(
    val secrets: SecretStore,
    val settings: KeyValueStore,
    val network: NetworkMonitor,
    val clock: Clock,
    val identity: IdentityProviding,
    val io: CoroutineDispatcher,
    /** The real account's chat copies (`noBackupFilesDir/ShellX`), wiped on sign-out. */
    val historyDirectory: File,
    /** The demo's chat copies (`noBackupFilesDir/ShellXDemo`). */
    val demoHistoryDirectory: File,
    val deviceName: String,
    val appVersion: String,
    val versionCode: Long,
    val debugBuild: Boolean,
    /** The relay (`ShellXEndpoints.of(debugBuild, BuildConfig.SHELLX_API_BASE)`). */
    val apiBase: String,
)
