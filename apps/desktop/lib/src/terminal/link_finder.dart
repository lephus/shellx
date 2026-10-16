import 'package:shellx_core/shellx_core.dart';
import 'package:xterm/core.dart';

import 'desktop_terminal.dart';
import 'terminal_buffer_text.dart';

/// How much of an OSC 8 link's text is read on hover: 8 rows, 2048 characters.
const int kMaxHoverRows = 8;
const int kMaxHoverText = 2048;

/// Where a link came from.
enum LinkSource { detected, hyperlink }

/// The link under a cell: [begin] and [end] (exclusive) are buffer cells.
final class LinkHit {
  const LinkHit({
    required this.source,
    required this.kind,
    required this.target,
    required this.begin,
    required this.end,
    this.needsConfirm = false,
    this.visible,
    this.line,
    this.column,
  });

  final LinkSource source;
  final TerminalLinkKind kind;

  /// The address, or the path as written (without its `:line`).
  final String target;
  final CellOffset begin;
  final CellOffset end;

  /// An OSC 8 link whose text is not its address (A10 D10).
  final bool needsConfirm;

  /// The text shown for an OSC 8 link.
  final String? visible;

  /// A detected path's `:line` / `:line:col` (or `(line,col)`), 1-based as
  /// printed; null when the path has none. `link-editor` opens the file
  /// there.
  final int? line;
  final int? column;

  bool get isWeb => kind == TerminalLinkKind.url;

  @override
  bool operator ==(Object other) =>
      other is LinkHit &&
      other.source == source &&
      other.kind == kind &&
      other.target == target &&
      other.begin == begin &&
      other.end == end &&
      other.line == line &&
      other.column == column;

  @override
  int get hashCode =>
      Object.hash(source, kind, target, begin, end, line, column);

  /// Never shows the target (A10 §5).
  @override
  String toString() => 'LinkHit(…)';
}

/// A10 D6–D11: the link under a cell of [terminal]: an OSC 8 hyperlink
/// first, else a URL (or, with [paths], a path) found in the logical line.
LinkHit? findLinkAt(
  DesktopTerminal terminal,
  CellOffset cell, {
  required bool paths,
}) {
  final buffer = terminal.buffer;
  if (cell.y < 0 || cell.y >= buffer.height) return null;
  final osc = terminal.hyperlinks.at(cell.y, cell.x);
  if (osc != null) {
    final begin = osc.begin.offset;
    final end = osc.end.offset;
    // A program can put one link over thousands of rows: only the start is
    // read (hover runs this on every pointer move), and a link whose text
    // was cut cannot be verified, so it asks first.
    final tooLong = end.y - begin.y >= kMaxHoverRows;
    var visible = buffer.getText(
      BufferRangeLine(
        begin,
        tooLong ? CellOffset(0, begin.y + kMaxHoverRows) : end,
      ),
    );
    final cut = tooLong || visible.length > kMaxHoverText;
    if (visible.length > kMaxHoverText) {
      visible = visible.substring(0, kMaxHoverText);
    }
    return LinkHit(
      source: LinkSource.hyperlink,
      kind: TerminalLinkKind.url,
      target: osc.uri,
      begin: begin,
      end: end,
      visible: visible,
      needsConfirm: cut || !hyperlinkTextMatches(visible, osc.uri),
    );
  }
  final line = logicalLineAt(buffer, cell.y);
  final index = line.indexOfCell(cell.y, cell.x);
  if (index == null) return null;
  final link = linkAt(line.text, index, paths: paths);
  if (link == null) return null;
  // A link that runs into the cap's edge may be cut: never open half a URL.
  if ((line.clippedAfter && link.end >= line.text.length) ||
      (line.clippedBefore && link.start == 0)) {
    return null;
  }
  return LinkHit(
    source: LinkSource.detected,
    kind: link.kind,
    target: link.target,
    begin: line.beginOf(link.start),
    end: line.endAfter(link.end - 1),
    line: link.line,
    column: link.column,
  );
}
