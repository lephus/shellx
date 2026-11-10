package com.shellx.app

import com.shellx.app.demo.DemoSession
import com.shellx.app.ui.nav.RootRoutes
import com.shellx.app.ui.nav.RootState
import com.shellx.app.ui.nav.Routes
import com.shellx.app.ui.theme.AppAppearanceStore
import com.shellx.core.account.AccountVault
import com.shellx.core.account.AppCoordinator
import com.shellx.core.account.AppPhase
import com.shellx.core.account.RelayAccountCalling
import com.shellx.core.account.RelayClientFactory
import com.shellx.core.composer.AttachmentReader
import com.shellx.core.config.ShellXEndpoints
import com.shellx.core.demo.DemoEnvironment
import com.shellx.core.diagnostics.LatencyLog
import com.shellx.core.home.EndedDismissalStore
import com.shellx.core.home.GoneRemovalStore
import com.shellx.core.link.HubState
import com.shellx.core.link.MachineHub
import com.shellx.core.link.MachineLinkConnecting
import com.shellx.core.pairing.PairingInbox
import com.shellx.core.pairing.PairingModel
import com.shellx.core.pending.DecisionCenter
import com.shellx.core.platform.Clock
import com.shellx.core.platform.CoreLog
import com.shellx.core.platform.KeyValueStore
import com.shellx.core.push.PushRegistrar
import com.shellx.core.push.PushRegistration
import com.shellx.core.storage.ConversationStore
import com.shellx.core.update.UpdateChecker
import com.shellx.core.update.UpdatePrompt
import com.shellx.core.voice.SpeechEngine
import com.shellx.core.voice.VoicePermissionChecking
import com.shellx.core.voice.VoiceService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.ExperimentalForInheritanceCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.FlowCollector
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import okhttp3.OkHttpClient

/** The relay client and the Link connector of one account, over one OkHttp client. */
class RelayBundle(val relay: RelayAccountCalling, val connector: MachineLinkConnecting) {
    companion object {
        /**
         * `RelayClientFactory.make` and `makeConnector` over [AppEnvironment.apiBase]. They throw on a base that is not
         * https or loopback http, which `ShellXEndpoints` never hands out; should one get through, the production relay
         * is used (carry 3D-7).
         */
        fun relay(environment: AppEnvironment, vault: AccountVault): RelayBundle {
            val okHttp = OkHttpClient()
            fun bundle(apiBase: String) = RelayBundle(
                RelayClientFactory.make(apiBase, environment.appVersion, okHttp),
                RelayClientFactory.makeConnector(apiBase, environment.appVersion, vault, environment.deviceName, okHttp),
            )
            return try {
                bundle(environment.apiBase)
            } catch (e: Exception) {
                CoreLog.log("relay_base_refused")
                bundle(ShellXEndpoints.PRODUCTION)
            }
        }
    }
}

/**
 * The composition root (contracts §5; `AppComposition.swift` and 3C's wiring summary): the real account's
 * [AccountGraph] and the [DemoSession], and the one root destination of the navigation host ([root]).
 *
 * Main-confined; [appScope] is supervised, `Dispatchers.Main.immediate` in the app. The five typed parameters are plan
 * 3E's implementations (contracts §15), each defaulting to a stub. Nothing is launched here: [AppLifecycle] launches
 * the account at the app's first start in front (Spec note 9).
 */
