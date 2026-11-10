package com.shellx.app

import android.app.Application
import android.net.ConnectivityManager
import com.shellx.app.platform.AndroidClock
import com.shellx.app.platform.CredentialManagerIdentity
import com.shellx.app.platform.DataStoreKeyValueStore
import com.shellx.app.platform.DeviceName
import com.shellx.app.platform.KeystoreSecretStore
import com.shellx.app.platform.LegacyFlutterCleanup
import com.shellx.app.platform.NetworkPathWatcher
import com.shellx.core.account.IdentityProviding
import com.shellx.core.account.SecretStore
import com.shellx.core.config.ShellXEndpoints
import com.shellx.core.link.NetworkMonitor
import com.shellx.core.platform.Clock
import com.shellx.core.platform.KeyValueStore
import java.io.File
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.withContext

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
) {
    companion object {
        /**
         * The real environment (S3 §7.3), built on Dispatchers.IO: the settings snapshot first (DataStore, in an IO scope
         * as long as the process), then the one-time Flutter clean-up, the Keystore-sealed secrets, the network watcher,
         * the clock, Google's Credential Manager, the history folders under `noBackupFilesDir`, the device name, the
         * build's facts and the relay.
         */
        suspend fun android(app: Application): AppEnvironment = withContext(Dispatchers.IO) {
            val settings = DataStoreKeyValueStore.load(
                DataStoreKeyValueStore.file(app), CoroutineScope(SupervisorJob() + Dispatchers.IO),
            )
            LegacyFlutterCleanup.run(app.dataDir, settings)
            AppEnvironment(
                secrets = KeystoreSecretStore(KeystoreSecretStore.directory(app)),
                settings = settings,
                network = NetworkPathWatcher(app.getSystemService(ConnectivityManager::class.java)),
                clock = AndroidClock,
                identity = CredentialManagerIdentity.create(app),
                io = Dispatchers.IO,
                historyDirectory = File(app.noBackupFilesDir, "ShellX"),
                demoHistoryDirectory = File(app.noBackupFilesDir, "ShellXDemo"),
                deviceName = DeviceName.current(app),
                appVersion = BuildConfig.VERSION_NAME,
                versionCode = BuildConfig.VERSION_CODE.toLong(),
                debugBuild = BuildConfig.DEBUG,
                apiBase = ShellXEndpoints.of(BuildConfig.DEBUG, BuildConfig.SHELLX_API_BASE.ifEmpty { null }).apiBase,
            )
        }
    }
}
