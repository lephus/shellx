import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../config/config_controller.dart';
import '../../config/keybind_actions.dart';
import '../terminal/terminal_intents.dart';
import '../text_editing_shortcuts.dart';
import '../theme/shellx_desktop_theme.dart';
import 'action_labels.dart';

final Map<String, String> _fold = {
  for (final (chars, base) in const [
    ('àáạảãâầấậẩẫăằắặẳẵ', 'a'),
    ('èéẹẻẽêềếệểễ', 'e'),
    ('ìíịỉĩ', 'i'),
    ('òóọỏõôồốộổỗơờớợởỡ', 'o'),
    ('ùúụủũưừứựửữ', 'u'),
    ('ỳýỵỷỹ', 'y'),
    ('đ', 'd'),
  ])
    for (final c in chars.split('')) c: base,
};

/// [folded] is the search form of the text; [spans] holds, for each of its
/// characters, the start and end (UTF-16 units) of what it came from in the
/// original, a combining mark that follows included.
typedef _Folded = ({String folded, List<(int, int)> spans});

_Folded _foldWithSpans(String s) {
  final out = StringBuffer();
  final spans = <(int, int)>[];
  var offset = 0;
  for (final rune in s.runes) {
    final length = rune > 0xFFFF ? 2 : 1;
    if (rune >= 0x300 && rune <= 0x36F) {
      // A combining mark: part of the letter before it.
      if (spans.isNotEmpty) {
        spans[spans.length - 1] = (spans.last.$1, offset + length);
      }
    } else {
      for (final lower in String.fromCharCode(rune).toLowerCase().runes) {
        final c = String.fromCharCode(lower);
        if (lower >= 0x300 && lower <= 0x36F) continue;
        out.write(_fold[c] ?? c);
        // One output character per source character (a lower-case form
        // longer than one character maps all of them to the same source).
        for (var k = 0; k < (_fold[c] ?? c).length; k++) {
          spans.add((offset, offset + length));
        }
      }
    }
    offset += length;
  }
  return (folded: out.toString(), spans: spans);
}

/// D33: lower case, Vietnamese marks removed (precomposed or combining).
String foldForSearch(String s) => _foldWithSpans(s).folded;

const _boundaries = ' -/_.';

/// Where [query] matches [text], as positions in the folded text; null for
/// no match. Tiers, best first: prefix, word start (after a space, `-`,
/// `/`, `_` or `.`; every occurrence is looked at), inside, then (only when
/// [subsequence]) scattered letters.
({int score, List<int> at})? _match(
  String query,
  String folded, {
  required bool subsequence,
}) {
  final q = foldForSearch(query.trim());
  if (q.isEmpty) return (score: 0, at: const []);
  List<int> run(int from) => [for (var i = 0; i < q.length; i++) from + i];
  if (folded.startsWith(q)) return (score: 4000, at: run(0));
  var first = -1;
  var from = 0;
  while (true) {
    final i = folded.indexOf(q, from);
    if (i < 0) break;
    if (first < 0) first = i;
    if (i > 0 && _boundaries.contains(folded[i - 1])) {
      return (score: 3000 - math.min(i, 999), at: run(i));
    }
    from = i + 1;
  }
  if (first >= 0) return (score: 2000 - math.min(first, 999), at: run(first));
  if (!subsequence) return null;
  var pos = 0;
  var last = -1;
  var gaps = 0;
  final at = <int>[];
  for (final ch in q.split('')) {
    if (ch == ' ') continue;
    final found = folded.indexOf(ch, pos);
    if (found < 0) return null;
    if (last >= 0) gaps += found - last - 1;
    last = found;
    pos = found + 1;
    at.add(found);
  }
  return (score: 1000 - math.min(gaps, 999), at: at);
}

/// Higher is better; null = no match. The tier alone decides (a longer
/// title is not worse); within a tier an earlier match is better, so a tie
/// in the palette falls through to recency and then to the original order
/// (D33). [subsequence] false: the text must contain the query as written
/// (the text of a command is long; scattered letters would match anything).
int? matchScore(String query, String text, {bool subsequence = true}) =>
    _match(query, foldForSearch(text), subsequence: subsequence)?.score;

