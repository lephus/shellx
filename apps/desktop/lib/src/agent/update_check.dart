import 'package:shellx_core/shellx_core.dart';

final class UpdateNotice {
  const UpdateNotice({
    required this.version,
    required this.url,
    required this.required,
  });

  final String version;
  final Uri url;

  /// True when this build is older than `min_agent` ("Cần cập nhật app").
  final bool required;
}

final RegExp _semver = RegExp(r'^\d+\.\d+\.\d+$');

/// Spec §14: notify when `/v1/version` offers a newer agent; §12: "Cần cập
/// nhật app" when this build is below `min_agent`. Returns null when up to
/// date or when any version is not `x.y.z` (never crash on server data).
UpdateNotice? evaluateUpdate(
  VersionInfo info, {
  required String appVersion,
  required DevicePlatform platform,
}) {
  final latest = info.latestAgent;
  if (![appVersion, info.minAgent, latest.version].every(_semver.hasMatch)) {
    return null;
  }
  final url = platform == DevicePlatform.windows
      ? latest.winUrl
      : latest.macUrl;
  try {
    if (compareVersions(appVersion, info.minAgent) < 0) {
      return UpdateNotice(version: latest.version, url: url, required: true);
    }
    if (compareVersions(latest.version, appVersion) > 0) {
      return UpdateNotice(version: latest.version, url: url, required: false);
    }
  } on FormatException {
    // x.y.z in form but not semver: a leading zero or an oversized number.
    return null;
  }
  return null;
}
