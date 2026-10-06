import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

/// A3 D2. `row`: the two halves side by side (split right); `column`:
/// stacked (split down).
enum SplitAxis { row, column }

enum PaneDirection { left, right, up, down }

/// Where a split sits in a tree: `''` is the root, then one character per
/// level, `'0'` for `first`, `'1'` for `second`. Paths change when the tree
/// does; users re-check the node they find ([nodeAt]).
typedef PanePath = String;

/// A tab's pane tree (A3 P1). Immutable; every operation returns a new tree.
@immutable
sealed class PaneNode {
  const PaneNode();
}

@immutable
final class PaneLeaf extends PaneNode {
  const PaneLeaf(this.sessionId);
  final int sessionId;

  @override
  bool operator ==(Object other) =>
      other is PaneLeaf && other.sessionId == sessionId;
  @override
  int get hashCode => sessionId.hashCode;
  @override
  String toString() => 'PaneLeaf($sessionId)';
}

@immutable
final class PaneSplit extends PaneNode {
  const PaneSplit({
    required this.axis,
    required this.ratio,
    required this.first,
    required this.second,
  });

  final SplitAxis axis;

  /// The share of [first] along [axis], in [kMinPaneRatio, 1 − kMinPaneRatio].
  final double ratio;
  final PaneNode first;
  final PaneNode second;

  PaneSplit copyWith({double? ratio, PaneNode? first, PaneNode? second}) =>
      PaneSplit(
        axis: axis,
        ratio: ratio ?? this.ratio,
        first: first ?? this.first,
        second: second ?? this.second,
      );

  @override
  bool operator ==(Object other) =>
      other is PaneSplit &&
      other.axis == axis &&
      other.ratio == ratio &&
      other.first == first &&
      other.second == second;
  @override
  int get hashCode => Object.hash(axis, ratio, first, second);
  @override
  String toString() => 'PaneSplit($axis, $ratio, $first, $second)';
}

/// The model's own floor; pixel minimums (A3 D4) are applied by the tab
/// list, which knows the pane area.
const double kMinPaneRatio = 0.05;

double clampRatio(double ratio) =>
    ratio.clamp(kMinPaneRatio, 1 - kMinPaneRatio).toDouble();

const Rect _unit = Rect.fromLTWH(0, 0, 1, 1);

/// D23: reading order — `first` before `second`, depth first.
List<int> paneIds(PaneNode node) => switch (node) {
  PaneLeaf(:final sessionId) => [sessionId],
  PaneSplit(:final first, :final second) => [
    ...paneIds(first),
    ...paneIds(second),
  ],
};

/// D3: [target] becomes a split of [axis] with [newId] after it, half each.
PaneNode splitPane(PaneNode node, int target, int newId, SplitAxis axis) =>
    switch (node) {
      PaneLeaf(:final sessionId) when sessionId == target => PaneSplit(
        axis: axis,
        ratio: 0.5,
        first: node,
        second: PaneLeaf(newId),
      ),
      PaneLeaf() => node,
      final PaneSplit s => s.copyWith(
        first: splitPane(s.first, target, newId, axis),
        second: splitPane(s.second, target, newId, axis),
      ),
    };

/// D7: the tree without [id]; its sibling takes its parent's place. Null
/// when [id] was the only pane.
PaneNode? removePane(PaneNode node, int id) => switch (node) {
  PaneLeaf(:final sessionId) => sessionId == id ? null : node,
  final PaneSplit s => _rejoin(
    s,
    removePane(s.first, id),
    removePane(s.second, id),
  ),
};

PaneNode? _rejoin(PaneSplit s, PaneNode? first, PaneNode? second) {
  if (first == null) return second;
  if (second == null) return first;
  if (identical(first, s.first) && identical(second, s.second)) return s;
  return s.copyWith(first: first, second: second);
}

/// D8 fallback: the first leaf (reading order) of [id]'s sibling branch.
int? siblingLeaf(PaneNode node, int id) {
  if (node is! PaneSplit) return null;
  if (node.first == PaneLeaf(id)) return paneIds(node.second).first;
  if (node.second == PaneLeaf(id)) return paneIds(node.first).first;
  return siblingLeaf(node.first, id) ?? siblingLeaf(node.second, id);
}

/// Every leaf's rectangle inside [area] (the unit square by default).
Map<int, Rect> paneRects(PaneNode node, [Rect area = _unit]) {
  final out = <int, Rect>{};
  void visit(PaneNode n, Rect r) {
    switch (n) {
      case PaneLeaf(:final sessionId):
        out[sessionId] = r;
      case PaneSplit(:final axis, :final ratio, :final first, :final second):
        final (a, b) = _halves(r, axis, ratio);
        visit(first, a);
        visit(second, b);
    }
  }

  visit(node, area);
  return out;
}

(Rect, Rect) _halves(Rect r, SplitAxis axis, double ratio) {
  if (axis == SplitAxis.row) {
    final x = r.left + r.width * ratio;
    return (
      Rect.fromLTRB(r.left, r.top, x, r.bottom),
      Rect.fromLTRB(x, r.top, r.right, r.bottom),
    );
  }
  final y = r.top + r.height * ratio;
  return (
    Rect.fromLTRB(r.left, r.top, r.right, y),
    Rect.fromLTRB(r.left, y, r.right, r.bottom),
  );
}

