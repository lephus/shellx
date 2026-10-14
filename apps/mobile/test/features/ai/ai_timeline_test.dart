import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_items.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_timeline.dart';
import 'package:shellx_ai/remote.dart';

import '../../support/app_harness.dart';
import '../../support/fakes.dart';
import '../../support/widget_probes.dart';

const sid = 'e.-1';

void say(AiSessionState s, String text) => s.applyUpdate(
  SessionUpdate.fromJson({
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  }),
  DateTime.now(),
);

void tool(AiSessionState s, String id, Map<String, Object?> fields) =>
    s.applyUpdate(SessionUpdate.fromJson({'sessionUpdate': 'tool_call', 'toolCallId': id, ...fields}), DateTime.now());

void read(AiSessionState s, int i) => tool(s, 'c$i', {
  'title': 'Read f$i.ts',
  'kind': 'read',
  'status': 'completed',
  'locations': [
    {'path': '/p/f$i.ts'},
  ],
});

/// V2-2 §5.2 and D8: the conversation list on a phone, in isolation from the page.
void main() {
  late FakeAiSession ai;
  late ValueNotifier<int> version;
  late int loadCalls;

  setUp(() {
    ai = FakeAiSession(sid);
    version = ValueNotifier<int>(0);
    ai.changes.listen((_) => version.value++);
    loadCalls = 0;
  });

  tearDown(() => version.dispose());

  /// The timeline alone, 400 × 800 points, over [ai]'s mirror.
  Future<void> pump(WidgetTester tester, {ValueNotifier<int?>? jump, Size size = const Size(400, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localized(
        Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: version,
            builder: (context, v, _) => AiTimeline(
              mirror: ai.mirror,
              version: v,
              agentName: 'Claude',
              onLoadEarlier: () {
                loadCalls++;
                ai.loadEarlier();
              },
              jumpTo: jump,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The timeline's own scroll position (the cards inside scroll sideways too).
  ScrollPosition position(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: find.byKey(const Key('ai.timeline')), matching: find.byType(Scrollable)).first,
      )
      .position;

  Rect view(WidgetTester tester) => tester.getRect(find.byKey(const Key('ai.timeline')));

  /// A conversation whose items differ a lot in height: one-line cards between answers of 1 to 15 lines.
  void variedConversation(int rounds) {
    ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
    for (var i = 0; i < rounds; i++) {
      read(ai.desktop, i);
      say(ai.desktop, List.generate(1 + (i * 7) % 15, (n) => 'Dòng $n của đoạn $i.').join('\n\n'));
    }
  }

  group('virtualized', () {
    testWidgets('a thousand items, older pages and new ones: only what is near the screen is built', (tester) async {
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      for (var i = 0; i < 700; i++) {
        read(ai.desktop, i);
      }
      ai.sync();
      await pump(tester);
      expect(find.byType(AiItemView).evaluate().length, inInclusiveRange(5, 40));
      while (ai.mirror.hasEarlier) {
        ai.loadEarlier();
        await tester.pump();
      }
      expect(ai.mirror.items, hasLength(701));
      expect(find.byType(AiItemView).evaluate().length, inInclusiveRange(5, 40));
      for (var i = 700; i < 1000; i++) {
        read(ai.desktop, i);
      }
      ai.sync();
      await tester.pumpAndSettle();
      expect(ai.mirror.items, hasLength(1001));
      expect(find.byType(AiItemView).evaluate().length, inInclusiveRange(5, 40));
      expect(position(tester).extentAfter, lessThan(1)); // and the end is on screen
      expect(find.text('Đọc f999.ts'), findsOneWidget);
    });
  });

  group('sticks to the bottom only while the user is there', () {
    testWidgets('opens on the latest, whatever the heights', (tester) async {
      variedConversation(40);
      ai.sync();
      await pump(tester);
      expect(position(tester).extentAfter, lessThan(1));
      final last = find.textContaining('Dòng 3 của đoạn 39.');
      expect(last, findsOneWidget);
      expect(tester.getRect(last).bottom, lessThanOrEqualTo(view(tester).bottom));
    });

    testWidgets('follows what streams in below', (tester) async {
      variedConversation(30);
      ai.sync();
      await pump(tester);
      for (var i = 30; i < 36; i++) {
        read(ai.desktop, i);
        say(ai.desktop, List.generate(6, (n) => 'Dòng $n của đoạn $i.').join('\n\n'));
        ai.sync();
        await tester.pump();
        expect(position(tester).extentAfter, lessThan(1), reason: 'after $i');
        // On screen in the very frame it arrived, not one frame later.
        final newest = find.textContaining('Dòng 5 của đoạn $i.');
        expect(tester.getRect(newest).bottom, lessThanOrEqualTo(view(tester).bottom), reason: 'after $i');
      }
      await tester.pumpAndSettle();
      expect(position(tester).extentAfter, lessThan(1));
      expect(find.byKey(const Key('ai.latest')), findsNothing);
    });

    testWidgets('a text that grows at the bottom stays in view', (tester) async {
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      say(ai.desktop, 'bắt đầu');
      ai.sync();
      await pump(tester);
      for (var i = 0; i < 40; i++) {
        say(ai.desktop, '\n\nĐoạn mới số $i để dài thêm.');
        ai.sync();
        await tester.pump();
        expect(
          tester.getRect(find.textContaining('số $i để')).bottom,
          lessThanOrEqualTo(view(tester).bottom),
          reason: 'after $i',
        );
      }
      await tester.pumpAndSettle();
      expect(position(tester).extentAfter, lessThan(1));
      expect(find.textContaining('số 39'), findsOneWidget);
    });

    testWidgets('does not move what is read; "Mới nhất" brings the user back', (tester) async {
      variedConversation(30);
      ai.sync();
      await pump(tester);
      await tester.drag(find.byKey(const Key('ai.timeline')), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai.latest')), findsOneWidget);
      Map<int, double> tops() => {
        for (final e in find.byType(AiItemView).evaluate())
          (e.widget as AiItemView).item.index: tester.getTopLeft(find.byWidget(e.widget)).dy,
      };
      final before = tops();
      expect(before, isNotEmpty);
      final pixels = position(tester).pixels;
      for (var i = 30; i < 34; i++) {
        read(ai.desktop, i);
        say(ai.desktop, 'Tin mới $i.');
        ai.sync();
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final after = tops();
      for (final MapEntry(:key, :value) in before.entries) {
        expect(after[key], value, reason: 'item $key moved');
      }
      expect(position(tester).pixels, pixels);
      expect(find.byKey(const Key('ai.latest')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai.latest')));
      await tester.pumpAndSettle();
      expect(position(tester).extentAfter, lessThan(1));
      expect(find.byKey(const Key('ai.latest')), findsNothing);
      expect(find.text('Tin mới 33.'), findsOneWidget);
    });

    testWidgets('a finger on the list is not fought by what streams in', (tester) async {
      variedConversation(30);
      ai.sync();
      await pump(tester);
      final finger = await tester.startGesture(tester.getCenter(find.byKey(const Key('ai.timeline'))));
      await finger.moveBy(const Offset(0, 30)); // a little up, still within reach of the bottom
      await tester.pump();
      final pixels = position(tester).pixels;
      for (var i = 30; i < 33; i++) {
        read(ai.desktop, i);
        say(ai.desktop, 'Tin mới $i.\n\nvà thêm một đoạn nữa.\n\nvà một đoạn nữa.');
        ai.sync();
        await tester.pump();
      }
      expect(position(tester).pixels, closeTo(pixels, 0.5));
      await finger.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(position(tester).pixels, closeTo(pixels - 30, 0.5)); // the finger leads
      await finger.up();
      await tester.pumpAndSettle();
    });

    testWidgets(
      'also with the bouncing scroll of iOS: follows, lets a fling run, comes back with "Mới nhất"',
      (tester) async {
        variedConversation(30);
        ai.sync();
        await pump(tester);
        expect(position(tester).extentAfter, lessThan(1));
        for (var i = 30; i < 34; i++) {
          read(ai.desktop, i);
          say(ai.desktop, 'Tin mới $i.\n\nvà một đoạn nữa.');
          ai.sync();
          await tester.pump();
          expect(position(tester).extentAfter, lessThan(1), reason: 'after $i');
        }
        await tester.fling(find.byKey(const Key('ai.timeline')), const Offset(0, 500), 2000);
        await tester.pump(const Duration(milliseconds: 60));
        final flung = position(tester).pixels;
        for (var i = 34; i < 37; i++) {
          read(ai.desktop, i);
          say(ai.desktop, 'Tin mới $i.');
          ai.sync();
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(position(tester).pixels, lessThanOrEqualTo(flung)); // the fling goes on upwards, it is not pulled down
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('ai.latest')), findsOneWidget);
        await tester.tap(find.byKey(const Key('ai.latest')));
        await tester.pumpAndSettle();
        expect(position(tester).extentAfter, lessThan(1));
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets('a keyboard that opens leaves the last item in view', (tester) async {
      variedConversation(20);
      ai.sync();
      await pump(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(position(tester).extentAfter, lessThan(1));
    });

    testWidgets('a new generation starts over at the latest, wherever the user was', (tester) async {
      variedConversation(8); // short enough that the new one is the taller
      ai.sync();
      await pump(tester);
      await tester.drag(find.byKey(const Key('ai.timeline')), const Offset(0, 800));
      await tester.pumpAndSettle();
      expect(position(tester).extentAfter, greaterThan(100));
      void generation(int g, int n) {
        ai.mirror.apply({
          'v': 1,
          'g': g,
          'from': 0,
          'n': n,
          'reset': true,
          'items': [
            for (var i = 0; i < n; i++)
              {
                'i': i,
                'r': 1,
                'turn': 1,
                'k': 'agent',
                'at': 0,
                'add': 'Phiên $g, tin $i.\n\nvà một đoạn nữa cho dài.',
              },
          ],
        }, snapshot: true);
        version.value++;
      }

      generation(9, 80); // tall: the user cannot see all of it
      await tester.pumpAndSettle();
      expect(position(tester).extentAfter, lessThan(1));
      expect(find.textContaining('Phiên 9, tin 79.'), findsOneWidget);
      expect(find.textContaining('Phiên 9, tin 0.'), findsNothing);

      generation(10, 3); // short: all of it is in view
      await tester.pumpAndSettle();
      expect(find.textContaining('Phiên 10, tin 0.'), findsOneWidget);
      expect(find.textContaining('Phiên 10, tin 2.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('earlier pages (V2-2 D5, D8)', () {
    testWidgets('come above and do not move what is on screen', (tester) async {
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      for (var i = 0; i < 100; i++) {
        read(ai.desktop, i);
      }
      ai.sync();
      await pump(tester);
      await tester.drag(find.byKey(const Key('ai.timeline')), const Offset(0, 30000));
      await tester.pumpAndSettle();
      final first = find.text('Đọc f40.ts'); // the first item of the first snapshot
      expect(first, findsOneWidget);
      final before = tester.getTopLeft(first).dy;
      await tester.tap(find.byKey(const Key('ai.loadEarlier')));
      await tester.pumpAndSettle();
      expect(ai.mirror.from, lessThan(40));
      expect(tester.getTopLeft(first).dy, before);
      expect(position(tester).extentBefore, greaterThan(0)); // the new page waits above
    });

    testWidgets('one request per tap while the page is on its way', (tester) async {
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      for (var i = 0; i < 100; i++) {
        read(ai.desktop, i);
      }
      ai.sync();
      await pump(tester);
      await tester.drag(find.byKey(const Key('ai.timeline')), const Offset(0, 30000));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai.loadEarlier')));
      await tester.tap(find.byKey(const Key('ai.loadEarlier')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(loadCalls, 1);
    });

    testWidgets('the button waits for a page that never comes, then works again', (tester) async {
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      for (var i = 0; i < 100; i++) {
        read(ai.desktop, i);
      }
      ai.sync();
      ai.lose(); // the link is not live: a request is asked of nobody and nothing comes back
      await pump(tester);
      await tester.drag(find.byKey(const Key('ai.timeline')), const Offset(0, 30000));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai.loadEarlier')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai.loadEarlier')), warnIfMissed: false);
      expect(loadCalls, 1);
      await tester.pump(const Duration(seconds: 10));
      await tester.tap(find.byKey(const Key('ai.loadEarlier')));
      expect(loadCalls, 2);
    });
  });

  group('only what changed is rebuilt', () {
    testWidgets('one item changes: it is rebuilt, its neighbours are not', (tester) async {
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      for (var i = 0; i < 40; i++) {
        tool(ai.desktop, 'c$i', {
          'title': 'npm test $i',
          'kind': 'execute',
          'status': 'in_progress',
          'locations': [
            {'path': '/p/f$i.ts'},
          ],
        });
      }
      ai.sync();
      await pump(tester);
      expect(find.byType(AiItemView).evaluate().length, greaterThan(10));
      final rebuilds = trackRebuilds();
      ai.desktop.applyUpdate(
        SessionUpdate.fromJson({'sessionUpdate': 'tool_call_update', 'toolCallId': 'c39', 'status': 'completed'}),
        DateTime.now(),
      );
      ai.sync();
      await tester.pump();
      expect(rebuilds[AiItemView], 1);
      expect(rebuilds[AiToolCard], 1);
    });

    testWidgets('a streaming answer re-parses only its last block', (tester) async {
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      say(ai.desktop, List.generate(30, (i) => 'Đoạn số $i.').join('\n\n'));
      ai.sync();
      await pump(tester);
      expect(find.byType(MarkdownBody).evaluate().length, 30);
      final rebuilds = trackRebuilds();
      say(ai.desktop, ' Thêm một ít.');
      ai.sync();
      await tester.pump();
      expect(rebuilds[MarkdownBody], 1);
      expect(find.textContaining('Thêm một ít.'), findsOneWidget);
    });

    testWidgets('a longer answer builds only its new blocks', (tester) async {
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      say(ai.desktop, 'Một.\n\nHai.');
      ai.sync();
      await pump(tester);
      final rebuilds = trackRebuilds();
      say(ai.desktop, '\n\nBa.');
      ai.sync();
      await tester.pump();
      expect(rebuilds[MarkdownBody], 1); // only the new block is built
      expect(find.text('Ba.'), findsOneWidget);
    });
  });

  group('a card the user opened', () {
    testWidgets('stays open, and keeps its place, when the computer updates it', (tester) async {
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      tool(ai.desktop, 'c1', {
        'title': 'ls -la',
        'kind': 'execute',
        'status': 'in_progress',
        'content': [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': 'total 8'},
          },
        ],
      });
      ai.sync();
      await pump(tester);
      await tester.tap(find.text('Chạy ls -la'));
      await tester.pumpAndSettle();
      expect(find.textContaining('total 8'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        ai.desktop.applyUpdate(
          SessionUpdate.fromJson({'sessionUpdate': 'tool_call_update', 'toolCallId': 'c1', 'title': 'ls -la $i'}),
          DateTime.now(),
        );
        ai.sync();
        await tester.pumpAndSettle();
        expect(find.textContaining('total 8'), findsOneWidget, reason: 'update $i');
      }
    });

    testWidgets('a thought opened by the user stays open while the answer goes on', (tester) async {
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      ai.desktop.applyUpdate(
        SessionUpdate.fromJson({
          'sessionUpdate': 'agent_thought_chunk',
          'content': {'type': 'text', 'text': 'Mình nghĩ'},
        }),
        DateTime.now(),
      );
      ai.sync();
      await pump(tester);
      expect(find.textContaining('Mình nghĩ'), findsNothing); // folded
      await tester.tap(find.text('Suy nghĩ'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mình nghĩ'), findsOneWidget);
      ai.desktop.applyUpdate(
        SessionUpdate.fromJson({
          'sessionUpdate': 'agent_thought_chunk',
          'content': {'type': 'text', 'text': ' thêm một chút'},
        }),
        DateTime.now(),
      );
      ai.sync();
      await tester.pumpAndSettle();
      expect(find.textContaining('Mình nghĩ thêm một chút'), findsOneWidget);
    });
  });

  group('showing an item', () {
    testWidgets('an item to bring into view comes into view: built or not, and every time it is asked', (tester) async {
      variedConversation(40);
      ai.sync();
      final jump = ValueNotifier<int?>(null);
      addTearDown(jump.dispose);
      await pump(tester, jump: jump);
      final target = ai.mirror.items.whereType<MirrorTool>().last; // among the latest, like a permission's card
      final card = find.byWidgetPredicate((w) => w is AiToolCard && w.tool.index == target.index);
      void expectInView() {
        expect(card, findsOneWidget);
        final rect = tester.getRect(card);
        expect(rect.top, greaterThanOrEqualTo(view(tester).top));
        expect(rect.bottom, lessThanOrEqualTo(view(tester).bottom));
      }

      for (final away in [300.0, 30000.0, 300.0]) {
        await tester.drag(find.byKey(const Key('ai.timeline')), Offset(0, away)); // up, a little or to the top
        await tester.pumpAndSettle();
        jump.value = null; // to ask again for the same item
        jump.value = target.index;
        await tester.pumpAndSettle();
        expectInView();
      }
    });
  });

  group('a conversation with nothing yet', () {
    testWidgets('says to write the first message', (tester) async {
      await pump(tester);
      expect(find.text('Chưa có tin nhắn. Viết tin đầu tiên ở ô dưới.'), findsOneWidget);
    });
  });
}
