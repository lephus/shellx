import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_dock.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_items.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/widget_probes.dart';

/// V2-2 §5.2: the cards of the conversation, one by one.
void main() {
  late FakeExternalLinks links;

  setUp(() {
    links = FakeExternalLinks();
    getIt
      ..registerSingleton<ExternalLinks>(links)
      ..registerSingleton<PopupHandler>(FakePopupHandler());
  });

  tearDown(() async => getIt.reset());

  Future<void> pumpItem(
    WidgetTester tester,
    MirrorItem item, {
    Locale locale = vi,
    ReadonlySignal<DateTime>? clock,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localized(
        locale: locale,
        Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: AiItemView(item: item, agentName: 'Claude', clock: clock),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  MirrorTool tool({
    ToolKind? kind = ToolKind.execute,
    String? title = 'npm test',
    String? end = 'completed',
    ToolCallStatus? status,
    MirrorOutput? output,
    List<MirrorDiff> diffs = const [],
    String? input,
    MirrorPermissionState? permission,
    PermissionKind? answerKind,
    String? answerName,
    List<ToolLocation> locations = const [],
    DateTime? startedAt,
  }) => MirrorTool(
    0,
    1,
    1,
    toolCallId: 'c',
    kind: kind,
    title: title,
    end: end,
    status: status,
    output: output,
    diffs: diffs,
    input: input,
    permission: permission,
    answerKind: answerKind,
    answerName: answerName,
    locations: locations,
    startedAt: startedAt,
  );

  group('items the phone cannot draw are read on the computer (V2-2 D4)', () {
    for (final (kind, text) in [
      ('big', 'Quá lớn để xem trên điện thoại. Xem trên máy tính.'),
      ('hologram', 'Điện thoại chưa hỗ trợ loại mục này. Xem trên máy tính.'),
      (null, 'Điện thoại chưa hỗ trợ loại mục này. Xem trên máy tính.'),
    ]) {
      testWidgets('a "$kind" item', (tester) async {
        await pumpItem(tester, MirrorUnknown(0, 1, 1, kind));
        expect(find.text(text), findsOneWidget);
      });
    }

    testWidgets('in English too', (tester) async {
      await pumpItem(tester, const MirrorUnknown(0, 1, 1, 'hologram'), locale: en);
      expect(find.text('This kind of item is not supported on the phone yet. See it on the computer.'), findsOneWidget);
    });
  });

  group('a megabyte on one line does not stop the page (V2-2 D4: the phone caps what it draws)', () {
    final big = 'x' * 1000000;
    const tooBig = 'Quá lớn để xem trên điện thoại. Xem trên máy tính.';

    testWidgets('tool output, the first and the last lines', (tester) async {
      await pumpItem(
        tester,
        tool(
          output: MirrorOutput(head: big, tail: big, lines: 2, cut: true),
        ),
      );
      await tester.tap(find.text('Chạy npm test'));
      await tester.pumpAndSettle();
      expect(longestText(tester), inInclusiveRange(1000, 50000));
      expect(find.text(tooBig), findsWidgets);
    }, timeout: const Timeout(Duration(minutes: 3)));

    testWidgets('a diff, both sides', (tester) async {
      await pumpItem(
        tester,
        tool(
          kind: ToolKind.edit,
          title: 'Edit a.ts',
          diffs: [MirrorDiff(path: '/p/a.ts', oldText: big, newText: '${big}y', plus: 1, minus: 1)],
        ),
      );
      await tester.tap(find.text('Sửa a.ts'));
      await tester.pumpAndSettle();
      expect(longestText(tester), inInclusiveRange(1000, 50000));
      expect(find.text(tooBig), findsWidgets);
    }, timeout: const Timeout(Duration(minutes: 3)));

    testWidgets('a new file', (tester) async {
      await pumpItem(
        tester,
        tool(
          kind: ToolKind.edit,
          title: 'Create a.ts',
          diffs: [MirrorDiff(path: '/p/a.ts', newText: big, plus: 1)],
        ),
      );
      await tester.tap(find.text('Tạo a.ts'));
      await tester.pumpAndSettle();
      expect(longestText(tester), inInclusiveRange(1000, 50000));
    }, timeout: const Timeout(Duration(minutes: 3)));

    testWidgets('a tool call\'s input', (tester) async {
      await pumpItem(tester, tool(kind: ToolKind.other, title: 'mcp__s__t', input: big));
      await tester.tap(find.text('s · t'));
      await tester.pumpAndSettle();
      expect(longestText(tester), inInclusiveRange(1000, 50000));
    }, timeout: const Timeout(Duration(minutes: 3)));

    for (final kind in MirrorTextKind.values) {
      testWidgets('a ${kind.name} text', (tester) async {
        await pumpItem(tester, MirrorText(0, 1, 1, kind, big));
        if (kind == MirrorTextKind.thought) {
          await tester.tap(find.text('Suy nghĩ'));
          await tester.pumpAndSettle();
        }
        expect(longestText(tester), inInclusiveRange(1000, 50000));
        expect(find.text('Phần còn lại của tin này xem trên máy tính.'), findsOneWidget);
      }, timeout: const Timeout(Duration(minutes: 3)));
    }

    testWidgets('a text of a hundred thousand one-word paragraphs is cut by blocks too', (tester) async {
      await pumpItem(tester, MirrorText(0, 1, 1, MirrorTextKind.agent, List.filled(100000, 'a').join('\n\n')));
      expect(find.byType(MarkdownBody).evaluate().length, lessThan(300));
      expect(find.text('Phần còn lại của tin này xem trên máy tính.'), findsOneWidget);
    }, timeout: const Timeout(Duration(minutes: 3)));

    testWidgets('a text the computer cut says so, and a short one says nothing', (tester) async {
      await pumpItem(tester, const MirrorText(0, 1, 1, MirrorTextKind.agent, 'ngắn', fullLength: 90000));
      expect(find.text('Phần còn lại của tin này xem trên máy tính.'), findsOneWidget);
      await pumpItem(tester, const MirrorText(0, 1, 1, MirrorTextKind.agent, 'ngắn'));
      expect(find.text('Phần còn lại của tin này xem trên máy tính.'), findsNothing);
    });

    testWidgets('a message the phone itself may send (32 KB) is shown whole', (tester) async {
      final prompt = List.filled(10923, 'ab').join(' '); // 32 KB of words
      expect(prompt.length, 32 * 1024);
      await pumpItem(tester, MirrorText(0, 1, 1, MirrorTextKind.user, prompt));
      expect(find.text('Phần còn lại của tin này xem trên máy tính.'), findsNothing);
      expect(longestText(tester), prompt.length);
    });

    testWidgets('what the computer sends within its limits is shown whole', (tester) async {
      final output = '${List.generate(250, (i) => 'dòng $i của đầu ra').join('\n')}\n';
      expect(output.length, lessThan(8192));
      await pumpItem(tester, tool(output: MirrorOutput(head: output, lines: 251)));
      await tester.tap(find.text('Chạy npm test'));
      await tester.pumpAndSettle();
      expect(find.textContaining('dòng 0 của đầu ra'), findsOneWidget);
      expect(find.textContaining('dòng 249 của đầu ra'), findsOneWidget);
      expect(find.text(tooBig), findsNothing);
      final text = tester.widgetList<EditableText>(find.byType(EditableText)).map((w) => w.controller.text).join();
      expect(text, contains('dòng 249 của đầu ra'));
    });
  });

  group('markdown (V2-1 B15: no image is loaded, only web links open)', () {
    /// Taps [word] in the markdown on screen (plain `Text`: the timeline's one `SelectionArea` makes it selectable).
    Future<void> tapLink(WidgetTester tester, String word) async {
      await tester.tapOnText(find.textRange.ofSubstring(word));
      await tester.pumpAndSettle();
    }

    testWidgets('an image shows its alt text and loads nothing', (tester) async {
      await pumpItem(
        tester,
        const MirrorText(0, 1, 1, MirrorTextKind.agent, 'xem ![sơ đồ](https://example.com/x.png) này'),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('sơ đồ', findRichText: true), findsOneWidget);
    });

    for (final (href, opens) in [
      ('https://example.com/a?b=1', true),
      ('http://example.com', true),
      ('javascript:alert(1)', false),
      ('file:///etc/passwd', false),
      ('mailto:a@b.c', false),
      ('tel:+84123', false),
      ('/relative/path', false),
      ('https://', false),
      // A name before the host can pass one site for another ("good.com" is the user name here): never opened.
      ('https://good.com@evil.com', false),
      ('https://good.com@evil.com/a', false),
      ('https://user:pw@host.com', false),
      // An "@" later in the address is only a character of the path or the query.
      ('https://host.com/@path', true),
      ('https://host.com/a?mail=a@b.c', true),
    ]) {
      testWidgets('a link to $href ${opens ? 'opens' : 'does not'}', (tester) async {
        await pumpItem(tester, MirrorText(0, 1, 1, MirrorTextKind.agent, 'xem [tài liệu]($href) này'));
        await tapLink(tester, 'tài liệu');
        expect(links.opened, opens ? [Uri.parse(href)] : isEmpty);
      });
    }

    testWidgets('code, lists and headings are laid out', (tester) async {
      await pumpItem(
        tester,
        const MirrorText(
          0,
          1,
          1,
          MirrorTextKind.agent,
          '# Tiêu đề\n\n- một\n- hai\n\n```dart\nvar a = 1;\n```\n\nxong **đậm**',
        ),
      );
      expect(find.textContaining('Tiêu đề', findRichText: true), findsOneWidget);
      expect(find.textContaining('var a = 1;', findRichText: true), findsOneWidget);
      expect(find.textContaining('xong đậm', findRichText: true), findsOneWidget);
    });

    testWidgets(
      'a long answer (paragraphs, a list, a table) makes no editor each: the timeline has one SelectionArea for them all',
      (tester) async {
        final text = [
          for (var i = 0; i < 40; i++) 'đoạn $i **đậm**',
          '- một\n- hai\n- ba',
          '| a | b |\n|---|---|\n| 1 | 2 |',
        ].join('\n\n');
        await pumpItem(tester, MirrorText(0, 1, 1, MirrorTextKind.agent, text));
        expect(find.byType(MarkdownBody), findsWidgets);
        expect(find.byType(EditableText), findsNothing);
        expect(find.byType(SelectableText), findsNothing);
        expect(find.textContaining('đoạn 39 đậm', findRichText: true), findsOneWidget);
      },
    );

    testWidgets('what the user wrote is plain text as well, and a thought opened too', (tester) async {
      await pumpItem(tester, const MirrorText(0, 1, 1, MirrorTextKind.user, 'Thêm nút đăng xuất'));
      expect(find.text('Thêm nút đăng xuất'), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);
      await pumpItem(tester, const MirrorText(0, 1, 1, MirrorTextKind.thought, 'Mình đang nghĩ'));
      await tester.tap(find.text('Suy nghĩ'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mình đang nghĩ', findRichText: true), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);
    });

    testWidgets('only an opened card holds selectable text (its output, its diff)', (tester) async {
      await pumpItem(
        tester,
        tool(
          output: const MirrorOutput(head: 'ok'),
          diffs: const [MirrorDiff(path: '/p/a.ts', oldText: 'a', newText: 'b', plus: 1, minus: 1)],
        ),
      );
      expect(find.byType(EditableText), findsNothing);
      await tester.tap(find.text('Chạy npm test'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsWidgets);
    });
  });

  group('cards', () {
    testWidgets('a thought is folded until it is tapped', (tester) async {
      await pumpItem(tester, const MirrorText(0, 1, 1, MirrorTextKind.thought, 'Mình đang nghĩ'));
      expect(find.textContaining('Mình đang nghĩ', findRichText: true), findsNothing);
      await tester.tap(find.text('Suy nghĩ'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mình đang nghĩ', findRichText: true), findsOneWidget);
      await tester.tap(find.text('Suy nghĩ'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mình đang nghĩ', findRichText: true), findsNothing);
    });

    group('a finger can hit what it is meant to (at least 44 points, V2-2 fix round 1)', () {
      testWidgets('the thought toggle, the whole row', (tester) async {
        await pumpItem(tester, const MirrorText(0, 1, 1, MirrorTextKind.thought, 'Mình đang nghĩ'));
        final toggle = find.ancestor(of: find.text('Suy nghĩ'), matching: find.byType(InkWell)).first;
        expect(tester.getSize(toggle).height, greaterThanOrEqualTo(44));
        // A tap at the edge of the row, away from the icon and the word, still opens it.
        final box = tester.getRect(toggle);
        await tester.tapAt(Offset(box.right - 4, box.top + 3));
        await tester.pumpAndSettle();
        expect(find.textContaining('Mình đang nghĩ', findRichText: true), findsOneWidget);
      });

      testWidgets('the tool card header, the whole row (and a card with nothing to open is not a button)', (
        tester,
      ) async {
        await pumpItem(tester, tool(output: const MirrorOutput(head: 'ok')));
        final header = find.descendant(of: find.byType(AiToolCard), matching: find.byType(InkWell)).first;
        expect(tester.getSize(header).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(header).width, greaterThan(300));
        final box = tester.getRect(header);
        await tester.tapAt(Offset(box.left + 2, box.bottom - 3)); // the corner of the row, away from icon and title
        await tester.pumpAndSettle();
        expect(find.byType(SelectableText), findsWidgets);
      });

      testWidgets('a closed card is its header and nothing more: one line is not a block', (tester) async {
        await pumpItem(tester, tool(output: const MirrorOutput(head: 'ok')));
        expect(tester.getSize(find.byType(AiToolCard)).height, inInclusiveRange(44, 48)); // the header and the border
      });

      testWidgets('a card with a long title keeps its row at least 44 points, and no more than its text needs', (
        tester,
      ) async {
        await pumpItem(
          tester,
          tool(
            title: 'npm test -- --coverage --reporter=verbose ' * 4,
            output: const MirrorOutput(head: 'ok'),
          ),
        );
        final header = find.descendant(of: find.byType(AiToolCard), matching: find.byType(InkWell)).first;
        expect(tester.getSize(header).height, inInclusiveRange(44, 60));
      });
    });

    for (final (end, rejected, text) in [
      ('completed', false, null),
      ('failed', false, 'lỗi'),
      ('failed', true, 'bị từ chối'),
      ('stopped', false, 'đã dừng'),
    ]) {
      testWidgets('a tool that $end${rejected ? ' (rejected)' : ''}', (tester) async {
        await pumpItem(
          tester,
          tool(end: end, answerKind: rejected ? PermissionKind.rejectOnce : null, answerName: rejected ? 'No' : null),
        );
        if (text == null) {
          expect(find.byIcon(Icons.check), findsOneWidget);
          expect(tester.widget<Icon>(find.byIcon(Icons.check)).semanticLabel, 'xong');
        } else {
          expect(find.text(text), findsOneWidget);
        }
      });
    }

    testWidgets('a tool waiting for the user is open by itself and says so', (tester) async {
      await pumpItem(
        tester,
        tool(
          kind: ToolKind.edit,
          title: 'Edit a.ts',
          end: null,
          permission: MirrorPermissionState.waiting,
          diffs: const [MirrorDiff(path: '/p/a.ts', oldText: 'a', newText: 'b', plus: 1, minus: 1)],
        ),
      );
      expect(find.text('chờ bạn'), findsOneWidget);
      expect(find.textContaining('- a'), findsOneWidget); // its diff shows without a tap
      expect(find.textContaining('+ b'), findsOneWidget);
    });

    testWidgets('what the user chose is written under the card', (tester) async {
      await pumpItem(
        tester,
        tool(permission: MirrorPermissionState.answered, answerKind: PermissionKind.allowOnce, answerName: 'Yes'),
      );
      expect(find.text('Bạn chọn: Cho phép (Yes)'), findsOneWidget);
    });

    testWidgets('a run shows how long it has been going', (tester) async {
      await pumpItem(
        tester,
        tool(
          end: null,
          status: ToolCallStatus.inProgress,
          startedAt: DateTime.now().subtract(const Duration(seconds: 4)),
        ),
      );
      expect(find.textContaining('đang chạy · 4,'), findsOneWidget); // 4,0 s, with the decimal comma
    });

    testWidgets('a run that goes on counts by the page\'s clock, and only its few characters are rebuilt', (
      tester,
    ) async {
      final clock = signal(DateTime(2026, 10, 14, 12));
      await pumpItem(
        tester,
        tool(end: null, status: ToolCallStatus.inProgress, startedAt: DateTime(2026, 10, 14, 11, 59, 58)),
        clock: clock,
      );
      expect(find.text('đang chạy · 2,0 s'), findsOneWidget);
      final rebuilds = trackRebuilds();
      clock.value = DateTime(2026, 10, 14, 12, 0, 3);
      await tester.pump();
      expect(find.text('đang chạy · 5,0 s'), findsOneWidget);
      clock.value = DateTime(2026, 10, 14, 12, 1, 2);
      await tester.pump();
      expect(find.text('đang chạy · 1:04'), findsOneWidget); // after a minute, minutes and seconds
      expect(rebuilds[AiToolCard], isNull);
      expect(rebuilds[AiItemView], isNull);
    });

    testWidgets('a finished tool says "done" in the language of the page, not "ok"', (tester) async {
      await pumpItem(tester, tool(), locale: en);
      expect(tester.widget<Icon>(find.byIcon(Icons.check)).semanticLabel, 'done');
    });

    testWidgets('and in English', (tester) async {
      final clock = signal(DateTime(2026, 10, 14, 12));
      await pumpItem(
        tester,
        tool(end: null, status: ToolCallStatus.inProgress, startedAt: DateTime(2026, 10, 14, 11, 59, 57, 900)),
        locale: en,
        clock: clock,
      );
      expect(find.text('running · 2.1 s'), findsOneWidget);
    });

    testWidgets('a turn ends with its summary', (tester) async {
      await pumpItem(
        tester,
        const MirrorTurnEnd(0, 1, 3, outcome: 'finished', elapsed: Duration(seconds: 41), files: 2, plus: 44, minus: 5),
      );
      expect(find.text('Lượt 3 · 0:41 · 2 tệp đổi +44 −5'), findsOneWidget);
    });

    for (final (outcome, text) in [
      ('cancelled', 'Đã dừng lượt 3 · 0:41'),
      ('interrupted', 'Lượt 3 bị gián đoạn'),
      ('failed', 'Lượt 3 lỗi'),
    ]) {
      testWidgets('a turn that $outcome', (tester) async {
        await pumpItem(tester, MirrorTurnEnd(0, 1, 3, outcome: outcome, elapsed: const Duration(seconds: 41)));
        expect(find.text(text), findsOneWidget);
      });
    }

    testWidgets('a question is a card with its state', (tester) async {
      final request = ElicitationRequest.fromJson({
        'mode': 'form',
        'message': 'Màu nào?',
        'requestedSchema': {'type': 'object', 'properties': <String, Object?>{}},
      });
      await pumpItem(tester, MirrorAsk(0, 1, 1, id: 3, status: 'open', request: request));
      expect(find.text('Màu nào?'), findsOneWidget);
      expect(find.text('Chờ bạn trả lời ở dưới'), findsOneWidget);
      await pumpItem(tester, MirrorAsk(0, 2, 1, id: 3, status: 'accepted', request: request));
      expect(find.text('Đã trả lời'), findsOneWidget);
    });

    testWidgets('a notice is a card', (tester) async {
      await pumpItem(tester, const MirrorNotice(0, 1, 1, kind: 'exited', args: {'k': 'exited', 'code': 1}));
      expect(find.text('Claude dừng bất ngờ (mã thoát 1).'), findsOneWidget);
    });

    testWidgets('a diff of a new file says it is new', (tester) async {
      await pumpItem(
        tester,
        tool(
          kind: ToolKind.edit,
          title: 'Create a.ts',
          diffs: const [MirrorDiff(path: '/p/a.ts', newText: 'x\ny', plus: 2)],
        ),
      );
      await tester.tap(find.text('Tạo a.ts'));
      await tester.pumpAndSettle();
      expect(find.text('a.ts · tệp mới · +2 −0'), findsOneWidget);
    });

    testWidgets('a long output says what is cut', (tester) async {
      await pumpItem(
        tester,
        tool(
          output: const MirrorOutput(head: 'a', tail: 'z', lines: 5000, cut: true),
        ),
      );
      await tester.tap(find.text('Chạy npm test'));
      await tester.pumpAndSettle();
      expect(find.text('5000 dòng; phần giữa xem trên máy tính'), findsOneWidget);
    });
  });

  group('the permission panel (V2-1 D10)', () {
    PermissionOption option(String id, PermissionKind kind, [String name = '']) =>
        PermissionOption(optionId: id, name: name, kind: kind);

    Future<List<String>> pumpPanel(
      WidgetTester tester,
      MirrorPermission permission, {
      bool busy = false,
      VoidCallback? onDetails,

      /// Do not wait for the first 400 ms of the panel: the test is about them.
      bool fresh = false,

      /// Where the answers go: the same list for a panel shown again.
      List<String>? answers,
    }) async {
      answers ??= <String>[];
      final taken = answers;
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        localized(
          Scaffold(
            body: SingleChildScrollView(
              child: AiPermissionPanel(
                permission: permission,
                agentName: 'Claude',
                busy: busy,
                onAnswer: (o) => taken.add(o.optionId),
                onDetails: onDetails,
              ),
            ),
          ),
        ),
      );
      if (!fresh) {
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400)); // a panel that has just appeared waits (below)
      }
      return answers;
    }

    PermissionOption yes() => option('a', PermissionKind.allowOnce, 'Yes');
    double opacityOf(WidgetTester tester, String id) => tester
        .widget<Opacity>(find.ancestor(of: find.byKey(Key('ai.option.$id')), matching: find.byType(Opacity)).first)
        .opacity;

    testWidgets('one big button per option, in the agent\'s order, each at least 52 points high', (tester) async {
      final answers = await pumpPanel(
        tester,
        MirrorPermission(
          id: 1,
          title: 'Edit a.ts',
          more: 2,
          options: [
            option('a', PermissionKind.allowOnce, 'Yes'),
            option('b', PermissionKind.allowAlways, 'Yes, allow all edits'),
            option('c', PermissionKind.rejectOnce, 'No'),
            option('d', PermissionKind.other, 'Tell Claude what to do'),
          ],
        ),
      );
      expect(find.text('Claude xin quyền:'), findsOneWidget);
      expect(find.text('còn 2 yêu cầu'), findsOneWidget);
      final tops = [
        for (final id in ['a', 'b', 'c', 'd']) tester.getTopLeft(find.byKey(Key('ai.option.$id'))).dy,
      ];
      expect(tops, [...tops]..sort());
      for (final id in ['a', 'b', 'c', 'd']) {
        expect(tester.getSize(find.byKey(Key('ai.option.$id'))).height, greaterThanOrEqualTo(52));
      }
      expect(find.text('Tell Claude what to do'), findsOneWidget); // an unknown kind says the agent's own words
      await tester.tap(find.byKey(const Key('ai.option.c')));
      expect(answers, ['c']);
    });

    testWidgets('a button is the same 52 points high on a panel that has just appeared (dimmed, not shrunk)', (
      tester,
    ) async {
      await pumpPanel(tester, MirrorPermission(id: 1, title: 'Edit a.ts', options: [yes()]), fresh: true);
      expect(tester.getSize(find.byKey(const Key('ai.option.a'))).height, greaterThanOrEqualTo(52));
    });

    testWidgets('a tap gives a haptic, a button that waits gives none', (tester) async {
      final haptics = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final permission = MirrorPermission(id: 1, title: 'Edit a.ts', options: [option('a', PermissionKind.allowOnce)]);
      await pumpPanel(tester, permission);
      await tester.tap(find.byKey(const Key('ai.option.a')));
      expect(haptics, ['HapticFeedbackType.lightImpact']); // the spec: "Rung nhẹ khi chạm"
      await pumpPanel(tester, permission, busy: true);
      await tester.tap(find.byKey(const Key('ai.option.a')));
      expect(haptics, hasLength(1));
    });

    testWidgets('busy: no button answers', (tester) async {
      final answers = await pumpPanel(
        tester,
        MirrorPermission(id: 1, title: 'Edit a.ts', options: [option('a', PermissionKind.allowOnce, 'Yes')]),
        busy: true,
      );
      await tester.tap(find.byKey(const Key('ai.option.a')));
      expect(answers, isEmpty);
    });

    testWidgets('busy: a screen reader hears a button that is switched off, not one that works', (tester) async {
      final handle = tester.ensureSemantics();
      // Two buttons, as a request has: each is a node of its own for a screen reader.
      final permission = MirrorPermission(
        id: 1,
        title: 'Edit a.ts',
        options: [yes(), option('b', PermissionKind.rejectOnce, 'No')],
      );
      SemanticsData allowNode() => find.semantics.byLabel(RegExp(r'^Cho phép$')).evaluate().single.getSemanticsData();
      await pumpPanel(tester, permission);
      expect(allowNode().flagsCollection.isButton, isTrue);
      expect(allowNode().flagsCollection.isEnabled.toBoolOrNull(), isTrue);
      expect(allowNode().hasAction(SemanticsAction.tap), isTrue);
      await pumpPanel(tester, permission, busy: true);
      expect(allowNode().flagsCollection.isButton, isTrue);
      expect(allowNode().flagsCollection.isEnabled.toBoolOrNull(), isFalse); // "dimmed", not just "a button"
      expect(allowNode().hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });

    group('a panel that has just appeared waits 400 ms (V2-2 fix round 1: a double tap answers once)', () {
      testWidgets('no button answers in the first 400 ms; they are dimmed meanwhile, and light up at 400', (
        tester,
      ) async {
        final answers = await pumpPanel(
          tester,
          MirrorPermission(id: 1, title: 'Edit a.ts', options: [yes()]),
          fresh: true,
        );
        expect(opacityOf(tester, 'a'), lessThan(1));
        await tester.pump(const Duration(milliseconds: 399));
        await tester.tap(find.byKey(const Key('ai.option.a')));
        await tester.pump();
        expect(answers, isEmpty);
        expect(opacityOf(tester, 'a'), lessThan(1));
        await tester.pump(const Duration(milliseconds: 1));
        expect(opacityOf(tester, 'a'), 1);
        await tester.tap(find.byKey(const Key('ai.option.a')));
        expect(answers, ['a']);
      });

      testWidgets('a tap that waits gives no haptic either', (tester) async {
        final haptics = <Object?>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
          return null;
        });
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        await pumpPanel(tester, MirrorPermission(id: 1, title: 'Edit a.ts', options: [yes()]), fresh: true);
        await tester.tap(find.byKey(const Key('ai.option.a')));
        expect(haptics, isEmpty);
      });

      testWidgets('another request in the same place (the panel is kept) waits again, whoever answered', (
        tester,
      ) async {
        final first = MirrorPermission(id: 1, title: 'Edit a.ts', options: [yes()]);
        final answers = await pumpPanel(tester, first);
        await tester.tap(find.byKey(const Key('ai.option.a')));
        expect(answers, ['a']);
        // The computer shows the next request at once, in the very same place.
        await pumpPanel(
          tester,
          MirrorPermission(id: 2, title: 'Edit b.ts', options: [yes()]),
          fresh: true,
          answers: answers,
        );
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.byKey(const Key('ai.option.a')));
        await tester.pump();
        expect(answers, ['a'], reason: 'the second tap of a double tap answers nothing');
        expect(opacityOf(tester, 'a'), lessThan(1));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(find.byKey(const Key('ai.option.a')));
        expect(answers, ['a', 'a']);
      });

      testWidgets('the same request shown again (the page rebuilt) does not wait again', (tester) async {
        final permission = MirrorPermission(id: 1, title: 'Edit a.ts', options: [yes()]);
        final answers = await pumpPanel(tester, permission);
        await pumpPanel(
          tester,
          MirrorPermission(id: 1, title: 'Edit a.ts', more: 1, options: [yes()]),
          fresh: true,
          answers: answers,
        );
        await tester.tap(find.byKey(const Key('ai.option.a')));
        expect(answers, ['a']);
      });

      testWidgets('after an answer that came back with a refusal the buttons wait once more before they work', (
        tester,
      ) async {
        final permission = MirrorPermission(id: 1, title: 'Edit a.ts', options: [yes()]);
        final answers = await pumpPanel(tester, permission);
        await pumpPanel(tester, permission, busy: true, fresh: true, answers: answers); // the answer is on its way
        await pumpPanel(tester, permission, fresh: true, answers: answers); // ... refused: free, but not at once
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.byKey(const Key('ai.option.a')));
        await tester.pump();
        expect(answers, isEmpty);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(find.byKey(const Key('ai.option.a')));
        expect(answers, ['a']);
      });

      testWidgets('while it is busy, the end of the 400 ms does not light the buttons up', (tester) async {
        final permission = MirrorPermission(id: 1, title: 'Edit a.ts', options: [yes()]);
        final answers = await pumpPanel(tester, permission, busy: true, fresh: true);
        await tester.pump(const Duration(milliseconds: 500));
        expect(opacityOf(tester, 'a'), lessThan(1));
        await tester.tap(find.byKey(const Key('ai.option.a')));
        expect(answers, isEmpty);
      });

      testWidgets('a panel taken away within the 400 ms leaves no timer behind', (tester) async {
        await pumpPanel(tester, MirrorPermission(id: 1, title: 'Edit a.ts', options: [yes()]), fresh: true);
        await tester.pumpWidget(const SizedBox());
        // The test framework fails a test that ends with a timer pending.
      });

      testWidgets('a panel with nothing to tap has nothing to wait for', (tester) async {
        await pumpPanel(tester, const MirrorPermission(id: 1, title: 'Edit a.ts', options: []), fresh: true);
        expect(find.text('Trả lời yêu cầu này trên máy tính.'), findsOneWidget);
      });
    });

    testWidgets('without options: the computer answers, and there is no button', (tester) async {
      await pumpPanel(tester, const MirrorPermission(id: 1, title: 'Edit a.ts', options: []));
      expect(find.text('Trả lời yêu cầu này trên máy tính.'), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('"Xem chi tiết" only when there is a card to show', (tester) async {
      var taps = 0;
      await pumpPanel(
        tester,
        MirrorPermission(id: 1, title: 'Edit a.ts', options: [option('a', PermissionKind.allowOnce)]),
        onDetails: () => taps++,
      );
      await tester.tap(find.byKey(const Key('ai.permission.details')));
      expect(taps, 1);
      await pumpPanel(
        tester,
        MirrorPermission(id: 1, title: 'Edit a.ts', options: [option('a', PermissionKind.allowOnce)]),
      );
      expect(find.byKey(const Key('ai.permission.details')), findsNothing);
    });
  });
}
