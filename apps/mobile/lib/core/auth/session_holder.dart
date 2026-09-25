import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';

/// The signed-in account and its running backend (spec §5.2, §9.4, §12).
abstract class SessionHolder {
  ReadonlySignal<AccountSession?> get session;
  ReadonlySignal<bool> get isAuthenticated;

  /// The `shellx_core` + `shellx_client` stack of the signed-in account; null when signed out.
  ReadonlySignal<ShellxBackend?> get backend;

  /// [backend] of the signed-in account; throws [StateError] when signed out.
  ShellxBackend get requireBackend;

  /// Why the last sign-out happened; null after a successful sign-in.
  ReadonlySignal<SignOutReason?> get signOutReason;

  /// The email of the last account on this phone, to prefill the login form.
  String? get lastEmail;

  String get appVersion;

  /// Loads the saved session and starts its backend. Emits no event: the first route is guarded.
  Future<void> restore();

  /// Throws [ApiException] (e.g. `invalid_credentials`, HTTP 429).
  Future<void> login(String email, String password);

  /// Throws [ApiException] (e.g. `email_taken`, `disposable_email`).
  Future<void> register(String email, String password);

  /// Signs out even offline: the saved token is deleted first, then `POST /v1/auth/logout` is
  /// tried for at most 10 s; network and storage errors are swallowed. A call while a sign-out
  /// runs (a 4002 included) returns that sign-out.
  Future<void> logout();

  /// Throws [ApiException] (`invalid_credentials` for a wrong password) and stays signed in —
  /// unless the relay already closed the socket with 4002 (the account may be gone and only the
  /// response lost): then it signs out with [SignOutReason.revoked] before rethrowing.
  Future<void> deleteAccount(String password);

  /// Takes the connection back after close code 4001 (spec §12: never automatic).
  Future<void> reconnectReplaced();

  void onBackground();
  void onForeground();
}

@LazySingleton(as: SessionHolder)
class SessionHolderImpl implements SessionHolder {
  SessionHolderImpl({
    required ShellxApi api,
    required AuthStorage storage,
    required KeyValueStore store,
    required DeviceDescription device,
    required PackageInfo packageInfo,
    required BackendFactory backends,
    required AuthEventNotifier events,
  }) : _api = api,
       _storage = storage,
       _store = store,
       _device = device,
       _appVersion = packageInfo.version,
       _backends = backends,
       _events = events;

  final ShellxApi _api;
  final AuthStorage _storage;
  final KeyValueStore _store;
  final DeviceDescription _device;
  final String _appVersion;
  final BackendFactory _backends;
  final AuthEventNotifier _events;
  final Signal<AccountSession?> _session = signal(null);
  final Signal<ShellxBackend?> _backend = signal(null);
  final Signal<SignOutReason?> _signOutReason = signal(null);
  late final Computed<bool> _authenticated = computed(() => _session.value != null);
  StreamSubscription<RelayConnectionState>? _relaySubscription;
  String? _lastEmail;
  bool _deletingAccount = false;
  bool _suspended = false;
  Future<void>? _signingOut;

  /// Bounds the best-effort `POST /v1/auth/logout`; the saved token is already deleted by then.
  static const Duration _logoutTimeout = Duration(seconds: 10);

  @override
  ReadonlySignal<AccountSession?> get session => _session;

  @override
  ReadonlySignal<bool> get isAuthenticated => _authenticated;

  @override
  ReadonlySignal<ShellxBackend?> get backend => _backend;

  @override
  ShellxBackend get requireBackend => _backend.peek() ?? (throw StateError('Not signed in'));

  @override
  ReadonlySignal<SignOutReason?> get signOutReason => _signOutReason;

  @override
  String? get lastEmail => _lastEmail;

  @override
  String get appVersion => _appVersion;

  @override
  Future<void> restore() async {
    _lastEmail = await _storage.lastEmail();
    final saved = await _storage.load();
    if (saved == null) return;
    await _enter(saved, await DeviceIdentity.loadOrCreate(_store));
  }

  @override
  Future<void> login(String email, String password) => _authenticate(email, password, register: false);

  @override
  Future<void> register(String email, String password) => _authenticate(email, password, register: true);

  Future<void> _authenticate(String email, String password, {required bool register}) async {
    final identity = await DeviceIdentity.loadOrCreate(_store);
    final device = DeviceInfo(
      kind: DeviceKind.mobile,
      name: _device.name,
      platform: _device.platform,
      publicKey: identity.publicKey,
    );
    // Spec §5.2: trimmed and lower-cased so one account has one address.
    final normalized = email.trim().toLowerCase();
    final result = register
        ? await _api.register(normalized, password, device)
        : await _api.login(normalized, password, device);
    final session = AccountSession(
      userId: result.userId,
      deviceId: result.deviceId,
      token: result.token,
      email: normalized,
    );
    await _storage.save(session);
    await _enter(session, identity);
    _events.notifyAll(const SignedInEvent());
  }