class AppComposition(
    val environment: AppEnvironment,
    val appScope: CoroutineScope,
    val speechEngine: SpeechEngine = NoSpeechEngine,
    val voicePermissions: VoicePermissionChecking = NoVoicePermissions,
    val pushRegistrar: PushRegistrar = NoPushRegistrar,
    val updateChecker: UpdateChecker? = null,
    val attachmentReader: AttachmentReader = NoAttachmentReader,
    /** 3E passes `PlatformServices::makeVoice`; null: no mic and no Settings › Voice. */
    makeVoice: ((hub: MachineHub, latency: LatencyLog, settings: KeyValueStore, clock: Clock) -> VoiceService)? = null,
    relays: (AccountVault) -> RelayBundle = { RelayBundle.relay(environment, it) },
    /** Null: `DemoEnvironment(scope, clock, demoHistoryDirectory, io)`. */
    demoEnvironment: ((CoroutineScope) -> DemoEnvironment)? = null,
) {
    val latency: LatencyLog = LatencyLog()

    /** Settings › Appearance, always over the real settings (also during the demo). */
    val appearance: AppAppearanceStore = AppAppearanceStore(environment.settings)

    /** A `shellx-link` link opened from elsewhere, held until [takeLink] can take it. */
    val inbox: PairingInbox = PairingInbox()

    // The real account's pieces, by the names plan 3E reads.
    val vault: AccountVault = AccountVault(environment.secrets, environment.io)
    val settings: KeyValueStore get() = environment.settings
    val clock: Clock get() = environment.clock

    private val bundle: RelayBundle = relays(vault)
    private val history = ConversationStore(environment.historyDirectory, environment.io, environment.clock)
    private val launch = LaunchMark(latency, environment.clock)

    /** The hub reports a refused token to the coordinator that made it (iPhone `CoordinatorReference`). */
    private var owner: AppCoordinator? = null

    private val coordinator: AppCoordinator = AppCoordinator(
        vault, bundle.relay, environment.identity, environment.deviceName, listOf(history), environment.settings, appScope,
    ) {
        MachineHub(vault, bundle.relay, bundle.connector, latency, environment.settings, appScope, environment.clock) {
            owner?.handleUnauthorized()
        }
    }.also { owner = it }

    val push: PushRegistration? = PushRegistration(bundle.relay, vault, pushRegistrar)

    /** Only in release builds with a checker (S3 §6.1: never in debug). */
    val updatePrompt: UpdatePrompt? =
        if (!environment.debugBuild && updateChecker != null) UpdatePrompt(environment.versionCode, updateChecker) else null

    val real: AccountGraph = AccountGraph(
        coordinator = coordinator,
        relay = bundle.relay,
        vault = vault,
        settings = environment.settings,
        scopes = SignedInScopes(coordinator, appScope) { hub ->
            makeScope(
                hub, bundle.relay, vault, history, latency, launch, environment.settings, environment.clock,
                makeVoice?.invoke(hub, latency, environment.settings, environment.clock),
            )
        },
        launch = launch,
        push = push,
        updatePrompt = updatePrompt,
        isDemo = false,
    )

    val demo: DemoSession = DemoSession(
        appScope = appScope,
        makeEnvironment = demoEnvironment ?: { scope ->
            DemoEnvironment(scope, environment.clock, environment.demoHistoryDirectory, environment.io)
        },
        graphOf = { env, child ->
            val demoLaunch = LaunchMark(env.latency, environment.clock).also { it.skip() }
            AccountGraph(
                coordinator = env.coordinator,
                relay = env.relay,
                vault = env.vault,
                settings = env.settings,
                scopes = SignedInScopes(env.coordinator, child) { hub ->
                    makeScope(
                        hub, env.relay, env.vault, env.history, env.latency, demoLaunch, env.settings, environment.clock,
                        makeVoice?.invoke(hub, env.latency, env.settings, environment.clock),
                    )
                },
                launch = demoLaunch,
                push = null,
                updatePrompt = null,
                isDemo = true,
            )
        },
    )

    /** The account the screens show: the demo while it runs, else the real one. Its value is always current. */
    val active: StateFlow<AccountGraph> = MappedStateFlow(demo.graph) { it ?: real }

    /** The one root destination (contracts §5): [RootRoutes.of] the active account's state; [Routes.LAUNCH] first. */
    @OptIn(ExperimentalCoroutinesApi::class)
    val root: StateFlow<String> = active
        .flatMapLatest { graph ->
            val hubState = graph.coordinator.hub.flatMapLatest { hub ->
                hub?.state?.map { HubAndState(hub, it) } ?: flowOf(null)
            }
            combine(graph.coordinator.phase, hubState, graph.scopes.current) { phase, hub, scope ->
                RootRoutes.of(
                    RootState(
                        demo = graph.isDemo,
                        phase = phase,
                        hubLoaded = hub?.state?.isLoaded == true,
                        hasMachines = hub?.state?.machines?.isNotEmpty() == true,
                        scopeReady = hub != null && scope?.hub === hub.hub,
                    ),
                )
            }
        }
        .distinctUntilChanged()
        .stateIn(appScope, SharingStarted.Eagerly, Routes.LAUNCH)

    private class HubAndState(val hub: MachineHub, val state: HubState)

    /** The process lifecycle's hook ([ShellXApplication] feeds it ON_START and ON_STOP). */
    val lifecycle: AppLifecycle = AppLifecycle(this)

    /**
     * Takes a waiting link when the active account is real, signed in, its hub loaded and its scope's sheets closed:
     * the pairing model begins with it (the confirmation step; nothing reaches the relay before Pair) and this returns
     * true. Otherwise false, and the link waits in [inbox] (Review Focus 2).
     */
    fun takeLink(): Boolean {
        val graph = active.value
        if (graph.isDemo || graph.coordinator.phase.value !is AppPhase.SignedIn) return false
        val hub = graph.coordinator.hub.value ?: return false
        if (!hub.state.value.isLoaded) return false
        val scope = graph.scopes.current.value?.takeIf { it.hub === hub } ?: return false
        val uri = inbox.take(over = scope.sheets) ?: return false
        scope.pairing.begin(uri)
        return true
    }

    companion object {
        /** One sign-in's scope over [hub] (`AppComposition.makeScope`); plan 3E's test rig builds its scope here too. */
        fun makeScope(
            hub: MachineHub,
            relay: RelayAccountCalling,
            vault: AccountVault,
            history: ConversationStore,
            latency: LatencyLog,
            launch: LaunchMark,
            settings: KeyValueStore,
            clock: Clock,
            voice: VoiceService?,
        ): SignedInScope = SignedInScope(
            hub = hub,
            decisions = DecisionCenter(hub, latency, hub.scope, clock),
            pairing = PairingModel(hub, relay, vault, hub.scope),
            history = history,
            launch = launch,
            endedDismissals = EndedDismissalStore(settings, clock),
            goneRemovals = GoneRemovalStore(settings, clock),
            clock = clock,
            latency = latency,
            voice = voice,
        )
    }
}

/** A read-only [StateFlow] of `transform(source.value)`, current without a coroutine in between. */
@OptIn(ExperimentalForInheritanceCoroutinesApi::class)
private class MappedStateFlow<T, R>(private val source: StateFlow<T>, private val transform: (T) -> R) : StateFlow<R> {
    override val value: R get() = transform(source.value)

    override val replayCache: List<R> get() = listOf(value)

    override suspend fun collect(collector: FlowCollector<R>): Nothing {
        source.map(transform).distinctUntilChanged().collect(collector)
        awaitCancellation()
    }
}
