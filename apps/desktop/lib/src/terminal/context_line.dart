import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

/// UI-A2 §2.2 shares.
const double _portPadding = 4; // 2 × ShellxSizes.portPadH
const double _portGap = 4;
const double _portsMaxShare = 0.6;
const double _branchMaxShare = 0.45;
const double _branchMin = 48;
const double _pathMin = 40;

/// A cut name keeps at least this many characters before `…` (V2): `w…`
/// says nothing.
const int _minKept = 3;
const String _separator = ' · ';

/// UI-A2 §2.3: the home directory as `~`, only on a whole component;
/// Windows compares without case and accepts `\` and `/`.
String displayPath(String path, {required String home, required bool windows}) {
  if (home.isEmpty) return path;
  bool sep(String c) => c == '/' || (windows && c == r'\');
  var h = home;
  while (h.length > 1 && sep(h[h.length - 1])) {
    h = h.substring(0, h.length - 1);
  }
  final starts = windows
      ? path.toLowerCase().startsWith(h.toLowerCase())
      : path.startsWith(h);
  if (!starts) return path;
  if (path.length == h.length) return '~';
  if (!sep(path[h.length])) return path;
  return '~${path.substring(h.length)}';
}

/// The longest start of [text] + `…` that fits; '' when not even that.
String ellipsizeEnd(
  String text,
  double maxWidth,
  double Function(String) measure,
) {
  if (measure(text) <= maxWidth) return text;
  // Whole grapheme clusters: an NFD "ệ" (e + two marks) or a ZWJ emoji
  // is never cut in two.
  final chars = text.characters.toList();
  String cut(int n) => '${chars.take(n).join()}…';
  var lo = 0;
  var hi = chars.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (measure(cut(mid)) <= maxWidth) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo == 0 ? '' : cut(lo);
}

/// Both ends of [text] around `…` (the start gets the extra character).
String ellipsizeMiddle(
  String text,
  double maxWidth,
  double Function(String) measure,
) {
  if (measure(text) <= maxWidth) return text;
  final chars = text.characters.toList(); // whole grapheme clusters
  String cut(int n) {
    final head = (n + 1) ~/ 2;
    final tail = n - head;
    return '${chars.take(head).join()}…'
        '${chars.skip(chars.length - tail).join()}';
  }

  var lo = 0;
  var hi = chars.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (measure(cut(mid)) <= maxWidth) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo == 0 ? '' : cut(lo);
}

/// UI-A2 §2.2 step 4 (V2): keep the first component (`~`, `/`, `C:`),
/// replace middle components with `…`, keep as many last components as
/// fit (`~/…/apps/desktop`); then the last component alone, first as
/// `…/desktop`, then whole (`desktop`), then end-cut (`desk…`, at least
/// three characters). '' when not even that fits: a whole path is never
/// cut through its characters (`~/w…llx` names no folder).
String ellipsizePath(
  String path,
  double maxWidth,
  double Function(String) measure, {
  required bool windows,
}) {
  if (measure(path) <= maxWidth) return path;
  final sep = windows ? r'\' : '/';
  final parts = path.split(windows ? RegExp(r'[\\/]') : RegExp('/'));
  if (parts.length > 2) {
    for (var keep = parts.length - 2; keep >= 1; keep--) {
      final candidate = [
        parts.first,
        '…',
        ...parts.sublist(parts.length - keep),
      ].join(sep);
      if (measure(candidate) <= maxWidth) return candidate;
    }
  }
  final last = parts.lastWhere((p) => p.isNotEmpty, orElse: () => path);
  if (parts.length > 1) {
    final tail = '…$sep$last';
    if (measure(tail) <= maxWidth) return tail;
  }
  if (measure(last) <= maxWidth) return last;
  final cut = ellipsizeEnd(last, maxWidth, measure);
  return cut.characters.length > _minKept ? cut : '';
}

/// The least a path may shrink to before something else gives way (V2):
/// itself when short, else `…/last` — never under [_pathMin].
double _pathNeed(String path, double Function(String) measure, bool windows) {
  final whole = measure(path);
  final parts = path.split(windows ? RegExp(r'[\\/]') : RegExp('/'));
  final last = parts.lastWhere((p) => p.isNotEmpty, orElse: () => path);
  final tail = measure('…${windows ? r'\' : '/'}$last');
  return min(whole, max(_pathMin, tail));
}

@immutable
final class ContextLineLayout {
  const ContextLineLayout({
    this.branch,
    this.path,
    this.ports = const [],
    this.morePorts = 0,
    this.truncated = false,
  });

  final String? branch;
  final String? path;

  /// The ports shown (ascending), and how many more hide behind `+N`.
  final List<int> ports;
  final int morePorts;

  /// Something was cut or left out: the row shows the full-line tooltip.
  final bool truncated;

  bool get isEmpty => branch == null && path == null && ports.isEmpty;
}

/// UI-A2 §2.2 (V2, V8): ports (never cut, ≤ 60 %, and never so many that
/// the folder loses its last component) > branch (≤ 45 % of the rest,
/// end-cut; [branchGlyph] is the glyph and gap drawn before it) > path
/// (cut by components, dropped under 40 px unless it fits whole).
ContextLineLayout layoutContextLine({
  required String? branch,
  required String? path,
  required List<int> ports,
  required double width,
  required double Function(String) measure,
  required bool windows,
  double branchGlyph = 0,
}) {
  final sepWidth = measure(_separator);
  double portsWidth(List<int> shown, int more) {
    if (shown.isEmpty) return 0;
    var w = _portGap * (shown.length - 1);
    for (final p in shown) {
      w += measure(':$p') + _portPadding;
    }
    if (more > 0) w += _portGap + measure('+$more');
    return w;
  }

  double branchWidth(String b) => branchGlyph + measure(b);

  final pathNeed = path == null ? 0.0 : _pathNeed(path, measure, windows);
  final branchNeed = branch == null
      ? 0.0
      : branchGlyph + min(measure(branch), _branchMin) + sepWidth;
  final portsCap = path == null
      ? width * _portsMaxShare
      : min(width * _portsMaxShare, width - sepWidth - pathNeed - branchNeed);

  final sorted = [...ports]..sort(); // the smallest ports first
  var shown = sorted.take(3).toList();
  var more = sorted.length - shown.length;
  while (shown.length > 1 && portsWidth(shown, more) > portsCap) {
    shown = shown.sublist(0, shown.length - 1);
    more++;
  }
  var truncated = more > 0;
  var remaining = width - portsWidth(shown, more);
  if (shown.isNotEmpty && (branch != null || path != null)) {
    remaining -= sepWidth;
  }

  String? b = branch;
  if (b != null) {
    var cap = remaining < _branchMin
        ? remaining
        : max(_branchMin, remaining * _branchMaxShare);
    if (path != null) {
      cap = min(cap, max(_branchMin, remaining - sepWidth - pathNeed));
    }
    if (branchWidth(b) > cap) {
      b = ellipsizeEnd(b, cap - branchGlyph, measure);
      truncated = true;
      if (b.isEmpty) b = null;
    }
    if (b != null) remaining -= branchWidth(b);
  }

  String? p = path;
  if (p != null) {
    if (b != null) remaining -= sepWidth;
    if (measure(p) <= remaining) {
      // fits whole
    } else if (remaining < _pathMin) {
      p = null;
      truncated = true;
    } else {
      p = ellipsizePath(p, remaining, measure, windows: windows);
      truncated = true;
      if (p.isEmpty) p = null;
    }
  }
  return ContextLineLayout(
    branch: b,
    path: p,
    ports: shown,
    morePorts: more,
    truncated: truncated,
  );
}