  Future<void> _enter(AccountSession session, NoiseKeyPair identity) async {
    _api.token = session.token;
    _suspended = false;
    final backend = await _backends.create(session, identity);
    _relaySubscription = backend.relayStates.listen((state) {
      // Deleting the account closes every socket with 4002; that is not a revocation.
      if (state == RelayConnectionState.revoked && !_deletingAccount) {
        unawaited(_signOut(SignOutReason.revoked));
      }
    });
    batch(() {
      _session.value = session;
      _backend.value = backend;
      _signOutReason.value = null;
    });
  }

  Future<void> _teardown(ShellxBackend backend) async {
    // Cancelling takes effect immediately; its future only reports cleanup.
    unawaited(_relaySubscription?.cancel());
    _relaySubscription = null;
    await backend.dispose();
  }

  @override
  Future<void> logout() => _signOut(SignOutReason.loggedOut);

  /// One sign-out at a time: a second [logout], or a 4002, while one runs gets the same future, so
  /// there is one [SignedOutEvent] and one `dispose`.
  Future<void> _signOut(SignOutReason reason) =>
      _signingOut ??= _runSignOut(reason).whenComplete(() => _signingOut = null);

  /// Fail-closed: the backend stops and the saved token is deleted before the best-effort network
  /// logout, so an app killed during that request comes back signed out.
  Future<void> _runSignOut(SignOutReason reason) async {
    final session = _session.peek();
    final backend = _backend.peek();
    if (session == null || backend == null) return;
    await _teardown(backend);
    try {
      await _storage.deleteToken();
    } catch (error) {
      // Signed out in memory all the same.
      _logError('deleteToken', error);
    }
    if (reason == SignOutReason.loggedOut) {
      try {
        await _api.logout().timeout(_logoutTimeout);
      } catch (error) {
        // Offline, timed out or a platform error: the token is already deleted locally.
        _logError('logout', error);
      }
    }
    _api.token = null;
    _lastEmail = session.email;
    _cleared(reason);
  }

  /// Only the type: an error may carry request details (overview §2).
  static void _logError(String step, Object error) {
    if (kDebugMode) debugPrint('SessionHolder $step error: ${error.runtimeType}');
  }

  void _cleared(SignOutReason reason) {
    batch(() {
      _session.value = null;
      _backend.value = null;
      _signOutReason.value = reason;
    });
    _events.notifyAll(SignedOutEvent(reason));
  }

  /// Spec §5.2 (App Store 5.1.1(v)): `DELETE /v1/account` with the password,
  /// then forget the token, the device key and this user's pinned machines.
  @override
  Future<void> deleteAccount(String password) async {
    final session = _session.peek();
    final backend = _backend.peek();
    if (session == null || backend == null) return;
    _deletingAccount = true;
    try {
      await _api.deleteAccount(password);
    } catch (_) {
      _deletingAccount = false;
      // The relay may have deleted the account, and closed the socket with 4002, before the
      // response was lost; that close was ignored above, so it counts now.
      if (backend.relayState == RelayConnectionState.revoked) await _signOut(SignOutReason.revoked);
      rethrow;
    }
    try {
      await _teardown(backend);
    } finally {
      _deletingAccount = false;
    }
    try {
      await _storage.forgetAccount(session.userId);
    } catch (error) {
      // The account is gone on the relay: signed out in memory all the same.
      _logError('forgetAccount', error);
    }
    _api.token = null;
    _lastEmail = null;
    _cleared(SignOutReason.accountDeleted);
  }

  /// Restarting the same backend keeps every machine and tab (`RelayConnection.start()` is
  /// allowed after `replaced`).
  @override
  Future<void> reconnectReplaced() async {
    final backend = _backend.peek();
    if (backend == null) return;
    await backend.suspend();
    await backend.resume();
  }

  /// App went to the background: stop retrying (spec §12 "mobile thử khi ở
  /// foreground"); iOS would cut the socket anyway (spec §9.4).
  @override
  void onBackground() {
    final backend = _backend.peek();
    if (backend == null || _suspended) return;
    switch (backend.relayState) {
      case RelayConnectionState.replaced:
      case RelayConnectionState.revoked:
      case RelayConnectionState.stopped:
        return; // Never reconnect these automatically.
      case RelayConnectionState.disconnected:
      case RelayConnectionState.connecting:
      case RelayConnectionState.connected:
        _suspended = true;
        unawaited(backend.suspend());
    }
  }

  /// App back in the foreground: reconnect right away (spec §9.4, §12).
  @override
  void onForeground() {
    final backend = _backend.peek();
    if (backend == null) return;
    if (_suspended) {
      _suspended = false;
      unawaited(backend.resume());
    } else if (backend.relayState == RelayConnectionState.disconnected) {
      backend.reconnectNow();
    }
  }
}