/// The rectangle of the split at [path]; null when [path] is not a split.
Rect? splitRect(PaneNode node, PanePath path, [Rect area = _unit]) {
  var n = node;
  var r = area;
  for (final step in path.split('')) {
    if (n is! PaneSplit) return null;
    final (a, b) = _halves(r, n.axis, n.ratio);
    (n, r) = step == '0' ? (n.first, a) : (n.second, b);
  }
  return n is PaneSplit ? r : null;
}

const double _eps = 1e-6;

/// D9: the pane next to [from] in [direction] — touching edge, overlapping
/// on the other axis; the one holding [from]'s centre line, else the
/// largest overlap, ties by [mru] (most recent first). Null: none (no wrap).
int? neighbourPane(
  PaneNode node,
  int from,
  PaneDirection direction, {
  List<int> mru = const [],
}) {
  final rects = paneRects(node);
  final f = rects[from];
  if (f == null) return null;
  final sideways =
      direction == PaneDirection.left || direction == PaneDirection.right;
  final overlaps = <int, double>{};
  for (final MapEntry(key: id, value: r) in rects.entries) {
    if (id == from) continue;
    final touches = switch (direction) {
      PaneDirection.left => (r.right - f.left).abs() < _eps,
      PaneDirection.right => (r.left - f.right).abs() < _eps,
      PaneDirection.up => (r.bottom - f.top).abs() < _eps,
      PaneDirection.down => (r.top - f.bottom).abs() < _eps,
    };
    if (!touches) continue;
    final overlap = sideways
        ? math.min(r.bottom, f.bottom) - math.max(r.top, f.top)
        : math.min(r.right, f.right) - math.max(r.left, f.left);
    if (overlap > _eps) overlaps[id] = overlap;
  }
  if (overlaps.isEmpty) return null;
  final centre = sideways ? f.center.dy : f.center.dx;
  for (final id in overlaps.keys) {
    final r = rects[id]!;
    final (lo, hi) = sideways ? (r.top, r.bottom) : (r.left, r.right);
    if (lo <= centre + _eps && centre < hi - _eps) return id;
  }
  final best = overlaps.values.reduce(math.max);
  final pool = [
    for (final MapEntry(key: id, value: o) in overlaps.entries)
      if ((o - best).abs() < _eps) id,
  ];
  for (final id in mru) {
    if (pool.contains(id)) return id;
  }
  return pool.first;
}

/// D11: how many panes line up along [axis].
int paneSpan(PaneNode node, SplitAxis axis) => switch (node) {
  PaneLeaf() => 1,
  PaneSplit(axis: final a, :final first, :final second) =>
    a == axis
        ? paneSpan(first, axis) + paneSpan(second, axis)
        : math.max(paneSpan(first, axis), paneSpan(second, axis)),
};

double _evenRatio(PaneSplit s) {
  final a = paneSpan(s.first, s.axis);
  return a / (a + paneSpan(s.second, s.axis));
}

/// D11: every split shares its extent by span (three columns → 1/3 each).
PaneNode equalized(PaneNode node) => switch (node) {
  PaneLeaf() => node,
  final PaneSplit s => PaneSplit(
    axis: s.axis,
    ratio: _evenRatio(s),
    first: equalized(s.first),
    second: equalized(s.second),
  ),
};

/// D11 (double-click a divider): only the split at [path].
PaneNode equalizedAt(PaneNode node, PanePath path) =>
    _replaceAt(node, path, (s) => s.copyWith(ratio: _evenRatio(s)));

PaneNode? nodeAt(PaneNode node, PanePath path) {
  PaneNode n = node;
  for (final step in path.split('')) {
    if (n is! PaneSplit) return null;
    n = step == '0' ? n.first : n.second;
  }
  return n;
}

/// The split at [path] with [ratio] (clamped); anything else unchanged.
PaneNode withRatio(PaneNode node, PanePath path, double ratio) =>
    _replaceAt(node, path, (s) => s.copyWith(ratio: clampRatio(ratio)));

PaneNode _replaceAt(
  PaneNode node,
  PanePath path,
  PaneSplit Function(PaneSplit split) change,
) {
  if (node is! PaneSplit) return node;
  if (path.isEmpty) return change(node);
  final rest = path.substring(1);
  return path[0] == '0'
      ? node.copyWith(first: _replaceAt(node.first, rest, change))
      : node.copyWith(second: _replaceAt(node.second, rest, change));
}

/// D12: the deepest split of [axis] above [id]; null when none.
PanePath? ancestorSplit(PaneNode node, int id, SplitAxis axis) {
  PanePath? found;
  bool visit(PaneNode n, PanePath path) {
    switch (n) {
      case PaneLeaf(:final sessionId):
        return sessionId == id;
      case final PaneSplit s:
        final inside =
            visit(s.first, '${path}0') || visit(s.second, '${path}1');
        if (inside && found == null && s.axis == axis) found = path;
        return inside;
    }
  }

  visit(node, '');
  return found;
}
