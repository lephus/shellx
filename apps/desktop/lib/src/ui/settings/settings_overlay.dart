import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../../config/config_controller.dart';
import '../../config/config_writer.dart' show ConfigWriteRefusal;
import '../../config/settings_schema.dart';
import '../config/config_ui_request.dart';
import '../theme/shellx_desktop_theme.dart';
import 'pages/advanced_page.dart';
import 'pages/agents_page.dart';
import 'pages/appearance_page.dart';
import 'pages/general_page.dart';
import 'pages/keys_page.dart';
import 'pages/page_parts.dart';
import 'pages/phone_page.dart';
import 'pages/terminal_page.dart';
import 'settings_row.dart';
import 'settings_values.dart';
import 'settings_writer.dart';

/// The window stops talking about search results more often than this.
const Duration kSettingsAnnounceEvery = Duration(milliseconds: 500);

/// How long a row a search hit jumped to stays lit.
const Duration kSettingsHighlight = Duration(seconds: 1);

const double _kWide = 880, _kTall = 600, _kNav = 200;

/// A11 D3: Settings, one overlay in the main window (focus trapped, Esc
/// closes, the keyboard goes back to where it was). Seven pages, a search
/// over all of them, rows that write the configuration file only when the
/// user acts. Nothing is written by opening it or visiting a page.
class SettingsOverlay extends ConsumerStatefulWidget {
  const SettingsOverlay({
    super.key,
    required this.onClose,
    required this.onOpenFile,
  });
  final VoidCallback onClose;
  final VoidCallback onOpenFile;

  @override
  ConsumerState<SettingsOverlay> createState() => _SettingsOverlayState();
}

