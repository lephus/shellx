import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import '../platform/settings_store.dart';
import '../platform/wake_detector.dart';
import 'agent_runtime.dart';
import 'agent_state.dart';
import 'desktop_services.dart';
import 'storage_keys.dart';
import 'update_check.dart';

final agentControllerProvider =
    NotifierProvider<AgentController, AgentViewState>(AgentController.new);

/// Owns the signed-in lifecycle: credentials, the [AgentRuntime], settings
/// switches, update checks. The tray and the windows only call its methods.
///
/// Never awaits `StreamSubscription.cancel()`: it may return a root-zone
/// future (hangs FakeAsync tests), and the 4002 handling runs inside the
/// very relay listener it cancels.
class AgentController extends Notifier<AgentViewState> {
  late DesktopServices _s;
  AgentRuntime? _runtime;

  /// The previous runtime's stop while it is still settling (its relay may
  /// have an upgrade in flight); null otherwise. Never fails.
  Future<void>? _stopping;
  final List<StreamSubscription<Object?>> _runtimeSubscriptions = [];
  StreamSubscription<void>? _trustedSubscription;
  Timer? _updateTimer;
  WakeDetector? _wakeDetector;
  bool _updateCheckFailed = false;
  bool _revoking = false;

  /// The signed-in account, set with the stored copy by [bootstrap] and
  /// [signIn] and dropped as soon as a sign-out starts. A runtime starts
  /// only from these, synchronously, so there is never a second runtime and
  /// never one with a token that is being deleted.
  AgentCredentials? _credentials;
  NoiseKeyPair? _identity;

  TrustedStore get _trusted => _s.trusted;

  @override
  AgentViewState build() {
    _s = ref.watch(desktopServicesProvider);
    // Pairings, pairing_removed and revokes from AgentService all land in
    // the shared store.
    _trustedSubscription = _trusted.changes.listen(
      (_) => unawaited(_refreshTrusted()),
    );
    ref.onDispose(_dispose);
    return const AgentViewState();
  }

  /// Visible for tests.
  AgentRuntime? get runtime => _runtime;

  /// Loads settings and stored credentials; starts the agent when signed in
  /// and remote access is on; schedules update checks (startup + every 24 h).
  /// An unreadable secure store starts it signed out, with a notification.
  Future<void> bootstrap({bool watchForWake = true}) async {
    final settings = _s.settings;
    state = state.copyWith(
      remoteAccess: settings.getBool(
        SettingKeys.remoteAccess,
        defaultValue: true,
      ),
      keepAwake: settings.getBool(SettingKeys.keepAwake, defaultValue: true),
      launchAtStartup: settings.getBool(
        SettingKeys.launchAtStartup,
        defaultValue: true,
      ),
      onboardingDone: settings.getBool(
        SettingKeys.onboardingDone,
        defaultValue: false,
      ),
    );
    if (state.onboardingDone) {
      try {
        final enabled = await _s.launchAtLogin.isEnabled();
        if (!ref.mounted) return;
        state = state.copyWith(launchAtStartup: enabled);
      } on Exception {
        // Keep the stored value if the OS cannot be queried.
      }
    }
    ({AgentCredentials? credentials, String? email})? saved;
    try {
      saved = await _loadSavedSignIn();
    } catch (error) {
      // An unreadable keychain must not leave the app stuck loading: it
      // starts signed out (deleting nothing: it may work next time) and
      // says so, without details.
      debugPrint(
        'ShellX: reading the saved sign-in failed: ${error.runtimeType}',
      );
      _identity = null;
    }
    if (!ref.mounted) return;
    final credentials = saved?.credentials;
    if (saved == null) {
      state = state.copyWith(phase: AuthPhase.signedOut);
      await _notify(
        title: _s.l10n.notifyStorageUnreadableTitle,
        body: _s.l10n.notifySignedOutBody,
      );
    } else if (credentials == null) {
      state = state.copyWith(phase: AuthPhase.signedOut, email: saved.email);
    } else {
      await _enterSignedIn(credentials, email: saved.email);
    }
    await _applyKeepAwake();
    if (!ref.mounted) return;
    unawaited(checkForUpdate());
    _updateTimer = Timer.periodic(
      _s.updateInterval,
      (_) => unawaited(checkForUpdate()),
    );
    if (watchForWake) {
      _wakeDetector = WakeDetector(onWake: handleWake)..start();
    }
  }

