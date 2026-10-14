import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_folders.dart';
import '../../terminal/local_sessions_provider.dart' show homeDirectoryProvider;
import '../text_editing_shortcuts.dart';
import '../theme/shellx_desktop_theme.dart';

/// D5 "Choose a project folder" (ruling B7: a typed path, as Settings ›
/// Projects takes one): absolute, `~` allowed, and it must exist. Over a
/// conversation (§6 "folder gone") it can be cancelled — "Cancel" or Esc —
/// and the conversation is as it was.
class AiFolderCard extends ConsumerStatefulWidget {
  const AiFolderCard({
    super.key,
    required this.onChosen,
    this.onCancel,
    this.initial,
    this.focusNode,
  });

  final void Function(String folder) onChosen;

  /// Null: there is nothing to go back to (a pane that never had a folder).
  final VoidCallback? onCancel;
  final String? initial;
  final FocusNode? focusNode;

  @override
  ConsumerState<AiFolderCard> createState() => _AiFolderCardState();
}

class _AiFolderCardState extends ConsumerState<AiFolderCard> {
  late final _text = TextEditingController(text: widget.initial ?? '');
  var _invalid = false;
  var _checking = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _use() async {
    final folder = aiFolderFrom(
      _text.text,
      home: ref.read(homeDirectoryProvider),
    );
    setState(() => _checking = true);
    final ok = folder != null && await ref.read(aiFolderExistsProvider)(folder);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _invalid = !ok;
    });
    if (ok) widget.onChosen(folder);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onCancel = widget.onCancel;
    Widget field = Shortcuts(
      shortcuts: textEditingShortcuts(),
      child: TextField(
        key: const Key('ai.folder.field'),
        controller: _text,
        focusNode: widget.focusNode,
        autofocus: widget.focusNode == null,
        onSubmitted: (_) => unawaited(_use()),
        decoration: InputDecoration(
          labelText: l10n.aiFolderField,
          hintText: '~/code/project',
          errorText: _invalid ? l10n.aiFolderInvalid : null,
        ),
      ),
    );
    if (onCancel != null) {
      field = CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): onCancel},
        child: field,
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(ShellxSpace.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.aiChooseFolderTitle,
                style: ShellxText.emptyTitle.copyWith(
                  color: ShellxDesktopColors.textTitle,
                ),
              ),
              const SizedBox(height: ShellxSpace.s4),
              Text(
                l10n.aiChooseFolderBody,
                style: ShellxText.body.copyWith(
                  color: ShellxDesktopColors.textSecondary,
                ),
              ),
              const SizedBox(height: ShellxSpace.s16),
              field,
              const SizedBox(height: ShellxSpace.s12),
              Row(
                children: [
                  if (onCancel != null) ...[
                    TextButton(
                      key: const Key('ai.folder.cancel'),
                      onPressed: onCancel,
                      child: Text(l10n.actionCancel),
                    ),
                    const SizedBox(width: ShellxSpace.s8),
                  ],
                  FilledButton(
                    key: const Key('ai.folder.use'),
                    onPressed: _checking ? null : () => unawaited(_use()),
                    child: Text(l10n.aiFolderUse),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
