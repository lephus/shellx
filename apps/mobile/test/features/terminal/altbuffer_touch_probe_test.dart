import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Probe: in the alternate buffer (claude), does a TOUCH drag forward to the
/// app (as arrow keys), the way a mouse wheel does?
void main() {
  testWidgets('touch drag in alt-buffer forwards to the app', (tester) async {
    final terminal = Terminal(maxLines: 1000);
    final out = <String>[];
    terminal.onOutput = out.add;
    final focus = FocusNode();
    final scroll = ScrollController();
    addTearDown(() {
      focus.dispose();
      scroll.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 240,
              child: TerminalView(
                terminal,
                scrollController: scroll,
                focusNode: focus,
                autofocus: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    terminal.write('\x1b[?1049h');
    await tester.pumpAndSettle();

    out.clear();
    await tester.drag(find.byType(TerminalView), const Offset(0, 150));
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print('TOUCH alt-buffer out=${out.map((e) => e.codeUnits).toList()}');
    expect(out, isNotEmpty, reason: 'touch drag should scroll the app');
  });
}