  /// The stored credentials (none unless token, device id and user id are
  /// all there) and email; loads the device key when signed in. Throws when
  /// the secure store cannot be read.
  Future<({AgentCredentials? credentials, String? email})>
  _loadSavedSignIn() async {
    final store = _s.secureStore;
    final token = await store.read(DesktopStorageKeys.token);
    final deviceId = await store.read(DesktopStorageKeys.deviceId);
    final userId = await store.read(DesktopStorageKeys.userId);
    final email = await store.read(DesktopStorageKeys.email);
    if (token == null || deviceId == null || userId == null) {
      return (credentials: null, email: email);
    }
    _identity = await DeviceIdentity.loadOrCreate(store);
    return (
      credentials: AgentCredentials(
        token: token,
        deviceId: deviceId,
        userId: userId,
        email: email ?? '',
      ),
      email: email,
    );
  }

  /// Login or register (spec §5.2). Throws [ApiException] for the UI to show.
  Future<void> signIn({
    required String email,
    required String password,
    required bool register,
  }) async {
    final normalized = email.trim().toLowerCase();
    final store = _s.secureStore;
    final identity = await DeviceIdentity.loadOrCreate(store);
    final device = DeviceInfo(
      kind: DeviceKind.agent,
      name: _s.deviceName,
      platform: _s.platform,
      publicKey: identity.publicKey,
    );
    _s.api.token = null;
    final result = register
        ? await _s.api.register(normalized, password, device)
        : await _s.api.login(normalized, password, device);
    final previousUser = await store.read(DesktopStorageKeys.userId);
    if (previousUser != null && previousUser != result.userId) {
      // Spec §5.2: phones trusted under another account lose their trust.
      await _trusted.clear();
    }
    await store.write(DesktopStorageKeys.token, result.token);
    await store.write(DesktopStorageKeys.deviceId, result.deviceId);
    await store.write(DesktopStorageKeys.userId, result.userId);
    await store.write(DesktopStorageKeys.email, normalized);
    if (!ref.mounted) return;
    _identity = identity;
    await _enterSignedIn(
      AgentCredentials(
        token: result.token,
        deviceId: result.deviceId,
        userId: result.userId,
        email: normalized,
      ),
      email: normalized,
    );
    await _applyKeepAwake();
  }

  /// Spec §5.2 "Đăng xuất trên agent": close sessions, delete the token and
  /// the server-side pairings (POST /v1/auth/logout), clear the local trusted
  /// list. Keeps the device key and the email (pre-fills the login form).
  Future<void> signOut() async {
    _credentials = null;
    // The relay link goes first: once it is stopped nothing more is emitted,
    // so logging out cannot come back as a 4002 (a spurious AgentRevoked).
    await _stopRuntime();
    await Future.wait([_settlePtyKills(), _logout()]);
    await _clearSignedInData();
    if (!ref.mounted) return;
    state = state.copyWith(
      phase: AuthPhase.signedOut,
      trusted: const <TrustedDevice>[],
      signedOutNotice: false,
    );
    await _applyKeepAwake();
  }

  /// Throws [ApiException] (`weak_password`, `agent_only`, network, 429).
  /// A 401 also signs out, like a 4002.
  Future<void> changePassword(String newPassword) async {
    try {
      await _s.api.changePassword(newPassword);
    } on ApiException catch (error) {
      if (error.status == 401) await _handleRevoked();
      rethrow;
    }
  }

  /// Spec §8.3: off disconnects from the relay and closes every session
  /// (the tray asks first); remembered across restarts.
  Future<void> setRemoteAccess(bool enabled) async {
    await _s.settings.setBool(SettingKeys.remoteAccess, enabled);
    if (!ref.mounted) return;
    state = state.copyWith(remoteAccess: enabled);
    if (enabled) {
      await _startRuntime();
    } else {
      await _stopRuntime();
    }
    await _applyKeepAwake();
  }

  Future<void> setKeepAwake(bool enabled) async {
    await _s.settings.setBool(SettingKeys.keepAwake, enabled);
    if (!ref.mounted) return;
    state = state.copyWith(keepAwake: enabled);
    await _applyKeepAwake();
  }

