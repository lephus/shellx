import 'package:package_info_plus/package_info_plus.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';

/// Spec §12/§14: the app is blocked when it is older than `min_mobile` of `GET /v1/version`.
@lazySingleton
class VersionGate {
  VersionGate(this._api, PackageInfo packageInfo) : _appVersion = packageInfo.version;

  final ShellxApi _api;
  final String _appVersion;
  final Signal<String?> _requiredVersion = signal(null);

  /// `min_mobile` when this app is too old, else null.
  ReadonlySignal<String?> get requiredVersion => _requiredVersion;

  /// Runs on every launch. An unreachable relay does not block the app.
  Future<void> check() async {
    try {
      final info = await _api.version();
      _requiredVersion.value = compareVersions(_appVersion, info.minMobile) < 0 ? info.minMobile : null;
    } on ApiException {
      // Offline (network errors and timeouts included): the next launch checks again.
    } on FormatException {
      // `min_mobile` is not a version: nothing to compare against, so nothing blocks.
    }
  }
}
