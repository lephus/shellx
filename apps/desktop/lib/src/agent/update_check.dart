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

/// A12 D20: what "Check for updates" found. Nothing here is installed:
/// [Available] carries the download page, checked like the automatic one.
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

final class UpToDate extends UpdateCheckResult {
  const UpToDate(this.version);

  /// This build.
  final String version;
}

final class Available extends UpdateCheckResult {
  const Available(this.notice);
  final UpdateNotice notice;
}

/// The relay did not answer in time, answered nonsense, or offered a link
/// the app does not trust.
final class Failed extends UpdateCheckResult {
  const Failed();
}

/// The longest a manual check waits for the relay.
const Duration kUpdateCheckTimeout = Duration(seconds: 10);

/// One check, never throwing: [fetch] is `GET /v1/version`.
Future<UpdateCheckResult> runUpdateCheck(
  Future<VersionInfo> Function() fetch, {
  required String appVersion,
  required DevicePlatform platform,
}) async {
  final VersionInfo info;
  try {
    info = await fetch().timeout(kUpdateCheckTimeout);
  } on Object {
    return const Failed();
  }
  if (![
    appVersion,
    info.minAgent,
    info.latestAgent.version,
  ].every(_semver.hasMatch)) {
    return const Failed();
  }
  final notice = evaluateUpdate(
    info,
    appVersion: appVersion,
    platform: platform,
  );
  if (notice != null) return Available(notice);
  // No notice: up to date, or a newer version whose link is not trusted.
  try {
    final newer =
        compareVersions(appVersion, info.minAgent) < 0 ||
        compareVersions(info.latestAgent.version, appVersion) > 0;
    return newer ? const Failed() : UpToDate(appVersion);
  } on FormatException {
    return const Failed();
  }
}

/// For the link between the window and the background service.
Map<String, Object?> updateCheckToWire(UpdateCheckResult r) => switch (r) {
  UpToDate(:final version) => {'r': 'upToDate', 'version': version},
  Available(:final notice) => {
    'r': 'available',
    'version': notice.version,
    'url': notice.url.toString(),
    'required': notice.required,
  },
  Failed() => {'r': 'failed'},
};

/// The other side is read as strictly as the relay: anything that is not
/// exactly a result, or a link the app does not trust, is [Failed].
UpdateCheckResult updateCheckFromWire(Object? wire) {
  if (wire is! Map<Object?, Object?>) return const Failed();
  final version = wire['version'];
  switch (wire['r']) {
    case 'upToDate':
      if (version is String && _semver.hasMatch(version)) {
        return UpToDate(version);
      }
    case 'available':
      final url = wire['url'];
      final required = wire['required'];
      if (version is String &&
          _semver.hasMatch(version) &&
          url is String &&
          required is bool) {
        final uri = Uri.tryParse(url);
        if (uri != null && isTrustedDownloadUrl(uri)) {
          return Available(
            UpdateNotice(version: version, url: uri, required: required),
          );
        }
      }
  }
  return const Failed();
}