  /// Applies the switch to the OS first; persists it only if that worked.
  Future<void> setLaunchAtStartup(bool enabled) async {
    try {
      await _s.launchAtLogin.setEnabled(enabled);
    } on Exception {
      if (ref.mounted) state = state.copyWith(launchAtStartup: !enabled);
      return;
    }
    await _s.settings.setBool(SettingKeys.launchAtStartup, enabled);
    if (!ref.mounted) return;
    state = state.copyWith(launchAtStartup: enabled);
  }

  Future<void> completeOnboarding() async {
    await setLaunchAtStartup(state.launchAtStartup);
    await _s.settings.setBool(SettingKeys.onboardingDone, true);
    if (!ref.mounted) return;
    state = state.copyWith(onboardingDone: true);
  }

  /// Null when there is no runtime (signed out or remote access off).
  PairingView? startPairing() {
    final runtime = _runtime;
    if (runtime == null) return null;
    final view = runtime.startPairing();
    state = state.copyWith(pairing: view);
    return view;
  }

  /// Closing the QR window invalidates the code (spec §5.3).
  void cancelPairing() {
    _runtime?.cancelPairing();
    state = state.copyWith(pairing: null);
  }

  /// Spec §5.5: local trust is removed first and takes effect immediately;
  /// the DELETE /v1/pairings call is best effort (the record is display-only).
  Future<void> revoke(String mobileId) async {
    final runtime = _runtime;
    if (runtime != null) {
      await runtime.revoke(mobileId);
    } else {
      await _revokeWithoutRuntime(mobileId);
    }
    await _refreshTrusted();
  }

  void closeSession(int id) => _runtime?.closeSession(id);

  void closeAllSessions() => _runtime?.closeAllSessions();

  /// Called by [WakeDetector] after the computer slept: retry now instead of
  /// after the backoff — only while `disconnected`. After a 4001 (`replaced`)
  /// spec §12 forbids reconnecting on our own; the tray's explicit
  /// "Reconnect" (Task 8) is the only way back.
  void handleWake() {
    final runtime = _runtime;
    if (runtime?.relayState == RelayConnectionState.disconnected) {
      runtime!.reconnectNow();
    }
  }

  /// Tray "Reconnect" (binding ruling, Task 8): the only way back after a
  /// 4001 (`replaced`) close, since spec §12 forbids the relay from
  /// reconnecting on its own then. A no-op without a runtime (signed out or
  /// remote access off) or outside `disconnected`/`replaced`.
  void reconnect() => _runtime?.reconnectNow();

  /// Spec §14 / §12. Never throws: a failure is retried when the relay next
  /// connects.
  Future<void> checkForUpdate() async {
    final VersionInfo info;
    try {
      info = await _s.api.version();
    } on Exception {
      _updateCheckFailed = true;
      return;
    }
    _updateCheckFailed = false;
    if (!ref.mounted) return;
    final notice = evaluateUpdate(
      info,
      appVersion: _s.appVersion,
      platform: _s.platform,
    );
    state = state.copyWith(update: notice);
    if (notice == null) return;
    final l10n = _s.l10n;
    await _notify(
      title: notice.required
          ? l10n.notifyUpdateRequiredTitle
          : l10n.notifyUpdateAvailableTitle(notice.version),
      body: notice.required
          ? l10n.notifyUpdateRequiredBody(notice.version)
          : l10n.notifyUpdateAvailableBody,
      onClick: () =>
          unawaited(_bestEffort(() => _s.urlOpener.open(notice.url))),
    );
  }

  /// Before quitting (the caller then runs `quitApp`): close sessions,
  /// disconnect, wait (bounded) for the PTY tree kills, release the sleep
  /// assertion. Never throws, so quitting always goes on.
  Future<void> shutdown() async {
    _updateTimer?.cancel();
    _updateTimer = null;
    _wakeDetector?.stop();
    _wakeDetector = null;
    await _stopRuntime();
    await _settlePtyKills();
    await _bestEffort(() => _s.keepAwake.setEnabled(false));
  }

  /// Shared tail of [bootstrap] and [signIn].
  Future<void> _enterSignedIn(
    AgentCredentials credentials, {
    required String? email,
  }) async {
    _credentials = credentials;
    _s.api.token = credentials.token;
    state = state.copyWith(
      phase: AuthPhase.signedIn,
      email: email,
      signedOutNotice: false,
    );
    await _refreshTrusted();
    await _startRuntime();
  }