class _SettingsOverlayState extends ConsumerState<SettingsOverlay> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'settings search');
  SettingPage _page = SettingPage.general;
  String _query = '';
  String? _highlight;
  Timer? _highlightTimer;

  /// The result count the screen reader hears; changes at most once per
  /// [kSettingsAnnounceEvery].
  String _announcement = '';
  Timer? _announceLock;
  bool _announceDirty = false;

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _announceLock?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool get _mac => ref.read(configPlatformProvider) == TargetPlatform.macOS;

  List<SettingDef> _hits(AppLocalizations l10n) {
    final platform = ref.read(configPlatformProvider);
    return [
      for (final d in searchSettings(_query, l10n))
        if (d.onlyOn == null || d.onlyOn == platform) d,
    ];
  }

  void _onQuery(String value) {
    setState(() => _query = value);
    _scheduleAnnounce();
  }

  void _scheduleAnnounce() {
    if (_announceLock != null) {
      _announceDirty = true;
      return;
    }
    final l10n = AppLocalizations.of(context);
    final query = _query.trim();
    setState(() {
      _announcement = query.isEmpty
          ? ''
          : (_hits(l10n).isEmpty
                ? l10n.settingsNoMatch(query)
                : l10n.settingsResultCount(_hits(l10n).length));
    });
    _announceLock = Timer(kSettingsAnnounceEvery, () {
      _announceLock = null;
      if (_announceDirty && mounted) {
        _announceDirty = false;
        _scheduleAnnounce();
      }
    });
  }

  void _open(SettingPage page, {String? highlight}) {
    _highlightTimer?.cancel();
    setState(() {
      _page = page;
      _query = '';
      _search.clear();
      _announcement = '';
      _highlight = highlight;
    });
    if (highlight != null) {
      _highlightTimer = Timer(kSettingsHighlight, () {
        if (mounted) setState(() => _highlight = null);
      });
    }
  }

  void _showProblems() => ref
      .read(configUiRequestProvider.notifier)
      .request(ConfigUiRequest.problems);

  /// Esc while an input method composes belongs to the input method; `/`
  /// outside a text field jumps to the search (D7).
  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      final composing = _search.value.composing;
      if (composing.isValid && !composing.isCollapsed) {
        return KeyEventResult.skipRemainingHandlers;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onOverlayKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.slash ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final inField =
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>() !=
        null;
    if (inField) return KeyEventResult.ignored;
    _searchFocus.requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 640;
    final searching = _query.trim().isNotEmpty;
    final mac = _mac;
    return SettingsScope(
      onOpenFile: widget.onOpenFile,
      onClose: widget.onClose,
      highlightId: _highlight,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: l10n.settingsTitle,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
            SingleActivator(LogicalKeyboardKey.keyF, meta: mac, control: !mac):
                _searchFocus.requestFocus,
          },
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onOverlayKey,
            child: FocusScope(
              autofocus: true,
              child: Container(
                width: math.min(_kWide, size.width - 48),
                height: math.min(_kTall, size.height - 64),
                decoration: BoxDecoration(
                  color: ShellxDesktopColors.surface,
                  borderRadius: BorderRadius.circular(ShellxRadius.r12),
                  border: Border.all(color: ShellxDesktopColors.border),
                  boxShadow: ShellxShadows.e1,
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(l10n),
                      const Divider(height: 1, color: ShellxDesktopColors.line),
                      Expanded(
                        child: compact
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _searchField(l10n),
                                  _tabStrip(l10n),
                                  Expanded(child: _body(l10n, searching)),
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    width: _kNav,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _searchField(l10n),
                                        Expanded(child: _nav(l10n)),
                                      ],
                                    ),
                                  ),
                                  const VerticalDivider(
                                    width: 1,
                                    color: ShellxDesktopColors.line,
                                  ),
                                  Expanded(child: _body(l10n, searching)),
                                ],
                              ),
                      ),
                      const Divider(height: 1, color: ShellxDesktopColors.line),
                      _footer(l10n),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              l10n.settingsTitle,
              style: ShellxText.bodyStrong.copyWith(
                color: ShellxDesktopColors.textPrimary,
              ),
            ),
          ),
        ),
        IconButton(
          key: const Key('settings.close'),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const Icon(Icons.close, size: 16),
          onPressed: widget.onClose,
        ),
      ],
    ),
  );

  Widget _searchField(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.all(8),
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onSearchKey,
      child: Semantics(
        textField: true,
        label: l10n.settingsSearch,
        child: TextField(
          key: const Key('settings.search'),
          controller: _search,
          focusNode: _searchFocus,
          autofocus: true,
          onChanged: _onQuery,
          decoration: InputDecoration(
            hintText: l10n.settingsSearch,
            prefixIcon: const Icon(Icons.search, size: 16),
            isDense: true,
          ),
        ),
      ),
    ),
  );

  String _pageLabel(AppLocalizations l10n, SettingPage page) =>
      settingPageLabel(page, l10n);

  Widget _nav(AppLocalizations l10n) => Semantics(
    container: true,
    label: l10n.settingsPageNavLabel,
    child: ListView(
      children: [
        for (final page in SettingPage.values)
          _NavItem(
            key: Key('settings.page.${page.name}'),
            label: _pageLabel(l10n, page),
            selected: !_searching && page == _page,
            onTap: () => _open(page),
          ),
      ],
    ),
  );

  bool get _searching => _query.trim().isNotEmpty;

  Widget _tabStrip(AppLocalizations l10n) => SizedBox(
    height: 40,
    child: Semantics(
      container: true,
      label: l10n.settingsPageNavLabel,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final page in SettingPage.values)
            _NavItem(
              key: Key('settings.page.${page.name}'),
              label: _pageLabel(l10n, page),
              selected: !_searching && page == _page,
              onTap: () => _open(page),
              horizontal: true,
            ),
        ],
      ),
    ),
  );

  Widget _body(AppLocalizations l10n, bool searching) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Heard, not seen: the number of hits (at most every 500 ms).
        Semantics(
          liveRegion: true,
          label: _announcement,
          child: const SizedBox(height: 0),
        ),
        Expanded(child: searching ? _results(l10n) : _pageBody()),
      ],
    );
  }

  Widget _results(AppLocalizations l10n) {
    final hits = _hits(l10n);
    if (hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const Key('settings.no-match'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsNoMatch(_query.trim()),
              style: ShellxText.body.copyWith(
                color: ShellxDesktopColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.settingsNoMatchHint,
              style: ShellxText.small.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('settings.no-match.open-file'),
              onPressed: widget.onOpenFile,
              child: Text(l10n.settingsOpenFile),
            ),
          ],
        ),
      );
    }
    return ListView(
      key: const Key('settings.results'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: [
        for (final d in hits)
          settingWidget(
            d,
            pageCaption: _pageLabel(l10n, d.page),
            onJump: () => _open(d.page, highlight: d.id),
            note: d.id == 'scrollback-limit'
                ? l10n.settingsScrollbackNote
                : null,
            enabled:
                d.page != SettingPage.phone ||
                ref.read(agentControllerProvider).signedIn,
          ),
      ],
    );
  }

  Widget _pageBody() => switch (_page) {
    SettingPage.general => const GeneralPage(),
    SettingPage.appearance => const AppearancePage(),
    SettingPage.terminal => const TerminalPage(),
    SettingPage.keys => const KeysPage(),
    SettingPage.agents => const AgentsPage(),
    SettingPage.phone => const PhonePage(),
    SettingPage.advanced => AdvancedPage(onShowProblems: _showProblems),
  };

  Widget _footer(AppLocalizations l10n) {
    final problems = ref.watch(
      shellxConfigProvider.select((s) => s.visibleProblemCount),
    );
    final status = ref.watch(settingsStatusProvider);
    final statusText = switch (status) {
      Changed() => l10n.settingsFileChanged,
      Refused(:final why) when why == ConfigWriteRefusal.damagedBlock =>
        l10n.settingsFileDamaged,
      Refused() => l10n.settingsFileUnwritable,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (statusText != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  statusText,
                  key: const Key('settings.status'),
                  style: ShellxText.small.copyWith(
                    color: status is Changed
                        ? ShellxDesktopColors.textPrimary
                        : ShellxDesktopColors.err,
                  ),
                ),
              ),
            ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              TextButton(
                key: const Key('settings.footer.open-file'),
                onPressed: widget.onOpenFile,
                child: Text(l10n.settingsOpenFile),
              ),
              TextButton(
                key: const Key('settings.footer.reload'),
                onPressed: () => unawaited(
                  ref.read(shellxConfigProvider.notifier).load(manual: true),
                ),
                child: Text(l10n.settingsReload),
              ),
              if (problems > 0)
                TextButton(
                  key: const Key('settings.footer.problems'),
                  onPressed: _showProblems,
                  child: Text(l10n.settingsProblems(problems)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.horizontal = false,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: ShellxText.body.copyWith(
        color: selected
            ? ShellxDesktopColors.textTitle
            : ShellxDesktopColors.textPrimary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        focusColor: ShellxDesktopColors.rowPressed,
        hoverColor: ShellxDesktopColors.rowHover,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: selected ? ShellxDesktopColors.primarySoft : null,
            border: Border(
              left: BorderSide(
                width: 2,
                color: selected
                    ? ShellxDesktopColors.accent
                    : Colors.transparent,
              ),
            ),
          ),
          child: text,
        ),
      ),
    );
  }
}
