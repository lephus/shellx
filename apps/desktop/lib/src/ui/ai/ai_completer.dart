import 'package:flutter/widgets.dart';
import 'package:shellx_acp/shellx_acp.dart' show AvailableCommand;

/// One line of the composer's suggestions (D16): what replaces the typed
/// token, what the line shows, and the file it mentions (null: none).
typedef AiSuggestion = ({
  String insert,
  String label,
  String? detail,
  String? mention,
});

/// The most suggestions shown at once.
const int kAiSuggestMax = 8;

/// D16: the files matching [query] (case-insensitive), best first — the
/// name starting with it, then the name containing it, then the path
/// containing it; shorter paths first among equals.
List<AiSuggestion> aiMatchFiles(List<String> files, String query) {
  final q = query.toLowerCase();
  int rank(String path) {
    final lower = path.toLowerCase();
    final name = lower.substring(lower.lastIndexOf('/') + 1);
    if (name.startsWith(q)) return 0;
    if (name.contains(q)) return 1;
    return lower.contains(q) ? 2 : 3;
  }

  final hits = [
    for (final f in files)
      if (rank(f) < 3) f,
  ];
  hits.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.length.compareTo(b.length);
  });
  return [
    for (final f in hits.take(kAiSuggestMax))
      (insert: '@$f ', label: f, detail: null, mention: f),
  ];
}

/// D16: the agent's commands (`available_commands_update`) matching
/// [query]: the name starting with it, then containing it; at most 8.
List<AiSuggestion> aiMatchCommands(
  List<AvailableCommand> commands,
  String query,
) {
  final q = query.toLowerCase();
  final starts = [
    for (final c in commands)
      if (c.name.toLowerCase().startsWith(q)) c,
  ];
  final contains = [
    for (final c in commands)
      if (!c.name.toLowerCase().startsWith(q) &&
          c.name.toLowerCase().contains(q))
        c,
  ];
  return [
    for (final c in [...starts, ...contains].take(kAiSuggestMax))
      (
        insert: '/${c.name} ',
        label: '/${c.name}',
        detail: [c.description, ?c.hint].where((s) => s.isNotEmpty).join(' — '),
        mention: null,
      ),
  ];
}

/// D16: what the composer offers while the user types `@…` (the project's
/// files that `.gitignore` keeps, Task 25's index) or, at the start, `/…`
/// (the agent's commands). ↑/↓ move, Enter or Tab take one, Esc closes the
/// list until the token changes.
final class AiCompleter extends ChangeNotifier {
  AiCompleter({required this.files, required this.commands});

  /// The project's files; loaded when `@` is first typed.
  final Future<List<String>> Function() files;

  /// The agent's commands as last announced.
  final List<AvailableCommand> Function() commands;

  List<AiSuggestion> _items = const [];
  var _selected = 0;
  var _start = -1;
  var _closedAt = -1;
  var _gen = 0;

  List<AiSuggestion> get items => _items;
  int get selected => _selected;
  bool get active => _items.isNotEmpty;

  /// The text or the cursor moved: the token before the cursor decides.
  Future<void> update(TextEditingValue value) async {
    final gen = ++_gen;
    final sel = value.selection;
    if (!sel.isValid || !sel.isCollapsed) return _clear();
    final before = value.text.substring(0, sel.baseOffset);
    final slash = RegExp(r'^/(\S*)$').firstMatch(before);
    if (slash != null) {
      if (_closedAt == 0) return _clear();
      return _show(0, aiMatchCommands(commands(), slash.group(1)!));
    }
    final at = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(before);
    if (at == null) {
      _closedAt = -1;
      return _clear();
    }
    final query = at.group(1)!;
    final start = before.length - query.length - 1;
    if (start == _closedAt) return _clear();
    final all = await files();
    if (gen != _gen) return;
    _show(start, aiMatchFiles(all, query));
  }

  void _show(int start, List<AiSuggestion> items) {
    _start = start;
    _items = items;
    _selected = 0;
    notifyListeners();
  }

  void _clear() {
    if (_items.isEmpty) return;
    _items = const [];
    notifyListeners();
  }

  void move(int delta) {
    if (_items.isEmpty) return;
    _selected = (_selected + delta) % _items.length;
    notifyListeners();
  }

  /// Esc: closed until another token starts.
  void dismiss() {
    _closedAt = _start;
    _clear();
  }

  /// [value] with the token replaced by suggestion [index] (the selected
  /// one by default), the cursor after it.
  (TextEditingValue, AiSuggestion) accept(
    TextEditingValue value, [
    int? index,
  ]) {
    final pick = _items[index ?? _selected];
    final end = value.selection.baseOffset;
    final text = value.text.replaceRange(_start, end, pick.insert);
    _clear();
    return (
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: _start + pick.insert.length),
      ),
      pick,
    );
  }
}