  /// Starts the runtime if signed in with remote access on and none runs.
  ///
  /// First waits for a previous runtime that is still stopping: its relay
  /// may still have an upgrade in flight, which would replace (4001) a new
  /// link dialled before it settled. From the checks on, everything up to
  /// `runtime.start()` is synchronous (no await), so two callers can never
  /// both create one.
  Future<void> _startRuntime() async {
    if (_stopping != null) await _pendingStop();
    final credentials = _credentials;
    final identity = _identity;
    if (_runtime != null ||
        credentials == null ||
        identity == null ||
        !ref.mounted ||
        !state.signedIn ||
        !state.remoteAccess) {
      return;
    }
    final runtime = _s.runtimeFactory(
      RuntimeParams(
        credentials: credentials,
        identity: identity,
        trusted: _trusted,
        api: _s.api,
      ),
    );
    _runtime = runtime;
    _runtimeSubscriptions.addAll([
      runtime.relayStates.listen(_onRelayState),
      runtime.events.listen(_onAgentEvent),
      runtime.sessionChanges.listen((_) => _refreshSessions()),
    ]);
    state = state.copyWith(
      relay: runtime.relayState,
      sessions: runtime.sessions,
      activeChannels: 0,
    );
    await runtime.start();
  }

  /// Closes every session and disconnects. The runtime is detached and
  /// told to stop at once (synchronously: from then on it emits nothing,
  /// AgentRuntime.stop contract), and the state shows it stopped. The
  /// returned future completes when that stop has finished, which includes
  /// the relay's wait for an upgrade still in flight; without a runtime it
  /// is the stop still settling, if any. Never throws.
  Future<void> _stopRuntime() {
    final runtime = _runtime;
    if (runtime == null) return _stopping ?? Future<void>.value();
    _runtime = null;
    for (final subscription in _runtimeSubscriptions) {
      unawaited(subscription.cancel());
    }
    _runtimeSubscriptions.clear();
    if (ref.mounted) {
      state = state.copyWith(
        relay: RelayConnectionState.stopped,
        sessions: const <SessionSummary>[],
        activeChannels: 0,
        pairing: null,
      );
    }
    final stopping = _bestEffort(runtime.stop);
    _stopping = stopping;
    unawaited(
      stopping.whenComplete(() {
        if (identical(_stopping, stopping)) _stopping = null;
      }),
    );
    return stopping;
  }

  /// Completes once no runtime is stopping any more (also one that started
  /// stopping while this waited).
  Future<void> _pendingStop() async {
    var stopping = _stopping;
    while (stopping != null) {
      await stopping;
      final next = _stopping;
      if (identical(next, stopping)) return;
      stopping = next;
    }
  }

  /// Relay said 4002, refused the upgrade with 401, or an API call got 401
  /// (spec §5.2 as amended, §12). The agent cannot tell a password change
  /// from an account deletion, so it always: closes every session, deletes
  /// the token, KEEPS the device key, user id and trusted list, and returns
  /// to the login window. [signIn] clears the trusted list only if the next
  /// account is a different user. Never throws (runs from listeners).
  Future<void> _handleRevoked() async {
    if (_revoking || !ref.mounted || state.phase != AuthPhase.signedIn) {
      return;
    }
    _revoking = true;
    _credentials = null;
    _s.api.token = null;
    try {
      await _stopRuntime();
      // If the delete fails, the next start gets 401 and lands here again.
      await _bestEffort(() => _s.secureStore.delete(DesktopStorageKeys.token));
      if (!ref.mounted) return;
      state = state.copyWith(phase: AuthPhase.signedOut, signedOutNotice: true);
      await _applyKeepAwake();
      await _notify(
        title: _s.l10n.notifySignedOutTitle,
        body: _s.l10n.notifySignedOutBody,
      );
    } finally {
      _revoking = false;
    }
  }

