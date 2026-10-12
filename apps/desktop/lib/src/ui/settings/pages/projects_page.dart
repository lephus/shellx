import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../terminal/sidebar_workspaces.dart';
import '../../theme/shellx_desktop_theme.dart';
import 'page_parts.dart';

/// Projects (cmux gap 36): a prominent place to create, name and fold the
/// terminal groups that the sidebar otherwise manages only through
/// right-click menus — and to give each group a folder its new local tabs
/// start in. A "project" here is a sidebar workspace.
class ProjectsPage extends ConsumerWidget {
  const ProjectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(sidebarWorkspacesProvider);
    final notifier = ref.read(sidebarWorkspacesProvider.notifier);
    return PageFrame(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Text(
            l10n.settingsProjectsIntro,
            style: ShellxText.small.copyWith(
              color: ShellxDesktopColors.textSecondary,
            ),
          ),
        ),
        ActionRow(
          key: const Key('settings.projects.new'),
          label: l10n.settingsProjectsNew,
          button: l10n.settingsProjectsNew,
          onPressed: () => notifier.createFor(),
        ),
        for (final w in state.workspaces)
          _ProjectCard(
            key: ValueKey('settings.project.${w.id}'),
            workspace: w,
            name: w.displayName(l10n),
            tabCount: state.tabsOf(w.id).length,
          ),
      ],
    );
  }
}

/// One project: its name, its folder, a tab count, and (not for Default) a
/// delete button. Text commits when the field loses focus or on Enter;
/// external changes reflect in only while the field is not being edited.
class _ProjectCard extends ConsumerStatefulWidget {
  const _ProjectCard({
    super.key,
    required this.workspace,
    required this.name,
    required this.tabCount,
  });

  final Workspace workspace;
  final String name;
  final int tabCount;

  @override
  ConsumerState<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends ConsumerState<_ProjectCard> {
  late final TextEditingController _name = TextEditingController(
    text: widget.name,
  );
  late final TextEditingController _root = TextEditingController(
    text: widget.workspace.root ?? '',
  );
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _rootFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) _commitName();
    });
    _rootFocus.addListener(() {
      if (!_rootFocus.hasFocus) _commitRoot();
    });
  }

  @override
  void didUpdateWidget(covariant _ProjectCard old) {
    super.didUpdateWidget(old);
    if (!_nameFocus.hasFocus && widget.name != _name.text) {
      _name.text = widget.name;
    }
    final root = widget.workspace.root ?? '';
    if (!_rootFocus.hasFocus && root != _root.text) {
      _root.text = root;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _root.dispose();
    _nameFocus.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  SidebarWorkspaces get _notifier =>
      ref.read(sidebarWorkspacesProvider.notifier);

  // An untouched name is left alone, so Default keeps its localized name
  // (a blank is ignored by [rename] anyway).
  void _commitName() {
    if (_name.text.trim() == widget.name.trim()) return;
    _notifier.rename(widget.workspace.id, _name.text);
  }

  void _commitRoot() => _notifier.setRoot(widget.workspace.id, _root.text);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isSsh = widget.workspace.ssh != null;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ShellxRadius.r8),
        border: Border.all(color: ShellxDesktopColors.borderInput),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  textField: true,
                  label: l10n.settingsProjectName,
                  child: TextField(
                    key: Key('settings.project.${widget.workspace.id}.name'),
                    controller: _name,
                    focusNode: _nameFocus,
                    onSubmitted: (_) => _commitName(),
                    decoration: InputDecoration(
                      labelText: l10n.settingsProjectName,
                      isDense: true,
                    ),
                  ),
                ),
              ),
              if (!widget.workspace.isDefault) ...[
                const SizedBox(width: 12),
                Tooltip(
                  message: l10n.settingsProjectDelete,
                  child: IconButton(
                    key: Key(
                      'settings.project.${widget.workspace.id}.delete',
                    ),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _notifier.delete(widget.workspace.id),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            textField: true,
            label: l10n.settingsProjectFolder,
            child: TextField(
              key: Key('settings.project.${widget.workspace.id}.root'),
              controller: _root,
              focusNode: _rootFocus,
              enabled: !isSsh,
              onSubmitted: (_) => _commitRoot(),
              decoration: InputDecoration(
                labelText: l10n.settingsProjectFolder,
                hintText: l10n.settingsProjectFolderHint,
                helperText: isSsh ? null : l10n.settingsProjectFolderEmpty,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.settingsProjectTabCount(widget.tabCount),
            style: ShellxText.caption.copyWith(
              color: ShellxDesktopColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
