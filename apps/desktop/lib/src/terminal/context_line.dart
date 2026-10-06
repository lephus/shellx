import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

/// UI-A2 §2.2 shares.
const double _portPadding = 4; // 2 × ShellxSizes.portPadH
const double _portGap = 4;
const double _portsMaxShare = 0.6;
const double _branchMaxShare = 0.45;
const double _branchMin = 48;
const double _pathMin = 24;
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

/// UI-A2 §2.2 step 4: keep the first component (`~`, `/`, `C:`), replace
/// middle components with `…`, keep as many last components as fit; then
/// [ellipsizeMiddle] on characters.
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
  return ellipsizeMiddle(path, maxWidth, measure);
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

/// UI-A2 §2.2: ports (never cut, ≤ 60 %) > branch (≤ 45 % of the rest,
/// end-cut) > path (middle-cut, dropped under 24 px).
ContextLineLayout layoutContextLine({
  required String? branch,
  required String? path,
  required List<int> ports,
  required double width,
  required double Function(String) measure,
  required bool windows,
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

  final sorted = [...ports]..sort(); // the smallest ports first
  var shown = sorted.take(3).toList();
  var more = sorted.length - shown.length;
  while (shown.length > 1 && portsWidth(shown, more) > width * _portsMaxShare) {
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
    final cap = remaining < _branchMin
        ? remaining
        : max(_branchMin, remaining * _branchMaxShare);
    if (measure(b) > cap) {
      b = ellipsizeEnd(b, cap, measure);
      truncated = true;
      if (b.isEmpty) b = null;
    }
    if (b != null) remaining -= measure(b);
  }

  String? p = path;
  if (p != null) {
    if (b != null) remaining -= sepWidth;
    if (remaining < _pathMin) {
      p = null;
      truncated = true;
    } else if (measure(p) > remaining) {
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