  /// Remote access off, so no AgentService: the same steps as its revoke.
  /// The DELETE names this pairing, so it never removes a newer one.
  Future<void> _revokeWithoutRuntime(String mobileId) async {
    final device = await _trusted.find(mobileId);
    if (device == null) return;
    await _trusted.remove(mobileId, pairingId: device.pairingId);
    final agentId = _credentials?.deviceId;
    if (agentId == null) return;
    try {
      await _s.api.deletePairing(
        agentId,
        mobileId,
        pairingId: device.pairingId,
      );
    } on ApiException catch (error) {
      // Trust is already gone locally; the server record is cosmetic. A 401
      // means the token was revoked.
      if (error.status == 401) await _handleRevoked();
    }
  }

  Future<void> _logout() async {
    try {
      await _s.api.logout().timeout(const Duration(seconds: 10));
    } on Exception {
      // Best effort: the token is deleted locally either way.
    }
  }

  /// Deletes token, device id, user id and the trusted list. Keeps the
  /// device key (spec §5.1) and the email (pre-fills the login form).
  Future<void> _clearSignedInData() async {
    await _trusted.clear();
    final store = _s.secureStore;
    await store.delete(DesktopStorageKeys.token);
    await store.delete(DesktopStorageKeys.deviceId);
    await store.delete(DesktopStorageKeys.userId);
    _s.api.token = null;
  }

  /// Waits for PTY tree kills in flight (DesktopServices.awaitPtyKills), at
  /// most `ptyKillTimeout`. Never throws.
  Future<void> _settlePtyKills() async {
    final settled = _s.awaitPtyKills;
    if (settled == null) return;
    try {
      await settled().timeout(_s.ptyKillTimeout);
    } catch (_) {
      // Timed out or failed: go on; the kills continue in the background.
    }
  }

  void _onRelayState(RelayConnectionState relay) {
    if (!ref.mounted) return;
    state = state.copyWith(relay: relay);
    if (relay == RelayConnectionState.revoked) {
      unawaited(_handleRevoked());
    } else if (relay == RelayConnectionState.connected && _updateCheckFailed) {
      unawaited(checkForUpdate());
    }
  }

  void _onAgentEvent(AgentEvent event) {
    if (!ref.mounted) return;
    final l10n = _s.l10n;
    switch (event) {
      case MobilePaired(:final device):
        state = state.copyWith(pairing: null);
        unawaited(_refreshTrusted());
        unawaited(_notify(title: l10n.notifyPaired(device.name)));
      case SessionOpenedByMobile(:final mobileName):
        unawaited(_notify(title: l10n.notifySessionOpened(mobileName)));
      case ActiveChannelsChanged(:final count):
        state = state.copyWith(activeChannels: count);
      case AgentRevoked():
        unawaited(_handleRevoked());
    }
  }

  void _refreshSessions() {
    final runtime = _runtime;
    if (runtime == null || !ref.mounted) return;
    state = state.copyWith(sessions: runtime.sessions);
  }

  /// Never throws: an unreadable store keeps the last list on screen.
  Future<void> _refreshTrusted() async {
    final List<TrustedDevice> devices;
    try {
      devices = await _trusted.list();
    } on Exception {
      return;
    }
    if (!ref.mounted) return;
    state = state.copyWith(trusted: devices);
  }

  Future<void> _applyKeepAwake() async {
    if (!ref.mounted) return;
    final enabled = state.keepAwake && state.signedIn && state.remoteAccess;
    await _bestEffort(() => _s.keepAwake.setEnabled(enabled));
  }

  Future<void> _notify({
    required String title,
    String? body,
    void Function()? onClick,
  }) => _bestEffort(
    () => _s.notifier.show(title: title, body: body, onClick: onClick),
  );

  /// OS conveniences (sleep assertion, notifications, the browser, the
  /// keychain on the 4002 path) must never break signing in or out or
  /// quitting, and many calls run unawaited from listeners.
  static Future<void> _bestEffort(Future<void> Function() call) async {
    try {
      await call();
    } catch (_) {
      // Nothing the user could do about it here.
    }
  }

  void _dispose() {
    _updateTimer?.cancel();
    _wakeDetector?.stop();
    unawaited(_trustedSubscription?.cancel());
    for (final subscription in _runtimeSubscriptions) {
      unawaited(subscription.cancel());
    }
    _runtimeSubscriptions.clear();
    final runtime = _runtime;
    _runtime = null;
    runtime?.stop().ignore();
  }
}
