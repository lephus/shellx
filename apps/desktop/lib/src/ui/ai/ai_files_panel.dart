import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_gitignore.dart';
import '../../ai/ai_project_files.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_changes_panel.dart' show aiTurnsOf, AiTurns;
import 'ai_file_viewer.dart';
import 'ai_scope.dart';

/// D18, §4.4: the Files tab — the session folder as a tree, folders before
/// files, `.git` hidden, loaded a folder at a time (off the UI isolate).
/// Files the session changed carry M or A; what `.gitignore` drops is
/// dimmed "ignored" (B12). A file opens in the viewer. It reloads when a
/// turn ends and when its tab comes back to the front (D18; never
/// continuously).
class AiFilesPanel extends ConsumerStatefulWidget {
  const AiFilesPanel({super.key});

  @override
  ConsumerState<AiFilesPanel> createState() => _AiFilesPanelState();
}

typedef _Row = ({AiDirEntry entry, int depth});

class _AiFilesPanelState extends ConsumerState<AiFilesPanel> {
  AiPaneScope? _pane;
  AiTurns? _turns;
  final _open = <String>{};
  final _children = <String, List<AiDirEntry>>{};
  Map<String, ChangeKind> _changed = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pane = AiPaneScope.of(context);
    if (!identical(pane.frames, _pane?.frames)) {
      _pane?.frames.removeListener(_onFrame);
      _pane?.ui.changes.removeListener(_onChanges);
      pane.frames.addListener(_onFrame);
      pane.ui.changes.addListener(_onChanges);
      _pane = pane;
      _turns = aiTurnsOf(pane.state);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_reload());
      });
    }
    _pane = pane;
  }

  @override
  void dispose() {
    _pane?.frames.removeListener(_onFrame);
    _pane?.ui.changes.removeListener(_onChanges);
    super.dispose();
  }

  void _onChanges() => unawaited(_reload());

  void _onFrame() {
    final next = aiTurnsOf(_pane!.state);
    final ended = next.lastFinished != _turns?.lastFinished;
    _turns = next;
    if (ended) unawaited(_reload());
  }

  Future<void> _reload() async {
    await Future.wait([
      for (final dir in ['', ..._open]) _load(dir),
    ]);
    final changes = await _pane!.runtime.sessionChanges();
    if (!mounted) return;
    setState(() {
      _changed = {
        for (final c in changes ?? const <FileChange>[]) c.path: c.kind,
      };
    });
  }

  Future<void> _load(String dir) async {
    final entries = await ref
        .read(aiProjectFilesProvider)
        .list(_pane!.state.cwd, dir);
    if (mounted) setState(() => _children[dir] = entries);
  }

  void _toggle(AiDirEntry folder) {
    final path = folder.path;
    if (_open.remove(path)) {
      setState(() {});
      return;
    }
    setState(() => _open.add(path));
    if (!_children.containsKey(path)) unawaited(_load(path));
  }

  List<_Row> _rows() {
    final out = <_Row>[];
    void walk(String dir, int depth) {
      for (final e in _children[dir] ?? const <AiDirEntry>[]) {
        out.add((entry: e, depth: depth));
        if (e.dir && _open.contains(e.path)) walk(e.path, depth + 1);
      }
    }

    walk('', 0);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = _rows();
    final dim = ShellxText.caption.copyWith(
      color: ShellxDesktopColors.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(ShellxSpace.s8),
          child: Text(l10n.aiFilesNote, style: dim),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemExtent: 24,
            itemBuilder: (context, i) {
              final (:entry, :depth) = rows[i];
              final mark = switch (_changed[entry.path]) {
                ChangeKind.modified => 'M',
                ChangeKind.added => 'A',
                _ => null,
              };
              return InkWell(
                key: ValueKey('ai.file.${entry.path}'),
                onTap: entry.dir
                    ? () => _toggle(entry)
                    : () => _pane!.ui.showOverlay(
                        AiFileViewer(
                          key: ValueKey('ai.viewer.${entry.path}'),
                          path: entry.path,
                        ),
                      ),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: ShellxSpace.s8 + depth * 12.0,
                    right: ShellxSpace.s8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        entry.dir
                            ? (_open.contains(entry.path)
                                  ? Icons.expand_more
                                  : Icons.chevron_right)
                            : Icons.description_outlined,
                        size: 14,
                        color: ShellxDesktopColors.textSecondary,
                      ),
                      const SizedBox(width: ShellxSpace.s4),
                      Expanded(
                        child: Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShellxText.small.copyWith(
                            color: entry.ignored
                                ? ShellxDesktopColors.textSecondary
                                : ShellxDesktopColors.textPrimary,
                          ),
                        ),
                      ),
                      if (mark != null)
                        Text(
                          mark,
                          style: ShellxText.caption.copyWith(
                            color: mark == 'A'
                                ? ShellxDesktopColors.ok
                                : ShellxDesktopColors.warn,
                          ),
                        )
                      else if (entry.ignored)
                        Text(l10n.aiIgnored, style: dim),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
