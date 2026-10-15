import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../l10n/app_localizations.dart';
import '../../browser/browser_engine.dart';
import '../../terminal/sidebar_workspaces.dart';
import '../../terminal/terminal_tabs.dart';
import '../../tools/tool_entry.dart';
import '../../tools/tool_ports.dart';
import '../../tools/tool_registry.dart';
import '../theme/shellx_desktop_theme.dart';

/// What the tool dialog gives back (§4.2).
final class ToolDraft {
  const ToolDraft({required this.name, required this.url, required this.phone});
  final String name;
  final String url;
  final bool phone;

  @override
  String toString() => 'ToolDraft(…)';
}

/// §4.2: "Add tool" for workspace [ws], or "Edit tool" for [existing].
/// Null when cancelled.
Future<ToolDraft?> showToolDialog(
  BuildContext context, {
  required String ws,
  ToolEntry? existing,
}) => showDialog<ToolDraft>(
  context: context,
  builder: (_) => ToolDialog(ws: ws, existing: existing),
);

/// D1 errors, in the dialog's words.
String toolUrlErrorText(AppLocalizations l10n, ToolUrlError error) =>
    switch (error) {
      ToolUrlError.notHttp => l10n.toolUrlNotHttp,
      ToolUrlError.userinfo => l10n.toolUrlUserinfo,
      ToolUrlError.backslash => l10n.toolUrlBackslash,
      ToolUrlError.noHost => l10n.toolUrlNoHost,
      ToolUrlError.badPort => l10n.toolUrlBadPort,
      ToolUrlError.tooLong => l10n.toolUrlTooLong,
    };

class ToolDialog extends ConsumerStatefulWidget {
  const ToolDialog({super.key, required this.ws, this.existing});
  final String ws;
  final ToolEntry? existing;

  @override
  ConsumerState<ToolDialog> createState() => _ToolDialogState();
}

class _ToolDialogState extends ConsumerState<ToolDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _url = TextEditingController(text: widget.existing?.url ?? '');
  late bool _phone = widget.existing?.phone ?? false;

  /// The URL error shows once Add was pressed, then follows the typing.
  bool _checked = false;

  bool get _adding => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _url.addListener(_changed);
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  ToolUrlResult get _parsed => parseToolUrl(_url.text);

  /// D15: only an http tool on this computer may open on a phone.
  bool get _phoneAllowed => switch (_parsed) {
    ToolUrlOk(:final url) => ToolEntry(
      id: '',
      ws: '',
      name: '',
      url: url,
    ).phoneAllowed,
    ToolUrlBad() => false,
  };

  bool get _full =>
      _adding &&
      ref.read(toolRegistryProvider.notifier).inWorkspace(widget.ws).length >=
          kMaxToolsPerWorkspace;

  void _pick(ToolPortSuggestion s) {
    _url.text = s.url;
    if (_name.text.trim().isEmpty) {
      final root = ref
          .read(sidebarWorkspacesProvider)
          .workspace(widget.ws)
          ?.root;
      final folder = root == null ? '' : p.basename(root);
      _name.text = folder.isNotEmpty ? folder : s.process;
    }
  }

  void _save() {
    setState(() => _checked = true);
    if (_full || _parsed is! ToolUrlOk) return;
    Navigator.of(context).pop(
      ToolDraft(
        name: _name.text,
        url: _url.text,
        phone: _phone && _phoneAllowed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final parsed = _parsed;
    final error = _checked && parsed is ToolUrlBad
        ? toolUrlErrorText(l10n, parsed.error)
        : null;
    return AlertDialog(
      key: const Key('tool.dialog'),
      title: Text(_adding ? l10n.toolDialogAddTitle : l10n.toolDialogEditTitle),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('tool.dialog.name'),
              controller: _name,
              autofocus: true,
              maxLength: kMaxToolNameLength,
              decoration: InputDecoration(
                labelText: l10n.toolDialogName,
                hintText: l10n.toolDialogNameHint,
                counterText: '',
                isDense: true,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: ShellxSpace.s12),
            TextField(
              key: const Key('tool.dialog.url'),
              controller: _url,
              decoration: InputDecoration(
                labelText: l10n.toolDialogUrl,
                hintText: l10n.toolDialogUrlHint,
                errorText: error,
                errorMaxLines: 2,
                isDense: true,
              ),
              onSubmitted: (_) => _save(),
            ),
            if (_adding) ...[
              const SizedBox(height: ShellxSpace.s12),
              _Suggestions(ws: widget.ws, onPick: _pick),
            ],
            const SizedBox(height: ShellxSpace.s8),
            Tooltip(
              message: _phoneAllowed ? '' : l10n.toolPhoneOnlyLocal,
              child: CheckboxListTile(
                key: const Key('tool.dialog.phone'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: _phone && _phoneAllowed,
                onChanged: _phoneAllowed
                    ? (on) => setState(() => _phone = on ?? false)
                    : null,
                title: Text(l10n.toolDialogPhone),
                subtitle: Text(
                  _phoneAllowed
                      ? l10n.toolDialogPhoneNote
                      : l10n.toolPhoneOnlyLocal,
                  style: ShellxText.caption.copyWith(
                    color: ShellxDesktopColors.textSecondary,
                  ),
                ),
              ),
            ),
            if (_full)
              Text(
                l10n.toolLimitReached(kMaxToolsPerWorkspace),
                key: const Key('tool.dialog.full'),
                style: ShellxText.small.copyWith(
                  color: ShellxDesktopColors.err,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('tool.dialog.cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          key: const Key('tool.dialog.save'),
          onPressed: _full ? null : _save,
          child: Text(_adding ? l10n.toolDialogAdd : l10n.toolDialogSave),
        ),
      ],
    );
  }
}

/// D12: "Running ports ShellX can see:" — the panes' ports at once, the
/// agents' servers and the names when the scan is back (≤ 2 s).
class _Suggestions extends ConsumerWidget {
  const _Suggestions({required this.ws, required this.onPick});
  final String ws;
  final void Function(ToolPortSuggestion suggestion) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scanned = ref.watch(toolPortSuggestionsProvider(ws));
    final list =
        scanned.value ??
        toolPortSuggestions(
          panePorts: workspacePanePorts(
            ref.read(terminalTabsProvider),
            ref.read(sidebarWorkspacesProvider),
            ws,
          ),
          usedPorts: const {},
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.toolSuggestionsTitle,
          style: ShellxText.small.copyWith(
            color: ShellxDesktopColors.textSecondary,
          ),
        ),
        const SizedBox(height: ShellxSpace.s6),
        if (list.isEmpty && !scanned.isLoading)
          Text(
            l10n.toolSuggestionsNone,
            key: const Key('tool.suggestions.none'),
            style: ShellxText.caption.copyWith(
              color: ShellxDesktopColors.textSecondary,
            ),
          )
        else
          Wrap(
            spacing: ShellxSpace.s6,
            runSpacing: ShellxSpace.s6,
            children: [
              for (final s in list)
                ActionChip(
                  key: Key('tool.suggestion.${s.port}'),
                  label: Text(
                    s.process.isEmpty
                        ? 'localhost:${s.port}'
                        : l10n.toolSuggestion(s.port, s.process),
                  ),
                  onPressed: () => onPick(s),
                ),
            ],
          ),
      ],
    );
  }
}

