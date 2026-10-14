import 'dart:math';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_completer.dart';
import 'package:shellx_desktop/src/ui/ai/ai_dock.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

/// V2-1 D16: `@` mentions.
void main() {
  const files = ['README.md', 'lib/src/main.dart', 'src/domain.dart', 'x.txt'];

  test('ranking: the name starting with it, then containing it, then the '
      'path; shorter first', () {
    expect(
      [for (final s in aiMatchFiles(files, 'ma')) s.label],
      ['lib/src/main.dart', 'src/domain.dart'],
    );
    expect(
      [for (final s in aiMatchFiles(files, 'src')) s.label],
      ['src/domain.dart', 'lib/src/main.dart'],
    );
  });

  test('20 000 paths: each is ranked once per keystroke, the best eight '
      'are kept, in the order a full sort gives', () {
    final random = Random(7);
    final many = [
      for (var i = 0; i < 20000; i++)
        'packages/pkg_${random.nextInt(97)}/lib/${random.nextBool() ? 'src/' : ''}'
            'feature_${random.nextInt(211)}/file_$i.dart',
    ];
    for (final q in ['a', 'fi', 'file_1', 'FEATURE_2', 'zzz', '']) {
      debugFileRanks = 0;
      final got = [for (final s in aiMatchFiles(many, q)) s.label];
      expect(debugFileRanks, lessThanOrEqualTo(many.length), reason: q);
      // The reference: rank everything, sort fully (stable on the order the
      // paths came in), take eight.
      final lowered = q.toLowerCase();
      int rank(String path) {
        final lower = path.toLowerCase();
        final name = lower.substring(lower.lastIndexOf('/') + 1);
        if (name.startsWith(lowered)) return 0;
        if (name.contains(lowered)) return 1;
        return lower.contains(lowered) ? 2 : 3;
      }

      final ranked =
          [
            for (final (i, f) in many.indexed)
              if (rank(f) < 3)
                (rank: rank(f), length: f.length, index: i, path: f),
          ]..sort((a, b) {
            final r = a.rank.compareTo(b.rank);
            if (r != 0) return r;
            final l = a.length.compareTo(b.length);
            return l != 0 ? l : a.index.compareTo(b.index);
          });
      expect(got, [for (final r in ranked.take(8)) r.path], reason: q);
    }
  });

  Future<(FakeAiRuntimes, AiRuntime)> dock(WidgetTester t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final runtime = partRuntime(fakes);
    await runtime.start();
    final part = await pumpAiPart(t, const AiDock(), runtime: runtime);
    part.ui.fileIndex = () async => files;
    await t.tap(find.byKey(const Key('ai.composer')));
    await t.pump();
    return (fakes, runtime);
  }

  String text(WidgetTester t) => t
      .widget<TextField>(find.byKey(const Key('ai.composer')))
      .controller!
      .text;

  testWidgets('@ offers the project\'s files; ↓ and Enter take one; the file '
      'goes along as a resource_link', (t) async {
    final (fakes, runtime) = await dock(t);
    await t.enterText(find.byKey(const Key('ai.composer')), 'look at @ma');
    await t.pump();
    expect(find.byKey(const Key('ai.suggest.0')), findsOneWidget);
    expect(find.text('lib/src/main.dart'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(text(t), 'look at @src/domain.dart ');
    expect(find.byKey(const Key('ai.suggest.0')), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    final prompt = fakes.agent().params['session/prompt']!['prompt']! as List;
    expect(prompt.first, {'type': 'text', 'text': 'look at @src/domain.dart'});
    expect(prompt.last, {
      'type': 'resource_link',
      'uri': Uri.file('$testAiCwd/src/domain.dart').toString(),
      'name': 'domain.dart',
      'title': 'src/domain.dart',
    });
    await runtime.dispose();
  });

  testWidgets('Esc closes the list and keeps the text (no Stop, no answer); '
      'the @ button starts a mention', (t) async {
    final (fakes, runtime) = await dock(t);
    await t.tap(find.byKey(const Key('ai.mention')));
    await t.pump();
    expect(text(t), '@');
    await t.pump();
    expect(find.byKey(const Key('ai.suggest.0')), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(find.byKey(const Key('ai.suggest.0')), findsNothing);
    expect(text(t), '@');
    await t.tap(find.byKey(const Key('ai.mention')));
    await t.pump();
    expect(fakes.agent().received.where((r) => r.contains('prompt')), isEmpty);
    await runtime.dispose();
  });

  testWidgets('clicking a suggestion keeps the keyboard in the composer '
      '(macOS and Windows drop it on a tap outside a field)', (t) async {
    final (_, runtime) = await dock(t);
    final focus = t
        .widget<TextField>(find.byKey(const Key('ai.composer')))
        .focusNode!;
    await t.enterText(find.byKey(const Key('ai.composer')), 'look at @ma');
    await t.pump();
    await t.tap(
      find.byKey(const Key('ai.suggest.1')),
      kind: PointerDeviceKind.mouse,
    );
    await t.pump();
    expect(text(t), 'look at @src/domain.dart ');
    expect(focus.hasPrimaryFocus, isTrue);
    await runtime.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
