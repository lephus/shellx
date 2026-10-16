import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_completer.dart';
import 'package:shellx_desktop/src/ui/ai/ai_dock.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

const _commands = [
  AvailableCommand(name: 'review', description: 'Review the changes'),
  AvailableCommand(
    name: 'init',
    description: 'Write CLAUDE.md',
    hint: 'what to cover',
  ),
  AvailableCommand(name: 'pr-comments', description: 'Read PR comments'),
];

/// V2-1 D16: `/` lists the agent's commands.
void main() {
  test('names starting with the text first, then containing it', () {
    expect(
      [for (final s in aiMatchCommands(_commands, 'r')) s.label],
      ['/review', '/pr-comments'],
    );
    expect(
      aiMatchCommands(_commands, 'init').single.detail,
      'Write CLAUDE.md — what to cover',
    );
  });

  Future<(FakeAiRuntimes, AiRuntime)> dock(WidgetTester t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final runtime = partRuntime(fakes);
    await runtime.start();
    runtime.state.applyUpdate(
      const CommandsUpdated(_commands),
      DateTime(2026, 10, 14),
    );
    await pumpAiPart(t, const AiDock(), runtime: runtime);
    await t.tap(find.byKey(const Key('ai.composer')));
    await t.pump();
    return (fakes, runtime);
  }

  testWidgets('/ at the start lists the commands; one is taken and sent as '
      'typed', (t) async {
    final (fakes, runtime) = await dock(t);
    await t.enterText(find.byKey(const Key('ai.composer')), '/re');
    await t.pump();
    expect(find.text('/review'), findsOneWidget);
    expect(find.text('Review the changes'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(
      t
          .widget<TextField>(find.byKey(const Key('ai.composer')))
          .controller!
          .text,
      '/review ',
    );
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(fakes.agent().received, contains('session/prompt:/review'));
    await runtime.dispose();
  });

  testWidgets('a / later in the text is only text; the / button starts a '
      'command', (t) async {
    final (_, runtime) = await dock(t);
    await t.enterText(find.byKey(const Key('ai.composer')), 'and /re');
    await t.pump();
    expect(find.byKey(const Key('ai.suggest.0')), findsNothing);
    await t.enterText(find.byKey(const Key('ai.composer')), '');
    await t.tap(find.byKey(const Key('ai.commands')));
    await t.pump();
    await t.pump();
    expect(find.text('/init'), findsOneWidget);
    await runtime.dispose();
  });
}