/// The matched stretches of [text] as (start, end) in its own UTF-16 units,
/// neighbours merged: what the palette draws in the accent colour. The
/// match is found in the folded text and mapped back, so "chia" marks all
/// of "Chìa", a combining mark included.
List<(int, int)> matchRanges(
  String query,
  String text, {
  bool subsequence = true,
}) {
  final f = _foldWithSpans(text);
  final m = _match(query, f.folded, subsequence: subsequence);
  if (m == null) return const [];
  final ranges = <(int, int)>[];
  for (final i in m.at) {
    final (start, end) = f.spans[i];
    if (ranges.isNotEmpty && ranges.last.$2 >= start) {
      ranges[ranges.length - 1] = (
        ranges.last.$1,
        math.max(end, ranges.last.$2),
      );
    } else {
      ranges.add((start, end));
    }
  }
  return ranges;
}

enum PaletteKind { action, command, snippet, config }

@immutable
final class PaletteEntry {
  const PaletteEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.shortcut,
    required this.intent,
  });

  final String id;
  final String title;
  final String? subtitle;
  final PaletteKind kind;
  final String? shortcut;
  final Intent intent;
}

/// D33: every applicable action (not `goto_tab`, `text`, `csi`, `esc`,
/// `ignore`, `run_command` — those are bindings), then your commands and
/// snippets. [enabled] is the window's own check (inapplicable → hidden).
List<PaletteEntry> paletteEntries({
  required AppLocalizations l10n,
  required ConfigState config,
  required bool Function(Intent intent) enabled,
}) {
  // UI-A9 §2.1 order with an empty query (after the recent ones): the
  // problems entry, the ShellX actions in the groups' order, your
  // commands, your snippets.
  final problems = <PaletteEntry>[];
  final entries = <PaletteEntry>[];
  for (final spec in kActionSpecs.values) {
    if (!spec.inPalette) continue;
    if (spec.scope != KeyScope.window) continue; // browser keys act on a page
    for (final param in actionVariants(spec)) {
      final action = KeyAction(spec.name, param);
      final intent = spec.name == 'select_all'
          ? const SelectAllIntent(fromMenu: true)
          : intentForAction(action);
      if (!enabled(intent)) continue;
      (spec.name == 'show_config_problems' ? problems : entries).add(
        PaletteEntry(
          id: action.text,
          title: actionLabel(l10n, action),
          subtitle: null,
          kind: spec.group == ActionGroup.config
              ? PaletteKind.config
              : PaletteKind.action,
          shortcut: config.bindings.labelOf(action),
          intent: intent,
        ),
      );
    }
  }
  final commands = config.config.commands;
  for (final c in [
    ...commands.where((c) => c.enter),
    ...commands.where((c) => !c.enter),
  ]) {
    entries.add(
      PaletteEntry(
        id: 'command:${c.name}',
        title: c.name,
        subtitle: c.text.replaceAll('\n', '⏎'),
        kind: c.enter ? PaletteKind.command : PaletteKind.snippet,
        shortcut: config.bindings.labelOf(KeyAction('run_command', c.name)),
        intent: RunUserCommandIntent(c.name),
      ),
    );
  }
  return [...problems, ...entries];
}

List<PaletteEntry> filterPalette(
  List<PaletteEntry> entries,
  String query,
  List<String> recent,
) {
  int recency(PaletteEntry e) {
    final i = recent.indexOf(e.id);
    return i < 0 ? recent.length : i;
  }

  if (query.trim().isEmpty) {
    final order = {for (var i = 0; i < entries.length; i++) entries[i]: i};
    return [...entries]..sort((a, b) {
      final r = recency(a).compareTo(recency(b));
      return r != 0 ? r : order[a]!.compareTo(order[b]!);
    });
  }
  final scored = <(PaletteEntry, int, int)>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final title = matchScore(query, e.title);
    final sub = e.subtitle == null
        ? null
        : matchScore(query, e.subtitle!, subsequence: false);
    final score = [
      ?title,
      if (sub != null) sub - 500,
    ].fold<int?>(null, (best, s) => best == null || s > best ? s : best);
    if (score != null) scored.add((e, score, i));
  }
  scored.sort((a, b) {
    final s = b.$2.compareTo(a.$2);
    if (s != 0) return s;
    final r = recency(a.$1).compareTo(recency(b.$1));
    return r != 0 ? r : a.$3.compareTo(b.$3);
  });
  return [for (final s in scored) s.$1];
}

/// UI-A9 §2: the ⌘⇧P overlay. The search field keeps the keyboard (focus
/// trap); the list is driven from it like a combobox, so it is no tab stop.
class CommandPalette extends StatefulWidget {
  const CommandPalette({
    super.key,
    required this.entries,
    required this.recent,
    required this.onRun,
    required this.onClose,
  });

