import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
// xterm 4.0.0 does not export its text-input client; its state keeps the
// last platform value and is reachable only through this file.
// ignore: implementation_imports
import 'package:xterm/src/ui/custom_text_edit.dart';

/// How long a key may leave a composition untouched before the input method
/// is taken to have ignored it.
const Duration kImeStaleAfter = Duration(milliseconds: 80);

/// Ends an input-method composition xterm 4.0.0 would otherwise keep
/// forever.
///
/// `CustomTextEdit` remembers the platform's last editing value, and while
/// that value has a marked (composing) range it hands every key event to the
/// input method instead of the terminal (its `_onKeyEvent` returns
/// `skipRemainingHandlers`) and shows the marked text. When the platform
/// drops the composition without a final update (focus leaves the terminal,
/// the app goes inactive, the input source is switched) nothing resets that
/// value, so Enter, Backspace, arrows and shortcuts stop reaching the
/// terminal until another composition happens to finish.
///
/// Wraps a `TerminalView` and ends such a composition by committing it: the
/// marked text is written once, as if the input method had confirmed it, and
/// xterm resets the platform's state. Without an input connection it is
/// dropped instead. This happens
///  - when focus leaves the terminal,
///  - when the app's lifecycle changes (only in the focused terminal),
///  - when a key goes down during a composition and the input method leaves
///    the editing value untouched for [kImeStaleAfter]: it did not consume
///    the key, so it has no composition any more (an input-source switch
///    without a focus change looks like this).
class ImeComposeReset extends StatefulWidget {
  const ImeComposeReset({super.key, required this.child});

  final Widget child;

  @override
  State<ImeComposeReset> createState() => _ImeComposeResetState();
}

class _ImeComposeResetState extends State<ImeComposeReset>
    with WidgetsBindingObserver {
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  CustomTextEditState? _client() {
    CustomTextEditState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is CustomTextEditState) {
        found = e.state as CustomTextEditState;
        return;
      }
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found;
  }

  /// Whether the primary focus is inside this terminal.
  bool get _focused {
    final focus = FocusManager.instance.primaryFocus?.context;
    return focus != null &&
        identical(focus.findAncestorStateOfType<_ImeComposeResetState>(), this);
  }

  bool _composing(CustomTextEditState c) =>
      !(c.currentTextEditingValue?.composing.isCollapsed ?? true);

  void _end() {
    if (!mounted) return;
    final c = _client();
    if (c == null || !_composing(c)) return;
    final v = c.currentTextEditingValue!;
    if (c.hasInputConnection) {
      // The input method's own confirmation: xterm writes the text and
      // resets the platform's state.
      c.updateEditingValue(v.copyWith(composing: TextRange.empty));
    } else {
      // Nowhere to reset; xterm would write into a closed connection.
      c.updateEditingValue(TextEditingValue.empty);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_focused) _end();
  }

  static final Set<LogicalKeyboardKey> _modifiers = {
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.fn,
  };

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || _modifiers.contains(event.logicalKey)) {
      return false;
    }
    final c = _client();
    if (c == null || !_composing(c) || !_focused) return false;
    final before = c.currentTextEditingValue;
    _watchdog?.cancel();
    _watchdog = Timer(kImeStaleAfter, () {
      if (!mounted) return;
      final now = _client();
      if (now != null && now.currentTextEditingValue == before) _end();
    });
    return false;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (hasFocus) {
      if (!hasFocus) _end();
    },
    child: widget.child,
  );
}
