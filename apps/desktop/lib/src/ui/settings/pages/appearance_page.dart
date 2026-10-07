import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../config/config_controller.dart';
import '../../../config/settings_schema.dart';
import '../../../config/shellx_config.dart' show TerminalFontWeight;
import '../../../config/theme_listing.dart';
import '../../../terminal/terminal_style.dart'
    show kTerminalFontSizeMax, kTerminalFontSizeMin;
import '../../theme/shellx_desktop_theme.dart';
import '../preview_terminal.dart';
import '../settings_preview.dart';
import '../settings_row.dart';
import 'page_parts.dart';

/// Appearance: a real terminal sample on top, the theme list, font, size,
/// weight, line height, padding, cursor and colors. Theme, size, weight and
/// line height show in the sample while the user hovers, focuses or drags
/// (never written, never in a real pane); a click, Enter or release writes.
/// Leaving the page, Esc and every write end the preview.
class AppearancePage extends ConsumerStatefulWidget {
  const AppearancePage({super.key});

  @override
  ConsumerState<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends ConsumerState<AppearancePage> {
  // Kept in a field: `ref` can't be read while the widget is taken apart.
  late final SettingsPreview _preview;

  @override
  void initState() {
    super.initState();
    _preview = ref.read(settingsPreviewProvider.notifier);
    // A load (our own write, a hand edit) is the truth now.
    ref.listenManual(
      shellxConfigProvider.select((s) => s.generation),
      (_, _) => _preview.clear(),
    );
  }

  @override
  void dispose() {
    // Not while the tree is being taken apart (Riverpod forbids provider
    // writes then); the container may already be gone with the window.
    final preview = _preview;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        preview.clear();
      } on Object {
        // The provider scope was disposed first: nothing left to clear.
      }
    });
    super.dispose();
  }

  void _onPreview(SettingDef def, String? raw) {
    if (raw == null) return _preview.clear();
    final value = double.tryParse(raw);
    switch (def.id) {
      case 'font-size':
        if (value != null) {
          _preview.preview(
            fontSize: value.clamp(kTerminalFontSizeMin, kTerminalFontSizeMax),
          );
        }
      case 'adjust-cell-height':
        if (value != null) {
          _preview.preview(cellHeightPercent: value.clamp(-10, 50).toDouble());
        }
      case 'font-weight':
        final weight = TerminalFontWeight.values
            .where((w) => w.name == raw)
            .firstOrNull;
        if (weight != null) _preview.preview(weight: weight);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      scroll: false,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: PreviewTerminal(key: Key('preview.terminal')),
        ),
        Expanded(
          child: ListView(
            key: const Key('settings.appearance.list'),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            children: [
              for (final def in kSettings)
                if (def.page == SettingPage.appearance)
                  def.id == 'theme'
                      ? SettingRow(
                          key: const ValueKey('row.theme'),
                          def: def,
                          control: (context, api) => _ThemeList(api: api),
                        )
                      : settingWidget(def, onPreview: _onPreview),
            ],
          ),
        ),
      ],
    );
  }
}

/// A searchable list of the themes on this computer. Moving through it with
/// the arrow keys or the pointer previews a theme; Enter or a click picks it.
class _ThemeList extends ConsumerStatefulWidget {
  const _ThemeList({required this.api});
  final SettingControlApi api;

  @override
  ConsumerState<_ThemeList> createState() => _ThemeListState();
}

class _ThemeListState extends ConsumerState<_ThemeList> {
  final _query = TextEditingController();

  /// The row that has the keyboard: leaving the pointer does not drop its
  /// preview.
  String? _focused;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  SettingsPreview get _preview => ref.read(settingsPreviewProvider.notifier);

  Future<void> _pick(ThemeEntry theme) async {
    await widget.api.commit(theme.name);
    // The sample follows the saved theme now (a refusal ends the preview too).
    if (mounted) _preview.clearTheme();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final themes = ref.watch(themeListProvider);
    final previewing = ref.watch(
      settingsPreviewProvider.select((s) => s?.theme),
    );
    final failed = previewing == null
        ? false
        : ref.watch(previewThemeProvider(previewing)).value?.failed ?? false;
    final current = widget.api.current.toLowerCase();
    final q = _query.text.trim().toLowerCase();
    final entries = [
      for (final e in themes.value ?? const <ThemeEntry>[])
        if (q.isEmpty || e.name.toLowerCase().contains(q)) e,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            l10n.settingsTheme,
            style: ShellxText.body.copyWith(
              color: ShellxDesktopColors.textPrimary,
            ),
          ),
        ),
        SizedBox(
          width: 320,
          child: Semantics(
            textField: true,
            label: l10n.settingsThemeSearch,
            child: TextField(
              key: const Key('settings.theme.search'),
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: l10n.settingsThemeSearch,
                prefixIcon: const Icon(Icons.search, size: 16),
                isDense: true,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: ShellxDesktopColors.surfaceInset,
            borderRadius: BorderRadius.circular(ShellxRadius.r6),
            border: Border.all(color: ShellxDesktopColors.border),
          ),
          child: Semantics(
            container: true,
            label: l10n.settingsTheme,
            child: ListView.builder(
              key: const Key('settings.theme.list'),
              itemCount: entries.length,
              itemExtent: 32,
              itemBuilder: (context, i) {
                final e = entries[i];
                final selected =
                    e.name.toLowerCase() == current ||
                    (e == ThemeEntry.builtIn && current.isEmpty);
                return _ThemeRow(
                  key: Key('theme.row.${e.name}'),
                  entry: e,
                  selected: selected,
                  enabled: widget.api.editable,
                  onPreview: () => _preview.preview(theme: e.name),
                  onFocus: (focused) {
                    if (focused) {
                      _focused = e.name;
                      _preview.preview(theme: e.name);
                    } else if (_focused == e.name) {
                      _focused = null;
                    }
                  },
                  onHoverEnd: () {
                    final keep = _focused;
                    if (keep == null) {
                      _preview.clearTheme();
                    } else {
                      _preview.preview(theme: keep);
                    }
                  },
                  onPick: () => unawaited(_pick(e)),
                );
              },
            ),
          ),
        ),
        if (failed)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Semantics(
              liveRegion: true,
              child: Text(
                l10n.settingsThemeNotFound,
                key: const Key('settings.theme.error'),
                style: ShellxText.small.copyWith(
                  color: ShellxDesktopColors.err,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow({
    super.key,
    required this.entry,
    required this.selected,
    required this.enabled,
    required this.onPreview,
    required this.onFocus,
    required this.onHoverEnd,
    required this.onPick,
  });
  final ThemeEntry entry;
  final bool selected;
  final bool enabled;
  final VoidCallback onPreview;
  final ValueChanged<bool> onFocus;
  final VoidCallback onHoverEnd;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: entry.name,
      excludeSemantics: true,
      onTap: enabled ? onPick : null,
      child: InkWell(
        onTap: enabled ? onPick : null,
        onFocusChange: onFocus,
        onHover: (hovering) => hovering ? onPreview() : onHoverEnd(),
        focusColor: ShellxDesktopColors.rowPressed,
        hoverColor: ShellxDesktopColors.rowHover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: selected
                    ? const Icon(
                        Icons.check,
                        size: 14,
                        color: ShellxDesktopColors.accent,
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ShellxText.body.copyWith(
                    color: ShellxDesktopColors.textPrimary,
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
