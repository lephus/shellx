import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../text_editing_shortcuts.dart';
import '../theme/shellx_desktop_theme.dart';

/// UI-A2 §4: rename in place. Opens with the text selected; Enter (or
/// Numpad Enter) and losing the focus commit, Esc cancels — exactly one of
/// the two calls. ⌘A/⌘C/⌘V/⌘X (Ctrl on Windows) edit the field instead of
/// reaching the window's terminal shortcuts; ⌘T, ⌘W and ⌘1–9 still reach
/// the window (the focus they move commits the field).
class InlineNameField extends StatefulWidget {
  const InlineNameField({
    super.key,
    required this.initial,
    required this.style,
    required this.label,
    required this.onCommit,
    required this.onCancel,
    this.identity,
    this.keepTextInPlace = false,
  });

  final String initial;
  final TextStyle style;

  /// The field's accessible name ("Tên tab" / "Tên workspace").
  final String label;
  final void Function(String text) onCommit;
  final VoidCallback onCancel;

  /// V5: draw the field [textInset] left so its text sits where the title
  /// was. Only where that much room is free left of the field (a tab row:
  /// the 8 px after the dot); a workspace header has its chevron 4 px away.
  final bool keepTextInPlace;

  /// What is being renamed (a tab, a workspace). A field disposed while a
  /// newer field for the same item is open does not commit: the open one
  /// has the user's text and commits itself.
  final Object? identity;

  /// The newest field per [identity].
  static final _open = <Object, Object>{};

  /// The text's left edge inside the field (the outlined decorator's own
  /// inset plus the 4 px padding; measured by the V5 test).
  /// The field is drawn this far left so the text does not jump (V5).
  static const double textInset = 8;

  /// Matches `kTabNameMaxLength` and `kWorkspaceNameMaxLength`.
  static const int maxLength = 64;

  @override
  State<InlineNameField> createState() => _InlineNameFieldState();
}

class _InlineNameFieldState extends State<InlineNameField> {
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  final _focus = FocusNode(debugLabel: 'inline name');
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (widget.identity case final id?) InlineNameField._open[id] = this;
    _focus.addListener(_onFocus);
    // After the frame that builds the field, so it wins over a focus
    // request made in the same frame (the selection's terminal focus).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_done) _focus.requestFocus();
    });
  }

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    if (_done) return;
    _done = true;
    widget.onCommit(_controller.text);
  }

  void _cancel() {
    if (_done) return;
    _done = true;
    widget.onCancel();
  }

  /// Closed from outside without Enter or Esc (another rename took over,
  /// the row scrolled out of the lazy list): what was typed is kept. After
  /// the frame that removed the field, since the commit changes providers.
  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    final id = widget.identity;
    var superseded = false;
    if (id != null) {
      superseded = !identical(InlineNameField._open[id], this);
      if (!superseded) InlineNameField._open.remove(id);
    }
    if (!_done && !superseded) {
      _done = true;
      final text = _controller.text;
      final commit = widget.onCommit;
      scheduleMicrotask(() => commit(text));
    }
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Enter and Esc as key events: a desktop text field only gets Enter as
  /// an input action when no ancestor handled the key. While an input
  /// method composes (Vietnamese Telex, CJK) both keys stay the IME's.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_controller.value.composing.isValid) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _commit();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    const outline = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r4)),
      borderSide: BorderSide(color: ShellxDesktopColors.accent),
    );
    // 22 high (UI-A2 §1.2); a large text scale grows it with the line.
    final line = MediaQuery.textScalerOf(
      context,
    ).scale((widget.style.fontSize ?? 13) * (widget.style.height ?? 1));
    final height = max(ShellxSizes.renameField, line + 2 * ShellxSpace.s2);
    final field = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Shortcuts(
        shortcuts: textEditingShortcuts(),
        child: SizedBox(
          height: height,
          child: Semantics(
            // The accessible name ("Tab name", UI-A2 §4), on a node of its
            // own: never merged into the row's label.
            container: true,
            label: widget.label,
            child: TextField(
              key: const Key('row.renameField'),
              controller: _controller,
              focusNode: _focus,
              style: widget.style.copyWith(
                color: ShellxDesktopColors.textTitle,
              ),
              cursorColor: ShellxDesktopColors.accent,
              maxLines: 1,
              maxLength: InlineNameField.maxLength,
              textAlignVertical: TextAlignVertical.center,
              onSubmitted: (_) => _commit(),
              decoration: InputDecoration(
                isDense: true,
                // V5: the outline is the whole 22 px box, whatever density
                // the platform theme applies (compact would hug the text).
                constraints: BoxConstraints.tightFor(height: height),
                filled: true,
                fillColor: ShellxDesktopColors.surfaceInset,
                counterText: '',
                semanticCounterText: '',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: ShellxSpace.s4,
                  vertical: ShellxSpace.s2,
                ),
                border: outline,
                enabledBorder: outline,
                focusedBorder: outline,
              ),
            ),
          ),
        ),
      ),
    );
    // V5: the platform's compact density would take the vertical padding
    // away; and the glyphs stay where the title or name was (the border
    // and the 4 px padding sit left of them).
    return Theme(
      data: Theme.of(context).copyWith(visualDensity: VisualDensity.standard),
      child: widget.keepTextInPlace
          ? Transform.translate(
              offset: const Offset(-InlineNameField.textInset, 0),
              child: field,
            )
          : field,
    );
  }
}
