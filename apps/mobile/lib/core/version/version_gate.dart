import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';

/// Spec §12/§14: the app is blocked when it is older than `min_mobile` of `GET /v1/version`.
@lazySingleton
class VersionGate {
  VersionGate(this._api, PackageInfo packageInfo, {@ignoreParam DateTime Function()? now})
    : _appVersion = packageInfo.version,
      _now = now ?? DateTime.now;

  /// Launch never waits on the API's own 20 s request stages.
  static const Duration _timeout = Duration(seconds: 5);

  /// Force update (contract §5): the checks on returning to the foreground are this far apart at
  /// least.
  static const Duration recheckInterval = Duration(minutes: 10);

  final ShellxApi _api;
  final String _appVersion;
  final DateTime Function() _now;
  final Signal<String?> _requiredVersion = signal(null);
  DateTime? _checkedAt;

  /// `min_mobile` when this app is too old, else null.
  ReadonlySignal<String?> get requiredVersion => _requiredVersion;

  /// Runs on every launch (and again in the foreground, see [recheck]) and takes 5 s at most. An
  /// unreachable or slow relay does not block the app; it keeps the last answer.
  Future<void> check() async {
    _checkedAt = _now();
    try {
      final info = await _api.version().timeout(_timeout);
      _requiredVersion.value = compareVersions(_appVersion, info.minMobile) < 0 ? info.minMobile : null;
    } on ApiException {
      // Offline (network errors and timeouts included): the next check tries again.
    } on TimeoutException {
      // Too slow: the next check tries again.
    } on FormatException {
      // `min_mobile` is not a version: nothing to compare against, so nothing blocks.
    }
  }

  /// [check] on a return to the foreground, unless the last one (the launch's included) started
  /// less than [recheckInterval] ago. True when it ran.
  Future<bool> recheck() async {
    final last = _checkedAt;
    if (last != null) {
      final since = _now().difference(last);
      // A clock set back is no reason to stop checking until it catches up.
      if (!since.isNegative && since < recheckInterval) return false;
    }
    await check();
    return true;
  }
}
