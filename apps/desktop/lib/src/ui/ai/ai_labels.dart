import 'package:shellx_acp/shellx_acp.dart';

import '../../../l10n/app_localizations.dart';

/// D10: the main label of a permission option comes from its kind; the
/// agent's own words stay as the second line (only the agent knows what
/// "always" covers).
String aiPermissionLabel(AppLocalizations l10n, PermissionOption option) =>
    switch (option.kind) {
      PermissionKind.allowOnce => l10n.aiPermAllowOnce,
      PermissionKind.allowAlways => l10n.aiPermAllowAlways,
      PermissionKind.rejectOnce => l10n.aiPermRejectOnce,
      PermissionKind.rejectAlways => l10n.aiPermRejectAlways,
      PermissionKind.other => option.name,
    };

/// [path] relative to the session folder [cwd] when it is inside it.
String aiRelativePath(String path, String cwd) {
  final root = cwd.endsWith('/') || cwd.endsWith(r'\') ? cwd : '$cwd/';
  if (path.startsWith(root)) return path.substring(root.length);
  final win = root.replaceAll('/', r'\');
  return path.startsWith(win) ? path.substring(win.length) : path;
}

/// "0:41" (spec §4.2 turn summary, the header clock).
String aiClock(Duration d) {
  final s = d.inSeconds;
  final m = s ~/ 60;
  return m >= 60
      ? '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}'
      : '$m:${(s % 60).toString().padLeft(2, '0')}';
}

/// "2,1" / "2.1" seconds, in the language's decimal mark.
String aiSeconds(Duration d, String localeName) {
  final tenths = (d.inMilliseconds / 100).round();
  final text = '${tenths ~/ 10}.${tenths % 10}';
  return localeName.startsWith('vi') ? text.replaceAll('.', ',') : text;
}
