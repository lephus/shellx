import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/notifications/domain/push_messaging.dart';
import 'package:shellx_mobile/features/notifications/presentation/notification_opener.dart';
import 'package:toastification/toastification.dart';

/// Push notifications on this phone (push spec §6), for the whole app's life:
/// - signed in with permission → the FCM token goes to the relay (again on every launch and on
///   `onTokenRefresh`; a failure waits for the next launch);
/// - the first time the machine list shows a paired machine → the system prompt, once per
///   install: a refusal is never asked again automatically (Settings offers the way back);
/// - sign-out, or notifications turned off in the system settings → this install's token is
///   deleted (the relay drops its copy too);
/// - in the foreground → an in-app banner; a tap (banner, notification, or the one that launched
///   the app) → [NotificationOpener].
///
/// Without Firebase ([PushMessaging.available] false) it does nothing at all.
@lazySingleton
class PushController {
  PushController({
    required PushMessaging messaging,
    required SessionHolder session,
    required SharedPreferences prefs,
    required NotificationOpener opener,
    required DeviceDescription device,
    required PopupHandler Function() popup,
  }) : _messaging = messaging,
       _session = session,
       _prefs = prefs,
       _opener = opener,
       _platform = device.platform == DevicePlatform.ios ? PushPlatform.ios : PushPlatform.android,
       _popup = popup;

  @factoryMethod
  static PushController create(
    PushMessaging messaging,
    SessionHolder session,
    SharedPreferences prefs,
    NotificationOpener opener,
    DeviceDescription device,
  ) => PushController(
    messaging: messaging,
    session: session,
    prefs: prefs,
    opener: opener,
    device: device,
    // Resolved when a banner shows: the popup handler needs the router's context.
    popup: () => getIt<PopupHandler>(),
  );

  /// Set once the automatic prompt was shown on this install.
  static const String askedKey = 'push_permission_asked';

  /// Set while a relay holds this install's token; cleared when the token is deleted.
  static const String registeredKey = 'push_token_registered';

  final PushMessaging _messaging;
  final SessionHolder _session;
  final SharedPreferences _prefs;
  final NotificationOpener _opener;
  final PushPlatform _platform;
  final PopupHandler Function() _popup;
  final Signal<PushPermission?> _permission = signal(null);
  final List<StreamSubscription<Object?>> _subscriptions = [];
  void Function()? _stopWatching;
  ShellxBackend? _owner;

  /// The backend whose relay has this install's token.
  ShellxBackend? _registeredFor;
  bool _asking = false;

  /// Push works on this install (Firebase configured and started).
  bool get available => _messaging.available;

  /// Null until read; Settings shows it.
  ReadonlySignal<PushPermission?> get permission => _permission;

  /// The automatic prompt was already shown on this install.
  bool get asked => _prefs.getBool(askedKey) ?? false;

  /// Once, when the app's router is up (after the first frame). Never throws.
  void start() {
    if (!available || _stopWatching != null) return;
    _subscriptions
      ..add(_messaging.foregroundMessages.listen(_showBanner, onError: _logStreamError))
      ..add(_messaging.openedMessages.listen(_open, onError: _logStreamError))
      ..add(_messaging.tokenRefreshes.listen(_onTokenRefresh, onError: _logStreamError));
    _stopWatching = _session.backend.subscribe(_onBackend);
    unawaited(_openInitial());
  }

  /// The machine list loaded [paired] paired machines.
  void onPairedMachines(int paired) {
    if (paired < 1 || !available || asked) return;
    unawaited(_ask());
  }

  /// "Bật" in Settings, before the automatic prompt ran.
  Future<void> requestFromSettings() => _ask();

  /// Settings, and the app coming back to the foreground: the user may have changed it in the
  /// system settings. A newly granted permission registers the token.
  Future<PushPermission?> refreshPermission() async {
    if (!available) return null;
    final PushPermission permission;
    try {
      permission = await _messaging.permission();
    } catch (error) {
      _log('permission', error);
      return null;
    }
    _permission.value = permission;
    final backend = _session.backend.peek();
    if (permission == PushPermission.granted) {
      if (backend != null && !identical(_registeredFor, backend)) await _register(backend);
    } else if (_prefs.getBool(registeredKey) ?? false) {
      // Turned off in the system settings: the token is invalidated, so the relay stops sending
      // notification text to it (FCM answers UNREGISTERED and the relay drops it).
      _registeredFor = null;
      await _deleteToken();
    }
    return permission;
  }

  Future<void> _ask() async {
    if (!available || _asking) return;
    _asking = true;
    try {
      await _prefs.setBool(askedKey, true);
      final permission = await _messaging.requestPermission();
      _permission.value = permission;
      final backend = _session.backend.peek();
      if (permission == PushPermission.granted && backend != null) await _register(backend);
    } catch (error) {
      _log('requestPermission', error);
    } finally {
      _asking = false;
    }
  }

  void _onBackend(ShellxBackend? backend) {
    if (identical(backend, _owner)) return;
    final previous = _owner;
    _owner = backend;
    _registeredFor = null;
    if (backend != null) {
      unawaited(refreshPermission());
    } else if (previous != null) {
      // Signed out: pushes to this install stop even if the relay did not hear the logout.
      unawaited(_deleteToken());
    }
  }

  void _onTokenRefresh(String token) {
    final backend = _session.backend.peek();
    if (backend == null || _permission.peek() != PushPermission.granted) return;
    unawaited(_register(backend, token: token));
  }

  /// Never throws: offline or a relay without push support (404) waits for the next launch.
  Future<void> _register(ShellxBackend backend, {String? token}) async {
    try {
      final value = token ?? await _messaging.token();
      if (value == null || !identical(_session.backend.peek(), backend)) return;
      await backend.registerPushToken(value, _platform);
      await _prefs.setBool(registeredKey, true);
      if (identical(_session.backend.peek(), backend)) _registeredFor = backend;
    } catch (error) {
      _log('registerPushToken', error);
    }
  }

  Future<void> _deleteToken() async {
    try {
      await _messaging.deleteToken();
      await _prefs.setBool(registeredKey, false);
    } catch (error) {
      _log('deleteToken', error);
    }
  }

  Future<void> _openInitial() async {
    try {
      final message = await _messaging.initialMessage();
      if (message != null) await _opener.open(message);
    } catch (error) {
      _log('initialMessage', error);
    }
  }

  void _open(PushMessage message) => unawaited(_opener.open(message));

  /// The system shows nothing while the app is open: the banner does (push spec §6).
  void _showBanner(PushMessage message) {
    final title = message.title ?? '';
    final body = message.body;
    if (title.isEmpty && (body == null || body.isEmpty)) return;
    try {
      _popup().showInfo(
        title: title.isEmpty ? body! : title,
        description: title.isEmpty ? null : body,
        callbacks: ToastificationCallbacks(onTap: (_) => _open(message)),
      );
    } catch (error) {
      _log('banner', error);
    }
  }

  void _logStreamError(Object error) => _log('stream', error);

  /// Only the type: never tokens or notification text.
  static void _log(String step, Object error) {
    if (kDebugMode) debugPrint('PushController $step error: ${error.runtimeType}');
  }

  @disposeMethod
  void dispose() {
    _stopWatching?.call();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _permission.dispose();
  }
}