  final List<PaletteEntry> entries;
  final List<String> recent;
  final void Function(PaletteEntry entry) onRun;
  final VoidCallback onClose;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _query = TextEditingController();
  final _field = FocusNode(debugLabel: 'palette search');
  final _scroll = ScrollController();
  late List<PaletteEntry> _results = filterPalette(
    widget.entries,
    '',
    widget.recent,
  );
  int _cursor = 0;
  Timer? _announce;

  @override
  void initState() {
    super.initState();
    // `autofocus` does not move a keyboard that sits in the terminal: the
    // window's scope already has a focused child.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _field.requestFocus();
    });
  }

  /// The entries changed under an open palette (a reload): filter again
  /// with the same query; the cursor stays on the same entry when it is
  /// still listed, else it stays at its place (clamped).
  @override
  void didUpdateWidget(CommandPalette old) {
    super.didUpdateWidget(old);
    if (identical(old.entries, widget.entries)) return;
    final id = _results.isEmpty ? null : _results[_cursor].id;
    final results = filterPalette(widget.entries, _query.text, widget.recent);
    final at = results.indexWhere((e) => e.id == id);
    _results = results;
    _cursor = at >= 0
        ? at
        : results.isEmpty
        ? 0
        : _cursor.clamp(0, results.length - 1);
  }

  @override
  void dispose() {
    _announce?.cancel();
    _query.dispose();
    _field.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// A row's height: 36, or 48 with the command's text; a large text scale
  /// grows it with the lines.
  double _extent(int i) {
    final scaler = MediaQuery.textScalerOf(context);
    final title = scaler.scale(18);
    if (_results[i].subtitle == null) {
      return math.max(ShellxSizes.paletteRow, title + 2 * ShellxSpace.s6);
    }
    return math.max(48, title + scaler.scale(16) + 2 * ShellxSpace.s6);
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

  /// D44: the count is read once after typing settles (at most every
  /// 500 ms), not on every key.
  void _filter(String query) {
    setState(() {
      _results = filterPalette(widget.entries, query, widget.recent);
      _cursor = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _announce?.cancel();
    _announce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      _say(
        _results.isEmpty
            ? l10n.paletteNoResults
            : l10n.paletteResultCount(_results.length),
      );
    });
  }

  String _rowLabel(AppLocalizations l10n, PaletteEntry e) =>
      [e.title, ?_kind(l10n, e.kind), ?e.shortcut].join(', ');

  /// ↑/↓ wrap (a short list, like VS Code); the page keys stop at the ends.
  void _move(int step, {bool wrap = true}) {
    if (_results.isEmpty) return;
    final next = wrap
        ? (_cursor + step) % _results.length
        : (_cursor + step).clamp(0, _results.length - 1);
    setState(() => _cursor = next);
    if (_scroll.hasClients) {
      var top = 0.0;
      for (var i = 0; i < next; i++) {
        top += _extent(i);
      }
      final bottom = top + _extent(next);
      final p = _scroll.position;
      if (top < p.pixels) {
        _scroll.jumpTo(top);
      } else if (bottom > p.pixels + p.viewportDimension) {
        _scroll.jumpTo(
          (bottom - p.viewportDimension).clamp(0.0, p.maxScrollExtent),
        );
      }
    }
    // The keyboard stays in the field, so the entry is read out here.
    _announce?.cancel();
    _say(_rowLabel(AppLocalizations.of(context), _results[next]));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    // While an input method composes (Vietnamese Telex/VNI, CJK) these keys
    // are the method's: Enter commits the word, it never runs an entry.
    if (_query.value.composing.isValid) return KeyEventResult.ignored;
    final k = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    // Ctrl+Shift+P is the palette's own chord on Windows and Linux.
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
      if (_results.isNotEmpty) widget.onRun(_results[_cursor]);
    } else if (k == LogicalKeyboardKey.escape) {
      if (_query.text.isNotEmpty) {
        _query.clear();
        _filter('');
      } else {
        widget.onClose();
      }
    } else if (k == LogicalKeyboardKey.tab) {
      // Focus stays in the field (UI-A9 §2.2).
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  String? _kind(AppLocalizations l10n, PaletteKind kind) => switch (kind) {
    PaletteKind.action => null,
    PaletteKind.command => l10n.paletteKindUserCommand,
    PaletteKind.snippet => l10n.paletteKindSnippet,
    PaletteKind.config => l10n.paletteKindConfig,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    return FocusScope(
      debugLabel: 'palette',
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: l10n.paletteTitle,
        child: Container(
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
                  // ⌘V / Ctrl+Shift+V / ⌘C edit this field: the window's own
                  // shortcuts would paste into the terminal (D7).
                  child: Shortcuts(
                    shortcuts: textEditingShortcuts(),
                    child: SizedBox(
                      height: ShellxSizes.paletteField,
                      // The field's accessible name (UI-A9 §8).
                      child: Semantics(
                        textField: true,
                        label: l10n.paletteSearchLabel,
                        child: TextField(
                          controller: _query,
                          focusNode: _field,
                          autofocus: true,
                          onChanged: _filter,
                          style: ShellxText.body.copyWith(
                            color: ShellxDesktopColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: l10n.paletteSearchHint,
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
                Flexible(
                  child: _results.isEmpty
                      ? SizedBox(
                          height: ShellxSizes.paletteRow,
                          child: Center(
                            child: Text(
                              l10n.paletteNoResults,
                              style: ShellxText.body.copyWith(
                                color: ShellxDesktopColors.textSecondary,
                              ),
                            ),
                          ),
                        )
                      : Semantics(
                          role: SemanticsRole.list,
                          container: true,
                          child: ListView.builder(
                            controller: _scroll,
                            shrinkWrap: true,
                            itemCount: _results.length,
                            itemExtentBuilder: (i, _) => _extent(i),
                            itemBuilder: (context, i) => _row(l10n, i),
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

  /// UI-A9 §2.1: the letters the query matched, accent and semi-bold.
  TextSpan _highlighted(
    String text,
    TextStyle style, {
    bool subsequence = true,
  }) {
    final ranges = matchRanges(_query.text, text, subsequence: subsequence);
    if (ranges.isEmpty) return TextSpan(text: text, style: style);
    final marked = style.copyWith(
      color: ShellxDesktopColors.accent,
      fontWeight: FontWeight.w600,
    );
    final spans = <TextSpan>[];
    var at = 0;
    for (final (start, end) in ranges) {
      if (start > at) spans.add(TextSpan(text: text.substring(at, start)));
      spans.add(TextSpan(text: text.substring(start, end), style: marked));
      at = end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: spans);
  }

  Widget _row(AppLocalizations l10n, int i) {
    final e = _results[i];
    final selected = i == _cursor;
    final kind = _kind(l10n, e.kind);
    return Semantics(
      key: ValueKey('palette.row.$i'),
      button: true,
      selected: selected,
      label: _rowLabel(l10n, e),
      excludeSemantics: true,
      onTap: () => widget.onRun(e),
      child: InkWell(
        onTap: () => widget.onRun(e),
        canRequestFocus: false, // the field keeps the keyboard
        borderRadius: BorderRadius.circular(ShellxRadius.r6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? ShellxDesktopColors.rowSelected : null,
            borderRadius: BorderRadius.circular(ShellxRadius.r6),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      _highlighted(
                        e.title,
                        ShellxText.body.copyWith(
                          color: ShellxDesktopColors.textPrimary,
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (e.subtitle != null)
                      Text.rich(
                        _highlighted(
                          e.subtitle!,
                          ShellxText.small.copyWith(
                            color: ShellxDesktopColors.textSecondary,
                          ),
                          subsequence: false,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (kind != null) ...[
                const SizedBox(width: ShellxSpace.s8),
                Text(
                  kind,
                  style: ShellxText.caption.copyWith(
                    color: ShellxDesktopColors.textSecondary,
                  ),
                ),
              ],
              if (e.shortcut != null) ...[
                const SizedBox(width: ShellxSpace.s8),
                Keycaps(label: e.shortcut!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// UI-A9 §1.2 keycap: the label as one chip ("⌘⇧D", "Ctrl+Shift+D").
class Keycaps extends StatelessWidget {
  const Keycaps({super.key, required this.label, this.dashed = false});
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Container(
    height: ShellxSizes.keycapHeight,
    padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s6),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: ShellxDesktopColors.surfaceInset,
      borderRadius: BorderRadius.circular(ShellxRadius.r4),
      border: Border.all(
        color: dashed ? ShellxDesktopColors.dim : ShellxDesktopColors.border,
      ),
    ),
    child: Text(
      label,
      style: ShellxText.small.copyWith(color: ShellxDesktopColors.textPrimary),
    ),
  );
}
