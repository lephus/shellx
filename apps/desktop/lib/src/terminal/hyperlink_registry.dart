import 'package:shellx_core/shellx_core.dart' show isSafeHyperlinkUri;
import 'package:xterm/core.dart';

/// One OSC 8 link: the cells between [begin] and [end] (exclusive) point
/// at [uri]. The anchors follow the text as it scrolls.
final class HyperlinkRange {
  HyperlinkRange(this.begin, this.end, this.uri);
  final CellAnchor begin;
  final CellAnchor end;
  final String uri;

  bool get attached => begin.attached && end.attached;

  bool contains(int row, int col) {
    if (!attached) return false;
    final b = begin.offset;
    final e = end.offset;
    final afterBegin = row > b.y || (row == b.y && col >= b.x);
    final beforeEnd = row < e.y || (row == e.y && col < e.x);
    return afterBegin && beforeEnd;
  }

  /// Never shows the address (A10 §5).
  @override
  String toString() => 'HyperlinkRange(…)';
}

/// A10 D11: remembers where the program put OSC 8 hyperlinks. xterm 4.0.0
/// hands the sequence over (`onPrivateOSC`) but stores nothing per cell, so
/// the open and close are noted as anchors at the cursor.
final class HyperlinkRegistry {
  HyperlinkRegistry({this.maxRanges = 2000});

  final int maxRanges;
  final _ranges = <HyperlinkRange>[];
  CellAnchor? _openAt;
  String? _openUri;

  int get length => _ranges.length;

  /// OSC 8 as xterm passes it: [args] is `params`, then the URI split at
  /// every `;` (a URI may hold one).
  void handle(Buffer buffer, List<String> args) {
    if (args.length < 2) return;
    final uri = args.sublist(1).join(';');
    if (uri.isEmpty) {
      _close(buffer);
    } else {
      _open(buffer, uri);
    }
  }

  void _open(Buffer buffer, String uri) {
    // OSC 8: a new link ends the one still open, right here.
    if (_openAt != null) _close(buffer);
    _openAt?.dispose();
    _openAt = null;
    _openUri = null;
    // A10 D10: nothing but http/https is ever recorded.
    if (!isSafeHyperlinkUri(uri)) return;
    _openAt = buffer.createAnchorFromCursor();
    _openUri = uri;
  }

  void _close(Buffer buffer) {
    final begin = _openAt;
    final uri = _openUri;
    _openAt = null;
    _openUri = null;
    if (begin == null || uri == null) return;
    final end = buffer.createAnchorFromCursor();
    if (!begin.attached || !end.attached) {
      begin.dispose();
      end.dispose();
      return;
    }
    _ranges.add(HyperlinkRange(begin, end, uri));
    _prune();
  }

  void _prune() {
    _ranges.removeWhere((r) {
      final gone = !r.attached;
      if (gone) {
        r.begin.dispose();
        r.end.dispose();
      }
      return gone;
    });
    while (_ranges.length > maxRanges) {
      final old = _ranges.removeAt(0);
      old.begin.dispose();
      old.end.dispose();
    }
  }

  /// The link under cell ([row], [col]), the newest first.
  HyperlinkRange? at(int row, int col) {
    for (var i = _ranges.length - 1; i >= 0; i--) {
      if (_ranges[i].contains(row, col)) return _ranges[i];
    }
    return null;
  }

  /// Drops every range and the open one: they belong to the buffer that was
  /// active (a screen switch makes them point at the wrong lines).
  void clear() {
    _openAt?.dispose();
    _openAt = null;
    _openUri = null;
    for (final r in _ranges) {
      r.begin.dispose();
      r.end.dispose();
    }
    _ranges.clear();
  }

  void dispose() {
    _openAt?.dispose();
    for (final r in _ranges) {
      r.begin.dispose();
      r.end.dispose();
    }
    _ranges.clear();
  }
}
