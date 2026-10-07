import 'package:shellx_core/shellx_core.dart';
import 'package:xterm/core.dart';

import 'desktop_terminal.dart';
import 'terminal_buffer_text.dart';

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

  bool get isWeb => kind == TerminalLinkKind.url;

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
    final visible = buffer.getText(BufferRangeLine(begin, end));
    return LinkHit(
      source: LinkSource.hyperlink,
      kind: TerminalLinkKind.url,
      target: osc.uri,
      begin: begin,
      end: end,
      visible: visible,
      needsConfirm: !hyperlinkTextMatches(visible, osc.uri),
    );
  }
  final line = logicalLineAt(buffer, cell.y);
  final index = line.indexOfCell(cell.y, cell.x);
  if (index == null) return null;
  final link = linkAt(line.text, index, paths: paths);
  if (link == null) return null;
  return LinkHit(
    source: LinkSource.detected,
    kind: link.kind,
    target: link.target,
    begin: line.beginOf(link.start),
    end: line.endAfter(link.end - 1),
  );
}
