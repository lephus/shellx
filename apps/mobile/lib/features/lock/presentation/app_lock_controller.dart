import 'package:flutter/foundation.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/lock/domain/biometric_authenticator.dart';

/// Spec §5.6: require unlocking when the app opens and when it comes back
/// after more than 5 minutes in the background. One instance for the app.
@lazySingleton
class AppLockController extends Controller {
  AppLockController({
    required BiometricAuthenticator authenticator,
    required bool Function() isEnabled,
    DateTime Function()? now,
    this.backgroundTimeout = const Duration(minutes: 5),
  }) : _authenticator = authenticator,
       _isEnabled = isEnabled,
       _now = now ?? DateTime.now;

  @factoryMethod
  static AppLockController create(BiometricAuthenticator authenticator, AppSettings settings) =>
      AppLockController(authenticator: authenticator, isEnabled: () => settings.biometricLock.peek());

  final BiometricAuthenticator _authenticator;
  final bool Function() _isEnabled;
  final DateTime Function() _now;
  final Duration backgroundTimeout;
  final Signal<bool> _locked = signal(false);
  final Signal<bool> _authenticating = signal(false);
  final Signal<bool> _foreground = signal(true);
  final Signal<BiometricKind> _kind = signal(BiometricKind.passcode);
  DateTime? _backgroundedAt;

  ReadonlySignal<bool> get isLocked => _locked;
  ReadonlySignal<bool> get isAuthenticating => _authenticating;

  /// V2-2b B10: the app is in the foreground — false from [onBackgrounded] to [onForegrounded]. A push's answer
  /// waits for it and for the lock, and is dropped when the app leaves it (ruling R7).
  ReadonlySignal<bool> get inForeground => _foreground;

  /// Face ID, Touch ID, fingerprint… — names the unlock button and the setting.
  ReadonlySignal<BiometricKind> get kind => _kind;

  /// Whether the biometric lock setting is on right now.
  bool get isEnabled => _isEnabled();

  Future<void> detectKind() async => _kind.value = await _authenticator.kind();

  void lockOnLaunch() {
    if (_isEnabled()) _locked.value = true;
  }

  void onBackgrounded() {
    _backgroundedAt = _now();
    _foreground.value = false;
  }

  void onForegrounded() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    // One batch, the lock first: whoever waits for "in the foreground and unlocked" (a push's answer) never sees
    // the app back in the foreground and not yet locked again.
    batch(() {
      if (since != null && _isEnabled() && _now().difference(since) > backgroundTimeout) _locked.value = true;
      _foreground.value = true;
    });
  }

  /// Prompts for Face ID / fingerprint / passcode. Unlocks without a prompt
  /// when the device cannot authenticate at all.
  ///
  /// An error from the platform (the prompt could not be shown, …) fails
  /// closed: the app stays locked and the unlock button lets the user retry.
  Future<bool> unlock(String reason) async {
    if (!_locked.peek()) return true;
    if (_authenticating.peek()) return false;
    _authenticating.value = true;
    try {
      final ok = !await _authenticator.isAvailable() || await _authenticator.authenticate(reason);
      if (ok) _locked.value = false;
      return ok;
    } catch (error) {
      if (kDebugMode) debugPrint('AppLockController.unlock failed: ${error.runtimeType}');
      return false;
    } finally {
      _authenticating.value = false;
    }
  }

  /// Call after the biometric setting changes: turning it off while locked
  /// must not leave the user stuck.
  void settingChanged() {
    if (!_isEnabled()) _locked.value = false;
  }
}