/// D23: "Delete the tool …?" through the window's confirm.
String toolDeleteQuestion(AppLocalizations l10n, ToolEntry tool) =>
    l10n.toolDeleteConfirm(tool.name);

/// D9: a page's alert / confirm / prompt, titled with the tool's name so a
/// page cannot pass for ShellX. The page's text is clipped, never logged.
Future<Object?> showToolJsDialog(
  BuildContext context,
  String toolName,
  BrowserJsDialog dialog,
) => showDialog<Object?>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ToolJsDialog(name: toolName, dialog: dialog),
);

class _ToolJsDialog extends StatefulWidget {
  const _ToolJsDialog({required this.name, required this.dialog});
  final String name;
  final BrowserJsDialog dialog;

  @override
  State<_ToolJsDialog> createState() => _ToolJsDialogState();
}

class _ToolJsDialogState extends State<_ToolJsDialog> {
  late final _text = TextEditingController(
    text: widget.dialog.defaultText ?? '',
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kind = widget.dialog.kind;
    final message = widget.dialog.message;
    final shown = message.length > 2000
        ? '${message.substring(0, 2000)}…'
        : message;
    Object? cancel() => switch (kind) {
      BrowserJsDialogKind.alert => null,
      BrowserJsDialogKind.confirm => false,
      BrowserJsDialogKind.prompt => null,
    };
    Object? ok() => switch (kind) {
      BrowserJsDialogKind.alert => null,
      BrowserJsDialogKind.confirm => true,
      BrowserJsDialogKind.prompt => _text.text,
    };
    return AlertDialog(
      key: const Key('tool.js'),
      title: Text(l10n.toolJsAlertTitle(widget.name)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(child: SelectableText(shown)),
            ),
            if (kind == BrowserJsDialogKind.prompt) ...[
              const SizedBox(height: ShellxSpace.s12),
              TextField(
                key: const Key('tool.js.text'),
                controller: _text,
                autofocus: true,
                onSubmitted: (_) => Navigator.of(context).pop(ok()),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (kind != BrowserJsDialogKind.alert)
          TextButton(
            key: const Key('tool.js.cancel'),
            onPressed: () => Navigator.of(context).pop(cancel()),
            child: Text(l10n.actionCancel),
          ),
        FilledButton(
          key: const Key('tool.js.ok'),
          autofocus: kind != BrowserJsDialogKind.prompt,
          onPressed: () => Navigator.of(context).pop(ok()),
          child: Text(l10n.toolOk),
        ),
      ],
    );
  }
}
