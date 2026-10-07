import 'package:flutter/widgets.dart';
// xterm 4.0.0 does not export its text-input client; its state keeps the
// last platform value and is reachable only through this file.
// ignore: implementation_imports
import 'package:xterm/src/ui/custom_text_edit.dart';

/// Ends an input-method composition xterm 4.0.0 would otherwise keep
/// forever.
///
/// `CustomTextEdit` remembers the platform's last editing value, and while
/// that value has a marked (composing) range it hands every key event to the
/// input method instead of the terminal (its `_onKeyEvent` returns
/// `skipRemainingHandlers`) and shows the marked text. When the platform
/// drops the composition without a final update (focus leaves the terminal,
/// the window goes inactive, the input source is switched) nothing resets
/// that value, so Enter, Backspace, arrows and shortcuts stop reaching the
/// terminal until another composition happens to finish.
///
/// Wraps a `TerminalView`; on losing focus and on any app lifecycle change
/// it feeds the client an empty value, but only while a composition is open.
class ImeComposeReset extends StatefulWidget {
  const ImeComposeReset({super.key, required this.child});

  final Widget child;

  @override
  State<ImeComposeReset> createState() => _ImeComposeResetState();
}

class _ImeComposeResetState extends State<ImeComposeReset>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _reset();

  void _reset() {
    if (!mounted) return;
    CustomTextEditState? client;
    void visit(Element e) {
      if (client != null) return;
      if (e is StatefulElement && e.state is CustomTextEditState) {
        client = e.state as CustomTextEditState;
        return;
      }
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    final c = client;
    if (c == null || c.currentTextEditingValue!.composing.isCollapsed) return;
    c.updateEditingValue(TextEditingValue.empty);
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (hasFocus) {
      if (!hasFocus) _reset();
    },
    child: widget.child,
  );
}
