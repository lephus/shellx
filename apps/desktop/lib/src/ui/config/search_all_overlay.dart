import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/global_search.dart';
import '../../terminal/terminal_tabs.dart';
import '../text_editing_shortcuts.dart';
import '../theme/shellx_desktop_theme.dart';

/// How long typing settles before a search starts (A11 D21).
const Duration kSearchAllDebounce = Duration(milliseconds: 150);

/// A11 D21: the panes to search — every pane of every tab, the selected
/// tab first, each tab's panes in reading order.
List<PaneSource> searchAllSources(TerminalTabsState state) {
  final tabs = [
    ?state.selected,
    for (final t in state.tabs)
      if (t.id != state.selectedId) t,
  ];
  return [
    for (final tab in tabs)
      for (final id in tab.paneOrder)
        PaneSource(
          tabId: tab.id,
          paneId: id,
          tabLabel: tab.label,
          paneNumber: tab.paneNumber(id),
          terminal: tab.panes[id]!.terminal,
        ),
  ];
}

/// UI-A11 D21: the ⌘⇧F overlay — a search field over a list of matches from
/// every open terminal. Chrome and keys as the command palette's: the field
/// keeps the keyboard, ↑/↓ move through the list, Enter or a click opens the
/// match, Esc closes. The search runs in slices between event-loop turns, so
/// the window stays responsive on any scrollback; the snippets live in this
/// widget only and go when it closes.
class SearchAllOverlay extends ConsumerStatefulWidget {
  const SearchAllOverlay({
    super.key,
    required this.onOpen,
    required this.onClose,
  });

  /// A match was chosen: the window selects its pane and opens the find bar
  /// with [query].
  final void Function(GlobalHit hit, String query) onOpen;
  final VoidCallback onClose;

  @override
  ConsumerState<SearchAllOverlay> createState() => _SearchAllOverlayState();
}

/// A slice of the search repaints the list only when it found something new
/// or the search is over (A11 final review): a long scan is not 120 rebuilds
/// a second.
bool searchAllNeedsRepaint({
  required int shownHits,
  required int hits,
  required bool done,
}) => done || hits != shownHits;

/// Counts the repaints the slices asked for (tests).
@visibleForTesting
int searchAllRepaints = 0;

class _SearchAllOverlayState extends ConsumerState<SearchAllOverlay> {
  final _query = TextEditingController();
  final _field = FocusNode(debugLabel: 'searchall field');
  final _scroll = ScrollController();
  GlobalSearch? _search;
  Set<int> _splitTabs = const {};
  Timer? _debounce;
  Timer? _work;
  Timer? _announce;
  int _cursor = 0;
  int _shownHits = 0;
  String _text = '';

  static const double _rowHeight = 48;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _field.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _work?.cancel();
    _announce?.cancel();
    _search?.dispose();
    _query.dispose();
    _field.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<GlobalHit> get _hits => _search?.hits ?? const [];

  void _changed(String text) {
    _debounce?.cancel();
    _work?.cancel();
    _search?.dispose();
    setState(() {
      _search = null;
      _shownHits = 0;
      _text = text;
      _cursor = 0;
    });
    if (text.length < kGlobalSearchMinQuery) return;
    _debounce = Timer(kSearchAllDebounce, _start);
  }

  void _start() {
    if (!mounted) return;
    final state = ref.read(terminalTabsProvider);
    _splitTabs = {
      for (final t in state.tabs)
        if (t.isSplit) t.id,
    };
    _search = GlobalSearch(searchAllSources(state), _text);
    _pump();
  }

  /// One slice, then back to the event loop (input and frames run between
  /// slices).
  void _pump() {
    _work = null;
    final search = _search;
    if (!mounted || search == null) return;
    final done = search.step();
    if (searchAllNeedsRepaint(
      shownHits: _shownHits,
      hits: search.hits.length,
      done: done,
    )) {
      _shownHits = search.hits.length;
      searchAllRepaints++;
      setState(() {});
    }
    if (done) {
      _announceCount();
    } else {
      _work = Timer(Duration.zero, _pump);
    }
  }

