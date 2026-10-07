/// What a line of terminal text links to (A10 D6, D7, D10). Pure Dart, no
/// xterm: the desktop and the phone each map a buffer line to a string and
/// the cell of every character, then ask here. Nothing in this file logs.
library;

/// The longest URL or path considered (A10 D6).
const int kMaxLinkLength = 2048;

enum TerminalLinkKind { url, path }

/// A link in a line of text: `[start, end)` are indices into the text that
/// was scanned, [target] is the URL, or the path without its line suffix.
final class TerminalLink {
  const TerminalLink({
    required this.kind,
    required this.start,
    required this.end,
    required this.target,
    this.line,
    this.column,
  });

  final TerminalLinkKind kind;
  final int start;
  final int end;
  final String target;
  final int? line;
  final int? column;

  bool contains(int index) => index >= start && index < end;

  /// Never shows what the link points at (privacy: A10 §5).
  @override
  String toString() => 'TerminalLink(…)';
}

const String _p = r'[A-Za-z0-9_.\-@%+=~À-￿]';
const String _before = r'(?<![A-Za-z0-9_.\-@%+=~/:\\À-￿])';
const String _suffix =
    r'(?::(\d{1,6})(?::(\d{1,6}))?|\((\d{1,6})(?:,\s*(\d{1,6}))?\))?';

final RegExp _urlPattern = RegExp(
  r'https?://[^\s<>"`\u0000-\u001f\u007f]+',
  caseSensitive: false,
);
final RegExp _absPath = RegExp(
  '$_before(?:~|\\.{1,2})?/(?:$_p+/)*$_p*$_suffix',
);
final RegExp _relPath = RegExp(
  '$_before(?:$_p+/)+$_p*\\.[A-Za-z0-9]{1,8}$_suffix',
);
final RegExp _winPath = RegExp(
  r'(?<![A-Za-z0-9])[A-Za-z]:\\(?:[^\s:*?"<>|\\]+\\)*[^\s:*?"<>|\\]*' + _suffix,
);

const String _trailingPunctuation = '.,;:!?\'"*';

/// [raw] without the punctuation a sentence adds after a URL: `.,;:!?'"*`,
/// and a closing `)`, `]` or `}` with no opening one inside the URL (so a
/// Wikipedia address ending in `)` keeps it).
String trimLinkEnd(String raw) {
  var s = raw;
  while (s.isNotEmpty) {
    final last = s[s.length - 1];
    if (_trailingPunctuation.contains(last)) {
      s = s.substring(0, s.length - 1);
      continue;
    }
    final open = switch (last) {
      ')' => '(',
      ']' => '[',
      '}' => '{',
      _ => null,
    };
    if (open != null && _count(s, last) > _count(s, open)) {
      s = s.substring(0, s.length - 1);
      continue;
    }
    break;
  }
  return s;
}

int _count(String s, String c) {
  var n = 0;
  for (var i = 0; i < s.length; i++) {
    if (s[i] == c) n++;
  }
  return n;
}

/// [raw] as a web address that may be opened: absolute `http`/`https` with a
/// host, no control characters, at most [kMaxLinkLength]. Null otherwise
/// (A10 D6: nothing else ever opens).
Uri? webUriOf(String raw) {
  if (raw.isEmpty || raw.length > kMaxLinkLength) return null;
  if (RegExp(r'[\u0000-\u001f\u007f\u0080-\u009f\s]').hasMatch(raw)) {
    return null;
  }
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.isAbsolute) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  return uri;
}

/// A10 D10: an OSC 8 target is acceptable only as [webUriOf] says.
bool isSafeHyperlinkUri(String uri) => webUriOf(uri) != null;

/// A10 D10: the text shown for an OSC 8 link already tells where it goes
/// (it is that address, or an address on the same host): no confirmation.
bool hyperlinkTextMatches(String visible, String uri) {
  final shown = visible.trim();
  if (shown == uri) return true;
  final target = webUriOf(uri);
  if (target == null) return false;
  final asUri = webUriOf(shown);
  if (asUri != null) {
    return asUri.host.toLowerCase() == target.host.toLowerCase();
  }
  return false;
}

/// Every link in [text], in order, none overlapping. URLs first; with
/// [paths] (a local pane, A10 D7) paths that do not overlap a URL.
List<TerminalLink> findLinks(String text, {bool paths = false}) {
  final links = <TerminalLink>[];
  for (final m in _urlPattern.allMatches(text)) {
    final trimmed = trimLinkEnd(m.group(0)!);
    if (webUriOf(trimmed) == null) continue;
    links.add(
      TerminalLink(
        kind: TerminalLinkKind.url,
        start: m.start,
        end: m.start + trimmed.length,
        target: trimmed,
      ),
    );
  }
  if (!paths) return links;
  final found = <TerminalLink>[];
  for (final regex in [_absPath, _relPath, _winPath]) {
    for (final m in regex.allMatches(text)) {
      final link = _pathLink(m);
      if (link == null) continue;
      final overlaps =
          links.any((l) => link.start < l.end && l.start < link.end) ||
          found.any((l) => link.start < l.end && l.start < link.end);
      if (!overlaps) found.add(link);
    }
  }
  links.addAll(found);
  links.sort((a, b) => a.start.compareTo(b.start));
  return links;
}

TerminalLink? _pathLink(RegExpMatch m) {
  final whole = m.group(0)!;
  final hasSuffix = m.group(1) != null || m.group(3) != null; // :12 or (12)
  var core = hasSuffix
      ? whole.substring(0, whole.length - _suffixLength(m, whole))
      : whole;
  if (!hasSuffix) core = _trimPathEnd(core);
  if (core.isEmpty || core.length > kMaxLinkLength) return null;
  // A lone "/" or "~" or "./" is not a path anyone means.
  if (core == '/' || core == '~' || core == './' || core == '../') return null;
  final line = int.tryParse(m.group(1) ?? m.group(3) ?? '');
  final col = int.tryParse(m.group(2) ?? m.group(4) ?? '');
  return TerminalLink(
    kind: TerminalLinkKind.path,
    start: m.start,
    end: m.start + core.length + (hasSuffix ? _suffixLength(m, whole) : 0),
    target: core,
    line: line,
    column: col,
  );
}

int _suffixLength(RegExpMatch m, String whole) {
  final tail = RegExp(
    r'(?::\d{1,6}(?::\d{1,6})?|\(\d{1,6}(?:,\s*\d{1,6})?\))$',
  ).firstMatch(whole);
  return tail?.group(0)?.length ?? 0;
}

String _trimPathEnd(String s) {
  var t = s;
  while (t.length > 1 && '.,;:!?'.contains(t[t.length - 1])) {
    t = t.substring(0, t.length - 1);
  }
  return t;
}

/// The link under character [index] of [text], or null.
TerminalLink? linkAt(String text, int index, {bool paths = false}) {
  for (final link in findLinks(text, paths: paths)) {
    if (link.contains(index)) return link;
  }
  return null;
}
