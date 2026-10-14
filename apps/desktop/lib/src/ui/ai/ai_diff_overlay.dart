import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_off_thread.dart';
import '../../ai/ai_project_files.dart';
import '../../ai/line_diff.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_diff_view.dart';
import 'ai_editor.dart';
import 'ai_scope.dart';

/// A changed file's diff over the conversation (§4.1 overlay, §4.4): the
/// file before turn [turn] (or before the session: [session]) against the
/// disk now. Binary and over-1-MiB files say so instead. Esc or × closes it.
class AiDiffOverlay extends ConsumerStatefulWidget {
  const AiDiffOverlay({
    super.key,
    required this.path,
    required this.turn,
    required this.session,
  });

  /// Relative to the session folder.
  final String path;
  final int turn;
  final bool session;

  @override
  ConsumerState<AiDiffOverlay> createState() => _AiDiffOverlayState();
}

class _AiDiffOverlayState extends ConsumerState<AiDiffOverlay> {
  List<DiffLine?>? _lines;
  String? _note;
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_load(AiPaneScope.of(context)));
  }

  Future<void> _load(AiPaneScope pane) async {
    final l10n = AppLocalizations.of(context);
    final before = aiFileContentOf(
      await pane.runtime.fileBefore(widget.turn, widget.path),
    );
    // Closed while the restore point was read (Esc, ×, the tab): `ref` and
    // `setState` are gone with the widget.
    if (!mounted) return;
    final now = await ref
        .read(aiProjectFilesProvider)
        .read(p.join(pane.state.cwd, widget.path));
    if (!mounted) return;
    if (before is AiFileBinary || now is AiFileBinary) {
      setState(() => _note = l10n.aiBinaryFile);
      return;
    }
    if (before is AiFileTooLarge || now is AiFileTooLarge) {
      setState(() => _note = l10n.aiFileTooLarge);
      return;
    }
    final lines = await lineDiff(
      ref.read(aiOffThreadProvider),
      before is AiFileText ? before.text : '',
      now is AiFileText ? now.text : '',
    );
    if (mounted) setState(() => _lines = withContext(lines));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pane = AiPaneScope.of(context);
    final lines = _lines;
    final note = _note;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): pane.ui.closeOverlay,
      },
      child: Focus(
        autofocus: true,
        child: Container(
          key: const Key('ai.diff'),
          margin: const EdgeInsets.all(ShellxSpace.s16),
          padding: const EdgeInsets.all(ShellxSpace.s12),
          decoration: BoxDecoration(
            color: ShellxDesktopColors.surface,
            borderRadius: BorderRadius.circular(ShellxRadius.r8),
            border: Border.all(color: ShellxDesktopColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellxText.bodyStrong.copyWith(
                        color: ShellxDesktopColors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => unawaited(
                      aiOpenInEditor(ref, widget.path, pane.state.cwd),
                    ),
                    child: Text(l10n.aiOpenInEditor),
                  ),
                  IconButton(
                    key: const Key('ai.diff.close'),
                    tooltip: l10n.actionClose,
                    iconSize: 16,
                    onPressed: pane.ui.closeOverlay,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                widget.session ? l10n.aiVsSessionStart : l10n.aiVsTurnStart,
                style: ShellxText.caption.copyWith(
                  color: ShellxDesktopColors.textSecondary,
                ),
              ),
              const SizedBox(height: ShellxSpace.s8),
              Expanded(
                child: note != null
                    ? Text(
                        note,
                        key: const Key('ai.diff.note'),
                        style: ShellxText.body.copyWith(
                          color: ShellxDesktopColors.textSecondary,
                        ),
                      )
                    : lines == null
                    ? const SizedBox.shrink()
                    : LayoutBuilder(
                        builder: (context, box) => SingleChildScrollView(
                          child: AiDiffView(
                            lines: lines,
                            height: box.maxHeight,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
