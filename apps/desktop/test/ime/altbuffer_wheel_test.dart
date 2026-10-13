import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ui/terminal/ime_compose_reset.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_overlays.dart'
    show ShellxScrollbar;
import 'package:xterm/xterm.dart';

/// `claude` runs in the alternate buffer with no scrollback (max=0). A mouse
/// wheel there must still scroll it — xterm forwards the wheel to the app as
/// arrow keys. This checks the wheel survives the desktop wrappers
/// (ShellxScrollbar + the shared scroll controller + ImeComposeReset).
void main() {
  Future<List<String>> wheelOutput(
    WidgetTester tester, {
    required bool withWrappers,
  }) async {
    final terminal = Terminal(maxLines: 1000);
    final out = <String>[];
    terminal.onOutput = out.add;
    final focus = FocusNode();
    final scroll = ScrollController();
    addTearDown(() {
      focus.dispose();
      scroll.dispose();
    });

    Widget view = TerminalView(
      terminal,
      scrollController: scroll,
      focusNode: focus,
      autofocus: true,
    );
    if (withWrappers) {
      view = ShellxScrollbar(
        controller: scroll,
        child: ImeComposeReset(child: view),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: 320, height: 240, child: view)),
        ),
      ),
    );
    await tester.pump();
    terminal.write('\x1b[?1049h'); // enter alternate buffer, like claude
    await tester.pumpAndSettle();

    out.clear();
    final center = tester.getCenter(find.byType(TerminalView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pumpAndSettle();
    return out;
  }

  testWidgets('bare TerminalView: wheel forwards to the app', (tester) async {
    final out = await wheelOutput(tester, withWrappers: false);
    expect(out, isNotEmpty, reason: 'bare: wheel should reach the app');
  });

  testWidgets('with desktop wrappers: wheel forwards to the app', (
    tester,
  ) async {
    final out = await wheelOutput(tester, withWrappers: true);
    expect(
      out,
      isNotEmpty,
      reason: 'wrapped: wheel must still reach the app (the real bug)',
    );
  });
}