  void _say(String message) {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ),
    );
  }

  void _announceCount() {
    _announce?.cancel();
    _announce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      _say(
        _hits.isEmpty ? l10n.searchAllNone : l10n.searchAllCount(_hits.length),
      );
    });
  }

  void _move(int step, {bool wrap = true}) {
    final n = _hits.length;
    if (n == 0) return;
    final next = wrap ? (_cursor + step) % n : (_cursor + step).clamp(0, n - 1);
    setState(() => _cursor = next);
    if (_scroll.hasClients) {
      final top = next * _rowHeight;
      final bottom = top + _rowHeight;
      final p = _scroll.position;
      if (top < p.pixels) {
        _scroll.jumpTo(top);
      } else if (bottom > p.pixels + p.viewportDimension) {
        _scroll.jumpTo(
          (bottom - p.viewportDimension).clamp(0.0, p.maxScrollExtent),
        );
      }
    }
  }

  void _open(int i) {
    if (i < 0 || i >= _hits.length) return;
    widget.onOpen(_hits[i], _text);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    // While an input method composes the keys are the method's.
    if (_query.value.composing.isValid) return KeyEventResult.ignored;
    final k = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    final ctrlOnly =
        keys.isControlPressed &&
        !keys.isShiftPressed &&
        !keys.isAltPressed &&
        !keys.isMetaPressed;
    final bare =
        !keys.isControlPressed &&
        !keys.isShiftPressed &&
        !keys.isAltPressed &&
        !keys.isMetaPressed;
    if ((bare && k == LogicalKeyboardKey.arrowDown) ||
        (ctrlOnly && k == LogicalKeyboardKey.keyN)) {
      _move(1);
    } else if ((bare && k == LogicalKeyboardKey.arrowUp) ||
        (ctrlOnly && k == LogicalKeyboardKey.keyP)) {
      _move(-1);
    } else if (k == LogicalKeyboardKey.pageDown) {
      _move(8, wrap: false);
    } else if (k == LogicalKeyboardKey.pageUp) {
      _move(-8, wrap: false);
    } else if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter) {
      _open(_cursor);
    } else if (k == LogicalKeyboardKey.escape) {
      widget.onClose();
    } else if (k == LogicalKeyboardKey.tab) {
      // Focus stays in the field.
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  String _location(AppLocalizations l10n, GlobalHit h) => [
    h.tabLabel,
    if (_splitTabs.contains(h.tabId)) l10n.searchAllPane(h.paneNumber),
    // Where the line is now; a line that left the history says so.
    h.liveRow == null ? l10n.searchAllGone : l10n.searchAllLine(h.liveRow! + 1),
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    final search = _search;
    final searched = _text.length >= kGlobalSearchMinQuery;
    final needTwo = _text.isNotEmpty && !searched;
    final none = searched && search != null && search.done && _hits.isEmpty;
    final capped = search != null && search.capped && _hits.isNotEmpty;
    return FocusScope(
      debugLabel: 'searchall',
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: l10n.searchAllTitle,
        child: Container(
          key: const Key('searchall.panel'),
          width: math.min(ShellxSizes.paletteWidth, size.width - 48),
          constraints: BoxConstraints(
            maxHeight: math.min(ShellxSizes.paletteMaxHeight, size.height - 96),
          ),
          padding: const EdgeInsets.all(ShellxSpace.s6),
          decoration: BoxDecoration(
            color: ShellxDesktopColors.surface,
            borderRadius: BorderRadius.circular(ShellxRadius.r8),
            border: Border.all(color: ShellxDesktopColors.border),
            boxShadow: ShellxShadows.e1,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _onKey,
                  child: Shortcuts(
                    shortcuts: textEditingShortcuts(),
                    child: SizedBox(
                      height: ShellxSizes.paletteField,
                      child: Semantics(
                        textField: true,
                        label: l10n.searchAllFieldLabel,
                        child: TextField(
                          key: const Key('searchall.field'),
                          controller: _query,
                          focusNode: _field,
                          autofocus: true,
                          onChanged: _changed,
                          style: ShellxText.body.copyWith(
                            color: ShellxDesktopColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: l10n.searchAllHint,
                            prefixIcon: const Icon(Icons.search, size: 16),
                            filled: true,
                            fillColor: ShellxDesktopColors.surfaceInset,
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: ShellxSpace.s6),
                const Divider(height: 1, color: ShellxDesktopColors.line),
                if (needTwo || none)
                  SizedBox(
                    height: ShellxSizes.paletteRow,
                    child: Center(
                      child: Text(
                        needTwo ? l10n.searchAllNeedTwo : l10n.searchAllNone,
                        style: ShellxText.body.copyWith(
                          color: ShellxDesktopColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                if (_hits.isNotEmpty)
                  Flexible(
                    child: Semantics(
                      role: SemanticsRole.list,
                      container: true,
                      child: ListView.builder(
                        controller: _scroll,
                        shrinkWrap: true,
                        itemCount: _hits.length,
                        itemExtent: _rowHeight,
                        itemBuilder: (context, i) => _row(l10n, i),
                      ),
                    ),
                  ),
                if (capped)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: ShellxSpace.s6,
                      horizontal: 10,
                    ),
                    child: Text(
                      l10n.searchAllCapped(_hits.length),
                      key: const Key('searchall.capped'),
                      style: ShellxText.caption.copyWith(
                        color: ShellxDesktopColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextSpan _snippet(GlobalHit h, TextStyle style) {
    final text = h.snippet;
    final a = h.snippetStart.clamp(0, text.length);
    final b = h.snippetEnd.clamp(a, text.length);
    if (a == b) return TextSpan(text: text, style: style);
    return TextSpan(
      style: style,
      children: [
        TextSpan(text: text.substring(0, a)),
        TextSpan(
          text: text.substring(a, b),
          style: style.copyWith(
            color: ShellxDesktopColors.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        TextSpan(text: text.substring(b)),
      ],
    );
  }

  Widget _row(AppLocalizations l10n, int i) {
    final h = _hits[i];
    final selected = i == _cursor;
    final where = _location(l10n, h);
    return Semantics(
      key: ValueKey('searchall.row.$i'),
      button: true,
      selected: selected,
      label: '$where, ${h.snippet}',
      excludeSemantics: true,
      onTap: () => _open(i),
      child: InkWell(
        onTap: () => _open(i),
        canRequestFocus: false, // the field keeps the keyboard
        borderRadius: BorderRadius.circular(ShellxRadius.r6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? ShellxDesktopColors.rowSelected : null,
            borderRadius: BorderRadius.circular(ShellxRadius.r6),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                where,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ShellxText.small.copyWith(
                  color: ShellxDesktopColors.textSecondary,
                ),
              ),
              Text.rich(
                _snippet(
                  h,
                  ShellxText.body.copyWith(
                    color: ShellxDesktopColors.textPrimary,
                  ),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
