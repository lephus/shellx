import 'dart:io';

/// Minimum Windows build: Windows 10 1809, the first with ConPTY (spec §3.1).
const int kMinWindowsBuild = 17763;

/// Parses the build number out of dart:io `Platform.operatingSystemVersion`
/// on Windows, e.g. `"Windows 10 Pro" 10.0 (Build 19045)`.
int? windowsBuildNumber(String operatingSystemVersion) {
  final match = RegExp(r'Build (\d+)').firstMatch(operatingSystemVersion);
  return match == null ? null : int.parse(match[1]!);
}

/// Unknown formats are allowed rather than locking the user out.
bool isSupportedWindowsBuild(String operatingSystemVersion) {
  final build = windowsBuildNumber(operatingSystemVersion);
  return build == null || build >= kMinWindowsBuild;
}

/// Device name sent to the relay (spec §5.2: the hostname), without the
/// macOS `.local` suffix, at most 64 characters.
String deviceNameFromHostname(String hostname) {
  var name = hostname.trim();
  if (name.toLowerCase().endsWith('.local')) {
    name = name.substring(0, name.length - '.local'.length);
  }
  if (name.isEmpty) return 'Computer';
  return name.length > 64 ? name.substring(0, 64) : name;
}

/// Client kind sent as `X-ShellX-Platform` (matches the relay's `audienceOf`).
String flutterPlatformName() =>
    Platform.isMacOS ? 'flutter-macos' : 'flutter-windows';

/// Normalizes dart:io `Platform.operatingSystemVersion` for the relay:
/// macOS `Version 14.5 (Build 23F79)` -> `14.5`; Windows
/// `"Windows 10 Pro" 10.0 (Build 22631)` -> `10.0.22631`. Null if unparseable.
String? normalizedOsVersion(
  String operatingSystemVersion, {
  required bool isMacOS,
}) {
  if (isMacOS) {
    return RegExp(
      r'Version (\d+\.\d+(?:\.\d+)?)',
    ).firstMatch(operatingSystemVersion)?[1];
  }
  final match = RegExp(
    r'(\d+\.\d+) \(Build (\d+)\)',
  ).firstMatch(operatingSystemVersion);
  return match == null ? null : '${match[1]}.${match[2]}';
}
