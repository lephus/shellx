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
final RegExp _hostname = RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)*$');

/// Spec §14: notify when `/v1/version` offers a newer agent; §12: "Cần cập
/// nhật app" when this build is below `min_agent`. Returns null when up to
/// date, when any version is not `x.y.z` (never crash on server data), or
/// when this platform's download link is not [isTrustedDownloadUrl]: the
/// link is opened with the OS, and the relay must only be able to reduce
/// trust, never to make the agent open a file, a share or another site.
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
  if (!isTrustedDownloadUrl(url)) return null;
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

/// An absolute `https` URL on `shellx.pro` or one of its subdomains (e.g.
/// `download.shellx.pro`), without user info. The host must also be a plain
/// ASCII hostname (letters, digits and hyphens in dot-separated labels), so a
/// percent-encoded host such as `evil.com%2F.shellx.pro` — which merely ends
/// with the right characters — is rejected rather than treated as trusted.
bool isTrustedDownloadUrl(Uri url) {
  if (!url.isAbsolute || url.scheme != 'https' || url.userInfo.isNotEmpty) {
    return false;
  }
  final host = url.host.toLowerCase();
  if (!_hostname.hasMatch(host)) return false;
  return host == 'shellx.pro' || host.endsWith('.shellx.pro');
}
