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
