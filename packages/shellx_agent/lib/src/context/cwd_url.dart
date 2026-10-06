import 'dart:convert';

/// What an `OSC 7` URL says about a session's directory (A2 C1, D2).
sealed class ReportedCwd {
  const ReportedCwd();
}

/// A directory on this computer.
final class LocalCwd extends ReportedCwd {
  const LocalCwd(this.path);
  final String path;
  @override
  bool operator ==(Object other) => other is LocalCwd && other.path == path;
  @override
  int get hashCode => path.hashCode;
}

/// A directory on another host (a shell inside `ssh` that reports its own
/// directory): the session's directory and branch are forgotten rather
/// than shown wrong (D2).
final class RemoteCwd extends ReportedCwd {
  const RemoteCwd();
  @override
  bool operator ==(Object other) => other is RemoteCwd;
  @override
  int get hashCode => 7;
}

final _driveUrl = RegExp(r'^/([A-Za-z]):(/.*)?$');
final _hexDigit = RegExp(r'^[0-9A-Fa-f]$');

/// Decodes `file://<host>/<percent-encoded path>`. Null when the URL is not
/// a `file:` URL, its percent-encoding or UTF-8 is broken, or it holds a
/// NUL: the caller ignores it and keeps the directory it had.
///
/// [localHostName] is `Platform.localHostname`; a host is this computer
/// when it is empty, `localhost`, or has the same first DNS label (zsh's
/// `$HOST` is often the short name, the OS the `.local` one).
///
/// Windows: `file:///C:/x` is `C:\x`; a URL with a host that is not this
/// computer is a UNC path `\\host\share\x` (that is how PowerShell's
/// `[Uri]` writes one), never [RemoteCwd].
ReportedCwd? parseCwdUrl(
  String url, {
  required bool windows,
  required String localHostName,
}) {
  const scheme = 'file://';
  if (url.length <= scheme.length ||
      url.substring(0, scheme.length).toLowerCase() != scheme) {
    return null;
  }
  final rest = url.substring(scheme.length);
  final slash = rest.indexOf('/');
  if (slash < 0) return null;
  final host = rest.substring(0, slash);
  final path = _percentDecode(rest.substring(slash));
  if (path == null || path.contains('\u0000')) return null;
  final isLocal = _isLocalHost(host, localHostName);
  if (windows) {
    if (!isLocal) return LocalCwd(r'\\' + host + path.replaceAll('/', r'\'));
    final drive = _driveUrl.firstMatch(path);
    if (drive == null) return null;
    final tail = (drive[2] ?? '/').replaceAll('/', r'\');
    return LocalCwd('${drive[1]!.toUpperCase()}:$tail');
  }
  return isLocal ? LocalCwd(path) : const RemoteCwd();
}

bool _isLocalHost(String host, String localHostName) {
  if (host.isEmpty) return true;
  final h = host.toLowerCase();
  if (h == 'localhost') return true;
  String label(String name) => name.toLowerCase().split('.').first;
  return localHostName.isNotEmpty && label(h) == label(localHostName);
}

/// `%XX` → byte; other characters as their UTF-8; the bytes must be UTF-8.
String? _percentDecode(String text) {
  final runes = text.runes.toList();
  final bytes = <int>[];
  for (var i = 0; i < runes.length; i++) {
    final rune = runes[i];
    if (rune != 0x25) {
      bytes.addAll(utf8.encode(String.fromCharCode(rune)));
      continue;
    }
    if (i + 2 >= runes.length) return null;
    final hi = String.fromCharCode(runes[i + 1]);
    final lo = String.fromCharCode(runes[i + 2]);
    if (!_hexDigit.hasMatch(hi) || !_hexDigit.hasMatch(lo)) return null;
    bytes.add(int.parse('$hi$lo', radix: 16));
    i += 2;
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}
